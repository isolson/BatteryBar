import Foundation
import Combine

class AppState: ObservableObject {
    @Published var latestReading: BatteryReading?
    @Published var history: [BatteryReading] = []
    let historyStore: HistoryStore

    /// 3-point rolling average for menu bar display
    @Published var smoothedReading: BatteryReading?
    private var recentReadings: [BatteryReading] = []

    private let batteryService: BatteryService
    private var cancellables = Set<AnyCancellable>()

    init(batteryService: BatteryService = BatteryService(), historyStore: HistoryStore = HistoryStore()) {
        self.batteryService = batteryService
        self.historyStore = historyStore
        batteryService.$latestReading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] reading in
                guard let self = self else { return }
                self.latestReading = reading
                guard let reading = reading else {
                    self.recentReadings.removeAll()
                    self.smoothedReading = nil
                    return
                }
                self.historyStore.append(reading)
                self.updateSmoothed(reading)
            }
            .store(in: &cancellables)

        historyStore.$readings
            .receive(on: DispatchQueue.main)
            .assign(to: &$history)
    }

    func start() {
        batteryService.startPolling()
    }

    private func updateSmoothed(_ reading: BatteryReading) {
        if let previous = recentReadings.last {
            let gap = reading.timestamp.timeIntervalSince(previous.timestamp)
            if previous.externalConnected != reading.externalConnected
                || previous.isCharging != reading.isCharging
                || (previous.systemPowerIn == nil) != (reading.systemPowerIn == nil)
                || gap < 0 || gap > 15 {
                recentReadings.removeAll()
            }
        }
        recentReadings.append(reading)
        if recentReadings.count > 3 { recentReadings.removeFirst() }

        // Create a smoothed copy by averaging the power telemetry values
        smoothedReading = BatteryReading(
            id: reading.id,
            timestamp: reading.timestamp,
            currentCapacity: reading.currentCapacity,
            maxCapacity: reading.maxCapacity,
            voltage: reading.voltage,
            amperage: Self.average(recentReadings.map(\.amperage))!,
            instantAmperage: reading.instantAmperage,
            isCharging: reading.isCharging,
            externalConnected: reading.externalConnected,
            cycleCount: reading.cycleCount,
            temperature: reading.temperature,
            avgTimeToFull: reading.avgTimeToFull,
            avgTimeToEmpty: reading.avgTimeToEmpty,
            designCapacity: reading.designCapacity,
            nominalChargeCapacity: reading.nominalChargeCapacity,
            systemPowerIn: Self.average(recentReadings.compactMap(\.systemPowerIn)),
            systemEnergyConsumed: reading.systemEnergyConsumed,
            batteryPower: reading.batteryPower,
            adapterWatts: reading.adapterWatts,
            adapterName: reading.adapterName,
            chargingCurrent: reading.chargingCurrent,
            slowChargingReason: reading.slowChargingReason,
            notChargingReason: reading.notChargingReason,
            thermallyLimited: reading.thermallyLimited,
            adapterEfficiencyLoss: reading.adapterEfficiencyLoss
        )
    }

    /// Divide before adding so all Int values, including both limits, remain safe.
    private static func average(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let count = values.count
        let quotient = values.reduce(0) { $0 + $1 / count }
        let remainder = values.reduce(0) { $0 + $1 % count }
        let result = quotient + remainder / count
        let fraction = remainder % count
        // Match integer division toward zero when the whole and fraction differ in sign.
        if result > 0 && fraction < 0 { return result - 1 }
        if result < 0 && fraction > 0 { return result + 1 }
        return result
    }

    func prepareForTermination() {
        batteryService.stopPolling()
        historyStore.saveToDisk()
    }
}
