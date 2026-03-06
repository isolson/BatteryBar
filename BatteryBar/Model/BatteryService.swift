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

    func startPolling(interval: TimeInterval = 5.0) {
        pollInterval = interval
        readBattery()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.readBattery()
        }

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
            self.timer = Timer.scheduledTimer(withTimeInterval: self.pollInterval, repeats: true) { [weak self] _ in
                self?.readBattery()
            }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    private func readBattery() {
        let serviceMatch = IOServiceMatching("AppleSmartBattery")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, serviceMatch)
        guard service != IO_OBJECT_NULL else {
            DispatchQueue.main.async { self.latestReading = nil }
            return
        }
        defer { IOObjectRelease(service) }

        var propsUnmanaged: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(service, &propsUnmanaged, kCFAllocatorDefault, 0)
        guard result == KERN_SUCCESS,
              let props = propsUnmanaged?.takeRetainedValue() as? [String: Any] else { return }

        let telemetry = props["PowerTelemetryData"] as? [String: Any]
        let chargerData = props["ChargerData"] as? [String: Any]

        let rawBatteryPower = telemetry?["BatteryPower"] as? UInt64 ?? 0
        let signedBatteryPower = Int64(bitPattern: rawBatteryPower)

        // Adapter details: array of dicts, take first entry
        var adapterWatts: Int? = nil
        var adapterName: String? = nil
        if let adapterDetails = props["AppleRawAdapterDetails"] as? [[String: Any]],
           let first = adapterDetails.first {
            adapterWatts = first["Watts"] as? Int
            adapterName = first["Description"] as? String ?? first["Name"] as? String
        }

        let reading = BatteryReading(
            id: UUID(),
            timestamp: Date(),
            currentCapacity: props["CurrentCapacity"] as? Int ?? 0,
            maxCapacity: props["MaxCapacity"] as? Int ?? 100,
            voltage: props["Voltage"] as? Int ?? 0,
            amperage: props["Amperage"] as? Int ?? 0,
            instantAmperage: props["InstantAmperage"] as? Int ?? 0,
            isCharging: props["IsCharging"] as? Bool ?? false,
            externalConnected: props["ExternalConnected"] as? Bool ?? false,
            cycleCount: props["CycleCount"] as? Int ?? 0,
            temperature: props["Temperature"] as? Int ?? 0,
            avgTimeToFull: props["AvgTimeToFull"] as? Int ?? 65535,
            avgTimeToEmpty: props["AvgTimeToEmpty"] as? Int ?? 65535,
            designCapacity: props["DesignCapacity"] as? Int ?? 0,
            nominalChargeCapacity: props["NominalChargeCapacity"] as? Int ?? 0,
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

        DispatchQueue.main.async {
            self.latestReading = reading
        }
    }

    deinit {
        if let obs = sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(obs) }
        if let obs = wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(obs) }
    }
}
