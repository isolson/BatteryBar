import SwiftUI

struct DetailPanel: View {
    let reading: BatteryReading?
    let history: [BatteryReading]
    let historyStore: HistoryStore
    @State private var showDetails = false
    @State private var timeframe: Timeframe = .oneHour

    private var filteredHistory: [BatteryReading] {
        let filtered = historyStore.readingsForTimeframe(timeframe)
        return downsampleForDisplay(filtered, targetCount: 200)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let r = reading {
                // Header
                HStack(alignment: .firstTextBaseline) {
                    Text("\(r.socPercent)%")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Spacer()
                    Text(statusText(r))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Power pills
                HStack(spacing: 8) {
                    if r.externalConnected {
                        HStack(spacing: 3) {
                            Circle().fill(.green).frame(width: 5, height: 5)
                            Text(BatteryFormatters.formatWatts(r.chargeWatts))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.green)
                        }
                    }
                    HStack(spacing: 3) {
                        Circle().fill(.orange).frame(width: 5, height: 5)
                        Text(BatteryFormatters.formatWatts(r.consumptionWatts))
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                }

                // Timeframe picker
                Picker("", selection: $timeframe) {
                    ForEach(Timeframe.allCases) { tf in
                        Text(tf.rawValue).tag(tf)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                // Graphs
                PowerGraph(history: filteredHistory)
                    .frame(height: 100)

                SOCGraph(history: filteredHistory)
                    .frame(height: 64)

                // Collapsible details
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { showDetails.toggle() } }) {
                    HStack {
                        Text("Details")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(showDetails ? 180 : 0))
                    }
                }
                .buttonStyle(.plain)

                if showDetails {
                    VStack(spacing: 3) {
                        InfoRow(label: "Voltage", value: BatteryFormatters.formatVoltage(r.voltageVolts))
                        InfoRow(label: "Amperage", value: BatteryFormatters.formatAmperage(r.amperageAmps))
                        InfoRow(label: "Temperature", value: BatteryFormatters.formatTemperature(r.temperatureCelsius))
                        InfoRow(label: "Cycles", value: "\(r.cycleCount)")
                        InfoRow(label: "Health", value: BatteryFormatters.formatHealth(r.batteryHealth))
                        InfoRow(label: "Time Left", value: BatteryFormatters.formatTimeRemaining(r.timeRemainingMinutes))
                    }
                    .font(.caption)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

            } else {
                Text("No Battery")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(width: 280)
    }

    private func statusText(_ r: BatteryReading) -> String {
        if r.isCharging { return "Charging" }
        else if r.externalConnected { return "On AC" }
        else { return "On Battery" }
    }
}
