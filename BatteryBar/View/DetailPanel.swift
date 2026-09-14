import SwiftUI

struct DetailPanel: View {
    @ObservedObject var appState: AppState
    @ObservedObject var updateChecker: UpdateChecker
    @State private var showDetails = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let r = appState.smoothedReading {
                // Flow diagram header + verdict
                VStack(spacing: 6) {
                    flowDiagram(r)
                    verdictLine(r)
                }
                .padding(8)
                .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.white.opacity(0.04))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
                            )
                    )

                // Collapsible details
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
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showDetails.toggle() } }

                if showDetails {
                    VStack(spacing: 3) {
                        InfoRow(label: "Voltage", value: BatteryFormatters.formatVoltage(r.voltageVolts))
                        InfoRow(label: "Amperage", value: BatteryFormatters.formatAmperage(r.amperageAmps))
                        InfoRow(label: "Temperature", value: BatteryFormatters.formatTemperature(r.temperatureCelsius))
                        InfoRow(label: "Cycles", value: "\(r.cycleCount)")
                        InfoRow(label: "Health", value: BatteryFormatters.formatHealth(r.batteryHealth))
                    }
                    .font(.caption)

                    // Energy-hungry apps
                    let hogs = topEnergyApps()
                    if !hogs.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Using Significant Energy")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ForEach(hogs) { hog in
                                HStack(spacing: 6) {
                                    if let icon = hog.icon {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .frame(width: 14, height: 14)
                                    }
                                    Text(hog.name)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                            }
                        }
                    }

                    Spacer().frame(height: 0)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

            } else {
                Text("Battery data unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Button("About") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/isolson/BatteryBar")!)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.tertiary)

                Spacer()

                if updateChecker.updateAvailable {
                    Button("Update Available") {
                        if let url = updateChecker.downloadURL {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.blue)

                    Spacer()
                }

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .frame(width: 280)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Flow Diagram

    @ViewBuilder
    private func flowDiagram(_ r: BatteryReading) -> some View {
        let showCharger = r.externalConnected && r.chargeWatts > 0

        Grid(horizontalSpacing: 4, verticalSpacing: 1) {
            GridRow(alignment: .firstTextBaseline) {
                if showCharger {
                    flowValue(icon: "bolt.fill", value: BatteryFormatters.formatWatts(r.chargeWatts))
                        .foregroundStyle(.green)
                        .help("Power flowing from the charger to the battery")
                    flowArrow
                }

                flowValue(icon: batteryIcon(r.socPercent), value: "\(r.socPercent)%")
                    .help("Current battery charge level")
                flowArrow
                flowValue(icon: "cpu", value: BatteryFormatters.formatWatts(r.consumptionWatts))
                    .foregroundStyle(.orange)
                    .help("Power being used by the laptop right now")
            }

            GridRow {
                if showCharger {
                    Text(r.adapterWatts.map { "\($0)W Charger" } ?? "Charger")
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                }
                Text("Battery")
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                Text("System")
            }
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
        }
        .lineLimit(1)
        .fixedSize()
        .frame(maxWidth: .infinity)
    }

    private func flowValue(icon: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 14))
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }

    private var flowArrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }

    // MARK: - Verdict Line

    @ViewBuilder
    private func verdictLine(_ r: BatteryReading) -> some View {
        let bottleneck = r.chargingBottleneck
        let text = BatteryFormatters.bottleneckText(bottleneck)
        let color = BatteryFormatters.bottleneckColor(bottleneck)
        let timeText = BatteryFormatters.formatTimeRemaining(r.timeRemainingMinutes)

        // Show time only when meaningful
        let showTime = timeText != "--" && (r.isCharging || !r.externalConnected)

        HStack {
            if !text.isEmpty {
                HStack(spacing: 4) {
                    Circle()
                        .fill(color)
                        .frame(width: 5, height: 5)
                    Text(text)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            } else if !r.externalConnected {
                Text("On Battery")
                    .foregroundStyle(.secondary)
            } else if r.socPercent >= 100 {
                Text("Fully Charged")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if showTime {
                Text(timeText + (r.isCharging ? " to full" : " left"))
                    .foregroundStyle(.tertiary)
                    .layoutPriority(1)
            }
        }
        .font(.caption)
    }

    // MARK: - Helpers

    private func batteryIcon(_ soc: Int) -> String {
        switch soc {
        case 88...100: return "battery.100percent"
        case 63...87: return "battery.75percent"
        case 38...62: return "battery.50percent"
        case 13...37: return "battery.25percent"
        default: return "battery.0percent"
        }
    }
}
