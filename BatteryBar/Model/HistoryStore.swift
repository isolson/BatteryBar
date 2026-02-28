import Foundation
import AppKit

class HistoryStore: ObservableObject {
    @Published private(set) var readings: [BatteryReading] = []
    private let persistenceURL: URL
    private var saveTimer: Timer?
    private var resignObserver: Any?

    // 7 days max. Downsampling keeps this manageable:
    // ~720 (1h@5s) + ~1380 (23h@1min) + ~1728 (6d@5min) ≈ 3828 max
    private let maxAge: TimeInterval = 7 * 24 * 3600

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("BatteryBar")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        persistenceURL = appDir.appendingPathComponent("history.json")
        loadFromDisk()
        startPeriodicSave()

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.saveToDisk()
        }
    }

    func append(_ reading: BatteryReading) {
        readings.append(reading)
        pruneAndDownsample()
    }

    func saveToDisk() {
        do {
            let data = try JSONEncoder().encode(readings)
            try data.write(to: persistenceURL, options: .atomic)
        } catch {
            print("BatteryBar: Failed to save history: \(error)")
        }
    }

    func readingsForTimeframe(_ timeframe: Timeframe) -> [BatteryReading] {
        let cutoff = Date().addingTimeInterval(-timeframe.seconds)
        return readings.filter { $0.timestamp > cutoff }
    }

    // MARK: - Downsampling

    private func pruneAndDownsample() {
        let now = Date()

        // Remove anything older than 7 days
        readings.removeAll { now.timeIntervalSince($0.timestamp) > maxAge }

        // Downsample: entries older than 24h → keep 1 per 5min
        downsampleRange(olderThan: 24 * 3600, interval: 300, now: now)
        // Entries older than 1h → keep 1 per 1min
        downsampleRange(olderThan: 3600, interval: 60, now: now)
    }

    private func downsampleRange(olderThan ageThreshold: TimeInterval, interval: TimeInterval, now: Date) {
        let cutoff = now.addingTimeInterval(-ageThreshold)
        let oldIndices = readings.indices.filter { readings[$0].timestamp < cutoff }
        guard oldIndices.count > 1 else { return }

        // Group old readings into buckets by interval
        var buckets: [[Int]] = []
        var currentBucket: [Int] = [oldIndices[0]]
        var bucketStart = readings[oldIndices[0]].timestamp

        for i in 1..<oldIndices.count {
            let idx = oldIndices[i]
            if readings[idx].timestamp.timeIntervalSince(bucketStart) < interval {
                currentBucket.append(idx)
            } else {
                buckets.append(currentBucket)
                currentBucket = [idx]
                bucketStart = readings[idx].timestamp
            }
        }
        buckets.append(currentBucket)

        // For each bucket with multiple entries, keep only the one closest to bucket midpoint
        // But also keep any local peaks/valleys
        var indicesToRemove = Set<Int>()
        for bucket in buckets where bucket.count > 1 {
            let keepIdx = bucket[bucket.count / 2] // keep middle entry
            for idx in bucket where idx != keepIdx {
                indicesToRemove.insert(idx)
            }
        }

        if !indicesToRemove.isEmpty {
            readings = readings.enumerated()
                .filter { !indicesToRemove.contains($0.offset) }
                .map { $0.element }
        }
    }

    // MARK: - Persistence

    private func startPeriodicSave() {
        saveTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.saveToDisk()
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: persistenceURL.path) else { return }
        do {
            let data = try Data(contentsOf: persistenceURL)
            let loaded = try JSONDecoder().decode([BatteryReading].self, from: data)
            let cutoff = Date().addingTimeInterval(-maxAge)
            readings = loaded.filter { $0.timestamp > cutoff }
        } catch {
            print("BatteryBar: Failed to load history: \(error)")
        }
    }

    deinit {
        saveTimer?.invalidate()
        if let obs = resignObserver { NotificationCenter.default.removeObserver(obs) }
        saveToDisk()
    }
}

enum Timeframe: String, CaseIterable, Identifiable {
    case oneHour = "1h"
    case twelveHours = "12h"
    case oneDay = "24h"
    case sevenDays = "7d"

    var id: String { rawValue }

    var seconds: TimeInterval {
        switch self {
        case .oneHour: return 3600
        case .twelveHours: return 12 * 3600
        case .oneDay: return 24 * 3600
        case .sevenDays: return 7 * 24 * 3600
        }
    }
}
