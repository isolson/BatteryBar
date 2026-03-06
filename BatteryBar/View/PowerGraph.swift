import SwiftUI
import Charts

// MARK: - Colors

private let activeBlue = Color(red: 0.30, green: 0.55, blue: 1.0)
private let activeCyan = Color(red: 0.35, green: 0.75, blue: 1.0)
private let chargingGreen = Color(red: 0.30, green: 0.85, blue: 0.45)
private let sleepIndigo = Color(red: 0.25, green: 0.25, blue: 0.65)

// MARK: - SOC Smoothing

/// Smooth integer SOC values into fractional values to eliminate stair-stepping.
private func smoothedSOCValues(_ readings: [BatteryReading]) -> [Double] {
    var vals = readings.map { Double($0.socPercent) }
    guard vals.count >= 3 else { return vals }
    for _ in 0..<6 {
        var next = vals
        for i in 1..<vals.count - 1 {
            next[i] = vals[i-1] * 0.2 + vals[i] * 0.6 + vals[i+1] * 0.2
        }
        vals = next
    }
    return vals
}

// MARK: - Catmull-Rom Spline

/// Build a smooth Catmull-Rom spline path through the given screen-space points.
private func catmullRomPath(_ points: [CGPoint]) -> Path {
    var path = Path()
    guard points.count >= 2 else { return path }

    path.move(to: points[0])

    if points.count == 2 {
        path.addLine(to: points[1])
        return path
    }

    for i in 0..<points.count - 1 {
        let p0 = points[max(i - 1, 0)]
        let p1 = points[i]
        let p2 = points[min(i + 1, points.count - 1)]
        let p3 = points[min(i + 2, points.count - 1)]

        // Catmull-Rom → cubic Bezier control points (tension = 1.0)
        // Clamp X so the curve never goes backward in time
        let cp1 = CGPoint(
            x: min(max(p1.x + (p2.x - p0.x) / 6.0, p1.x), p2.x),
            y: p1.y + (p2.y - p0.y) / 6.0
        )
        let cp2 = CGPoint(
            x: min(max(p2.x - (p3.x - p1.x) / 6.0, p1.x), p2.x),
            y: p2.y - (p3.y - p1.y) / 6.0
        )

        path.addCurve(to: p2, control1: cp1, control2: cp2)
    }

    return path
}

// MARK: - Segment Extraction

private enum SegmentType: Equatable {
    case charging
    case onBattery
}

private struct GraphSegment {
    let type: SegmentType
    let startIndex: Int
    let endIndex: Int // inclusive
}

/// Group consecutive readings into charging vs on-battery segments.
/// Time gaps (sleep) and idle readings get only the baseline.
private func extractSegments(_ readings: [BatteryReading], gapThreshold: TimeInterval = 180) -> [GraphSegment] {
    guard !readings.isEmpty else { return [] }

    var segments: [GraphSegment] = []
    var currentType: SegmentType?
    var segStart = 0

    for i in 0..<readings.count {
        let r = readings[i]

        // Detect sleep: time gap from previous reading exceeds threshold
        let isGap = i > 0 && r.timestamp.timeIntervalSince(readings[i - 1].timestamp) > gapThreshold

        let type: SegmentType?
        if isGap {
            type = nil // gap = sleep, baseline only
        } else if r.isCharging && r.chargeWatts > 0.5 {
            type = .charging
        } else if !r.externalConnected && r.consumptionWatts > 0.5 {
            type = .onBattery
        } else {
            type = nil // idle — baseline only
        }

        if type != currentType {
            // Close previous segment
            if let ct = currentType, i > segStart {
                segments.append(GraphSegment(type: ct, startIndex: segStart, endIndex: i - 1))
            }
            currentType = type
            segStart = i
        }
    }

    // Close final segment
    if let ct = currentType {
        segments.append(GraphSegment(type: ct, startIndex: segStart, endIndex: readings.count - 1))
    }

    return segments
}


// MARK: - Graph View

struct BatteryGraph: View {
    let history: [BatteryReading]
    @State private var hoveredReading: BatteryReading? = nil

    private let baseWidth: CGFloat = 4
    private let maxExtraWidth: CGFloat = 14

