import Foundation
import IOKit
import Combine
import AppKit

class BatteryService: ObservableObject {
    @Published var latestReading: BatteryReading?
    private var timer: Timer?
    private var pollInterval: TimeInterval = 5.0
    private var sleepObserver: Any?
    private var wakeObserver: Any?
    private var isPolling = false
    private let readProperties: () -> [String: Any]?

    init(readProperties: @escaping () -> [String: Any]? = BatteryService.readRegistryProperties) {
        self.readProperties = readProperties
    }

    func startPolling(interval: TimeInterval = 5.0) {
        guard !isPolling else { return }
        isPolling = true
        pollInterval = interval
        readBattery()
        scheduleTimer(interval: interval)

        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.timer?.invalidate()
            self?.timer = nil
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.readBattery()
            self.scheduleTimer(interval: self.pollInterval)
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
        isPolling = false

        if let obs = sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            sleepObserver = nil
        }
        if let obs = wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
            wakeObserver = nil
        }
    }

    private func scheduleTimer(interval: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.readBattery()
        }
    }

    // Polling and publication run on the main run loop.
    func readBattery() {
        latestReading = readProperties().flatMap { Self.reading(from: $0) }
    }

    static func readRegistryProperties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        var propsUnmanaged: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(service, &propsUnmanaged, kCFAllocatorDefault, 0)
        let properties = propsUnmanaged?.takeRetainedValue()
        guard result == KERN_SUCCESS else { return nil }
        return properties as? [String: Any]
    }

    static func reading(from props: [String: Any]) -> BatteryReading? {
        guard props["BatteryInstalled"] as? Bool != false,
              let currentCapacity = props["CurrentCapacity"] as? Int,
              (0...100).contains(currentCapacity) else { return nil }

        let batteryData = props["BatteryData"] as? [String: Any]
        func measurement(_ key: String) -> Int? {
            if let value = props[key] as? Int, value > 0 { return value }
            if let value = batteryData?[key] as? Int, value > 0 { return value }
            return nil
        }

        let telemetry = props["PowerTelemetryData"] as? [String: Any]
        let chargerData = props["ChargerData"] as? [String: Any]

        let signedBatteryPower = telemetry?["BatteryPower"] as? Int64
            ?? Int64(bitPattern: telemetry?["BatteryPower"] as? UInt64 ?? 0)

        // Adapter details: array of dicts, take first entry
        var adapterWatts: Int? = nil
        var adapterName: String? = nil
        if let adapterDetails = props["AppleRawAdapterDetails"] as? [[String: Any]],
           let first = adapterDetails.first {
            adapterWatts = first["Watts"] as? Int
            adapterName = first["Description"] as? String ?? first["Name"] as? String
        }

        return BatteryReading(
            id: UUID(),
            timestamp: Date(),
            currentCapacity: currentCapacity,
            maxCapacity: props["MaxCapacity"] as? Int ?? 100,
            voltage: props["Voltage"] as? Int ?? 0,
            amperage: props["Amperage"] as? Int ?? 0,
            instantAmperage: props["InstantAmperage"] as? Int ?? 0,
            isCharging: props["IsCharging"] as? Bool ?? false,
            externalConnected: props["ExternalConnected"] as? Bool ?? false,
            cycleCount: props["CycleCount"] as? Int ?? 0,
            temperature: measurement("Temperature"),
            avgTimeToFull: props["AvgTimeToFull"] as? Int ?? 65535,
            avgTimeToEmpty: props["AvgTimeToEmpty"] as? Int ?? 65535,
            designCapacity: measurement("DesignCapacity"),
            nominalChargeCapacity: measurement("NominalChargeCapacity"),
            systemPowerIn: telemetry?["SystemPowerIn"] as? Int ?? 0,
            systemEnergyConsumed: telemetry?["SystemEnergyConsumed"] as? Int ?? 0,
            batteryPower: signedBatteryPower,
            adapterWatts: adapterWatts,
            adapterName: adapterName,
            chargingCurrent: chargerData?["ChargingCurrent"] as? Int ?? 0,
            slowChargingReason: chargerData?["SlowChargingReason"] as? Int ?? 0,
            notChargingReason: chargerData?["NotChargingReason"] as? Int ?? 0,
            thermallyLimited: chargerData?["TimeChargingThermallyLimited"] as? Int ?? 0,
            adapterEfficiencyLoss: telemetry?["AdapterEfficiencyLoss"] as? Int ?? 0
        )
    }

    deinit {
        stopPolling()
    }
}
