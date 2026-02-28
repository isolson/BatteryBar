import SwiftUI
import Charts

struct SOCGraph: View {
    let history: [BatteryReading]

    var body: some View {
        let (segments, gaps) = segmentReadings(history)

        VStack(alignment: .leading, spacing: 2) {
            Text("Charge")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Chart {
                ForEach(Array(segments.enumerated()), id: \.offset) { idx, segment in
                    ForEach(segment.readings) { reading in
                        AreaMark(
                            x: .value("Time", reading.timestamp),
                            y: .value("SOC", reading.socPercent),
                            series: .value("Seg", "A-\(idx)")
                        )
                        .foregroundStyle(
                            .linearGradient(
                                colors: [.blue.opacity(0.2), .blue.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                        LineMark(
                            x: .value("Time", reading.timestamp),
                            y: .value("SOC", reading.socPercent),
                            series: .value("Seg", "L-\(idx)")
                        )
                        .foregroundStyle(.blue)
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                }

                ForEach(Array(gaps.enumerated()), id: \.offset) { idx, gap in
                    LineMark(
                        x: .value("Time", gap.from.timestamp),
                        y: .value("SOC", gap.from.socPercent),
                        series: .value("Seg", "Gap-\(idx)")
                    )
                    .foregroundStyle(.blue.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

                    LineMark(
                        x: .value("Time", gap.to.timestamp),
                        y: .value("SOC", gap.to.socPercent),
                        series: .value("Seg", "Gap-\(idx)")
                    )
                    .foregroundStyle(.blue.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            .chartYScale(domain: 0...100)
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