    var body: some View {
        let now = Date(timeIntervalSinceReferenceDate: (Date().timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
        let windowStart = now.addingTimeInterval(-3 * 3600)
        let smoothed = smoothedSOCValues(history)

        // Compute max values for normalization
        let maxChargeW = max(history.map { $0.chargeWatts }.max() ?? 1, 1)
        let maxConsumptionW = max(history.map { $0.consumptionWatts }.max() ?? 1, 1)

        // Empty chart for axis labels + coordinate system
        Chart {
            // Invisible point to establish the domain (Chart needs at least one mark)
            RuleMark(y: .value("", 0))
                .foregroundStyle(.clear)

            if let hovered = hoveredReading {
                RuleMark(x: .value("Time", hovered.timestamp))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
        }
        .chartLegend(.hidden)
        .chartYScale(domain: 0...100)
        .chartXScale(domain: windowStart...now)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) {
                AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .abbreviated)))
                    .font(.system(size: 8))
            }
        }
        .chartYAxis(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geo in
                let plotFrame = geo[proxy.plotAreaFrame]

                // Convert data points to screen coordinates
                let screenPoints: [CGPoint] = history.enumerated().compactMap { i, r in
                    guard let x = proxy.position(forX: r.timestamp),
                          let y = proxy.position(forY: smoothed[i]) else { return nil }
                    return CGPoint(x: plotFrame.origin.x + x, y: plotFrame.origin.y + y)
                }

                // Layer 1 (back): Baseline SOC curve — constant width, always drawn
                if screenPoints.count >= 2 {
                    catmullRomPath(screenPoints)
                        .stroke(
                            sleepIndigo,
                            style: StrokeStyle(lineWidth: baseWidth, lineCap: .round, lineJoin: .round)
                        )
                }

                // Layer 2: Consumption bars — vertical bars dropping down from SOC line
                // Layer 3: Charging stroke — wider stroke along SOC line
                Canvas { ctx, size in
                    guard screenPoints.count >= 2 else { return }
                    let segments = extractSegments(history)
                    let maxBarHeight: CGFloat = 20

                    for seg in segments {
                        guard seg.endIndex >= seg.startIndex else { continue }

                        switch seg.type {
                        case .onBattery:
                            // Draw individual bars at each data point
                            for idx in seg.startIndex...seg.endIndex {
                                let pt = screenPoints[idx]
                                let r = history[idx]
                                let ratio = CGFloat(min(r.consumptionWatts / maxConsumptionW, 1.0))
                                let barHeight = max(ratio * maxBarHeight, 2)

                                // Bar width: fill the gap to the next point (or from previous)
                                let leftX: CGFloat
                                let rightX: CGFloat
                                if idx > seg.startIndex && idx < seg.endIndex {
                                    leftX = (screenPoints[idx - 1].x + pt.x) / 2
                                    rightX = (pt.x + screenPoints[idx + 1].x) / 2
                                } else if idx > seg.startIndex {
                                    leftX = (screenPoints[idx - 1].x + pt.x) / 2
                                    rightX = pt.x + (pt.x - leftX)
                                } else if idx < seg.endIndex {
                                    rightX = (pt.x + screenPoints[idx + 1].x) / 2
                                    leftX = pt.x - (rightX - pt.x)
                                } else {
                                    leftX = pt.x - 2
                                    rightX = pt.x + 2
                                }

                                let barRect = CGRect(
                                    x: leftX,
                                    y: pt.y,
                                    width: rightX - leftX,
                                    height: barHeight
                                )
                                let barPath = Path(roundedRect: barRect, cornerRadius: 1)
                                ctx.fill(barPath, with: .color(activeBlue.opacity(0.5)))
                            }

                        case .charging:
                            // Draw individual bars going UP from SOC line
                            for idx in seg.startIndex...seg.endIndex {
                                let pt = screenPoints[idx]
                                let r = history[idx]
                                let ratio = CGFloat(min(r.chargeWatts / maxChargeW, 1.0))
                                let barHeight = max(ratio * maxBarHeight, 2)

                                let leftX: CGFloat
                                let rightX: CGFloat
                                if idx > seg.startIndex && idx < seg.endIndex {
                                    leftX = (screenPoints[idx - 1].x + pt.x) / 2
                                    rightX = (pt.x + screenPoints[idx + 1].x) / 2
                                } else if idx > seg.startIndex {
                                    leftX = (screenPoints[idx - 1].x + pt.x) / 2
                                    rightX = pt.x + (pt.x - leftX)
                                } else if idx < seg.endIndex {
                                    rightX = (pt.x + screenPoints[idx + 1].x) / 2
                                    leftX = pt.x - (rightX - pt.x)
                                } else {
                                    leftX = pt.x - 2
                                    rightX = pt.x + 2
                                }

                                let barRect = CGRect(
                                    x: leftX,
                                    y: pt.y - barHeight,
                                    width: rightX - leftX,
                                    height: barHeight
                                )
                                let barPath = Path(roundedRect: barRect, cornerRadius: 1)
                                ctx.fill(barPath, with: .color(chargingGreen.opacity(0.5)))
                            }
                        }
                    }
                }
                .allowsHitTesting(false)

                // Hover detection
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let loc):
                            let xInPlot = loc.x - plotFrame.origin.x
                            guard xInPlot >= 0, xInPlot <= plotFrame.width else {
                                hoveredReading = nil
                                return
                            }
                            if let date: Date = proxy.value(atX: xInPlot) {
                                hoveredReading = history.min(by: {
                                    abs($0.timestamp.timeIntervalSince(date)) <
                                    abs($1.timestamp.timeIntervalSince(date))
                                })
                            }
                        case .ended:
                            hoveredReading = nil
                        }
                    }
            }
        }
        .overlay(alignment: .topLeading) {
            if let r = hoveredReading {
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.timestamp, format: .dateTime.hour().minute())
                        .foregroundStyle(.secondary)
                    Text("Battery: \(r.socPercent)%")
                        .foregroundStyle(.green)
                    if r.chargeWatts > 0 {
                        Text("Charging: \(BatteryFormatters.formatWatts(r.chargeWatts))")
                            .foregroundStyle(.orange)
                    }
                    Text("Using: \(BatteryFormatters.formatWatts(r.consumptionWatts))")
                        .foregroundStyle(activeCyan)
                }
                .font(.system(size: 9))
                .padding(6)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}
