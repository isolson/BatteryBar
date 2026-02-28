import SwiftUI
import Charts

struct PowerGraph: View {
    let history: [BatteryReading]

    var body: some View {
        let (segments, gaps) = segmentReadings(history)

        VStack(alignment: .leading, spacing: 2) {
            Text("Power")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Chart {
                // Solid lines for continuous segments
                ForEach(Array(segments.enumerated()), id: \.offset) { idx, segment in
                    ForEach(segment.readings) { reading in
                        LineMark(
                            x: .value("Time", reading.timestamp),
                            y: .value("Watts", reading.chargeWatts),
                            series: .value("Type", "Charge-\(idx)")
                        )
                        .foregroundStyle(.green)
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))

                        LineMark(
                            x: .value("Time", reading.timestamp),
                            y: .value("Watts", reading.consumptionWatts),
                            series: .value("Type", "Cons-\(idx)")
                        )
                        .foregroundStyle(.orange)
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                }

                // Dashed lines bridging gaps
                ForEach(Array(gaps.enumerated()), id: \.offset) { idx, gap in
                    LineMark(
                        x: .value("Time", gap.from.timestamp),
                        y: .value("Watts", gap.from.chargeWatts),
                        series: .value("Type", "GapC-\(idx)")
                    )
                    .foregroundStyle(.green.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

                    LineMark(
                        x: .value("Time", gap.to.timestamp),
                        y: .value("Watts", gap.to.chargeWatts),
                        series: .value("Type", "GapC-\(idx)")
                    )
                    .foregroundStyle(.green.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

                    LineMark(
                        x: .value("Time", gap.from.timestamp),
                        y: .value("Watts", gap.from.consumptionWatts),
                        series: .value("Type", "GapO-\(idx)")
                    )
                    .foregroundStyle(.orange.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

                    LineMark(
                        x: .value("Time", gap.to.timestamp),
                        y: .value("Watts", gap.to.consumptionWatts),
                        series: .value("Type", "GapO-\(idx)")
                    )
                    .foregroundStyle(.orange.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) {
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
                        .font(.system(size: 8))
                    AxisGridLine().foregroundStyle(.quaternary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) {
                    AxisValueLabel()
                        .font(.system(size: 8))
                    AxisGridLine().foregroundStyle(.quaternary)
                }
            }
        }
    }
}
