import Foundation

/// Downsample readings to a target count while preserving peaks and valleys.
func downsampleForDisplay(_ readings: [BatteryReading], targetCount: Int = 200) -> [BatteryReading] {
    guard readings.count > targetCount else { return readings }

    let step = Double(readings.count) / Double(targetCount)
    var result: [BatteryReading] = []

    // Always keep first and last
    result.append(readings[0])

    var i = 1
    while i < readings.count - 1 {
        let nextI = min(Int(Double(result.count) * step), readings.count - 2)
        if nextI <= i { i += 1; continue }

        // In this window, find the point to keep
        let window = Array(readings[i...nextI])
        if let best = selectRepresentative(window, prev: readings[i - 1], next: readings[min(nextI + 1, readings.count - 1)]) {
            result.append(best)
        }
        i = nextI + 1
    }

    result.append(readings[readings.count - 1])
    return result
}

/// Pick the most representative point from a window.
/// Prefer peaks/valleys (local extrema in consumption or charge).
private func selectRepresentative(_ window: [BatteryReading], prev: BatteryReading, next: BatteryReading) -> BatteryReading? {
    guard !window.isEmpty else { return nil }
    guard window.count > 1 else { return window[0] }

    // Find max and min consumption in window
    var maxCons = window[0], minCons = window[0]
    for r in window {
        if r.consumptionWatts > maxCons.consumptionWatts { maxCons = r }
        if r.consumptionWatts < minCons.consumptionWatts { minCons = r }
    }

    let avgPrevNext = (prev.consumptionWatts + next.consumptionWatts) / 2.0

    // If there's a significant peak, keep it
    if maxCons.consumptionWatts > avgPrevNext * 1.3 {
        return maxCons
    }
    // If there's a significant valley, keep it
    if minCons.consumptionWatts < avgPrevNext * 0.7 {
        return minCons
    }
    // Otherwise keep the middle point
    return window[window.count / 2]
}
