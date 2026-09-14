import Foundation

/// Downsample readings to a target count while preserving peaks and valleys.
func downsampleForDisplay(_ readings: [BatteryReading], targetCount: Int = 200) -> [BatteryReading] {
    guard targetCount > 0 else { return [] }
    guard readings.count > targetCount else { return readings }
    guard targetCount > 1 else { return [readings[readings.count - 1]] }

    // Always keep first and last
    var result = [readings[0]]
    let interiorCount = readings.count - 2
    let bucketCount = targetCount - 2
    if bucketCount > 0 {
        for bucket in 0..<bucketCount {
            let start = 1 + bucket * interiorCount / bucketCount
            let end = 1 + (bucket + 1) * interiorCount / bucketCount
            let window = Array(readings[start..<end])
            if let best = selectRepresentative(window, prev: readings[start - 1], next: readings[end]) {
                result.append(best)
            }
        }
    }

    result.append(readings[readings.count - 1])
    return result
}

/// Pick the most representative point from a window.
/// Prefer peaks/valleys (local extrema in consumption or charge).
private func selectRepresentative(_ window: [BatteryReading], prev: BatteryReading, next: BatteryReading) -> BatteryReading? {
    guard !window.isEmpty else { return nil }
    guard window.count > 1 else { return window[0] }

    // Always preserve charging readings
    var maxCharge = window[0]
    for r in window {
        if r.chargeWatts > maxCharge.chargeWatts { maxCharge = r }
    }
    if maxCharge.isCharging && maxCharge.chargeWatts > 0 {
        return maxCharge
    }

    // Find max and min consumption in window
    let measured = window.compactMap { reading in
        reading.consumptionWatts.map { (reading: reading, watts: $0) }
    }
    guard let maxCons = measured.max(by: { $0.watts < $1.watts }),
          let minCons = measured.min(by: { $0.watts < $1.watts }),
          let previousWatts = prev.consumptionWatts,
          let nextWatts = next.consumptionWatts else { return window[window.count / 2] }
    let avgPrevNext = (previousWatts + nextWatts) / 2.0

    // If there's a significant peak, keep it
    if maxCons.watts > avgPrevNext * 1.3 {
        return maxCons.reading
    }
    // If there's a significant valley, keep it
    if minCons.watts < avgPrevNext * 0.7 {
        return minCons.reading
    }
    // Otherwise keep the middle point
    return window[window.count / 2]
}
