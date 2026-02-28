import Foundation

struct ChartSegment {
    let readings: [BatteryReading]
}

struct GapBridge {
    let from: BatteryReading
    let to: BatteryReading
}

func segmentReadings(_ readings: [BatteryReading], gapThreshold: TimeInterval = 300) -> (segments: [ChartSegment], gaps: [GapBridge]) {
    guard !readings.isEmpty else { return ([], []) }

    var segments: [ChartSegment] = []
    var gaps: [GapBridge] = []
    var current: [BatteryReading] = [readings[0]]

    for i in 1..<readings.count {
        let dt = readings[i].timestamp.timeIntervalSince(readings[i - 1].timestamp)
        if dt > gapThreshold {
            segments.append(ChartSegment(readings: current))
            gaps.append(GapBridge(from: readings[i - 1], to: readings[i]))
            current = [readings[i]]
        } else {
            current.append(readings[i])
        }
    }
    segments.append(ChartSegment(readings: current))
    return (segments, gaps)
}
