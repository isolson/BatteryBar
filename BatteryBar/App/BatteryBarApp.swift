import SwiftUI
import Combine

@main
struct BatteryBarApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var updateChecker = UpdateChecker()

    var body: some Scene {
        MenuBarExtra {
            DetailPanel(
                appState: appState,
                updateChecker: updateChecker
            )
            .task { await updateChecker.checkIfNeeded() }
        } label: {
            MenuBarLabel(appState: appState)
        }
        .menuBarExtraStyle(.window)
    }
}

class AppState: ObservableObject {
    @Published var latestReading: BatteryReading?
    @Published var history: [BatteryReading] = []
    let historyStore = HistoryStore()

    /// 3-point rolling average for menu bar display
    @Published var smoothedReading: BatteryReading?
    private var recentReadings: [BatteryReading] = []

    private let batteryService = BatteryService()
    private var cancellables = Set<AnyCancellable>()

    init() {
        batteryService.$latestReading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] reading in
                guard let self = self, let reading = reading else { return }
                self.latestReading = reading
                self.historyStore.append(reading)
                self.updateSmoothed(reading)
            }
            .store(in: &cancellables)

        historyStore.$readings
            .receive(on: DispatchQueue.main)
            .assign(to: &$history)

        batteryService.startPolling()
    }

    private func updateSmoothed(_ reading: BatteryReading) {
        recentReadings.append(reading)
        if recentReadings.count > 3 { recentReadings.removeFirst() }

        // Create a smoothed copy by averaging the power telemetry values
        smoothedReading = BatteryReading(
            id: reading.id,
            timestamp: reading.timestamp,
            currentCapacity: reading.currentCapacity,
            maxCapacity: reading.maxCapacity,
            voltage: reading.voltage,
            amperage: Int(recentReadings.map { Double($0.amperage) }.reduce(0, +) / Double(recentReadings.count)),
            instantAmperage: reading.instantAmperage,
            isCharging: reading.isCharging,
            externalConnected: reading.externalConnected,
            cycleCount: reading.cycleCount,
            temperature: reading.temperature,
            avgTimeToFull: reading.avgTimeToFull,
            avgTimeToEmpty: reading.avgTimeToEmpty,
            designCapacity: reading.designCapacity,
            nominalChargeCapacity: reading.nominalChargeCapacity,
            systemPowerIn: Int(recentReadings.map { Double($0.systemPowerIn) }.reduce(0, +) / Double(recentReadings.count)),
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

    func saveHistory() {
        historyStore.saveToDisk()
    }
}
