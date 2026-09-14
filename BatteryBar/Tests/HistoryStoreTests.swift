import Foundation
import Darwin

@MainActor
enum HistoryStoreTests {
    private static let properties: [String: Any] = [
        "CurrentCapacity": 50, "Voltage": 12000, "Amperage": -1000,
        "ExternalConnected": false, "IsCharging": false
    ]

    static func runAll() throws {
        try testPartialRecoveryAndBackup()
        try testTruncatedFileBackup()
        try testFailedBackupDisablesSaves()
        try testTimestampValidationAndOrdering()
        try testStorageBounds()
        testDisplayDownsampling()
        print("History recovery, storage bounds, and downsampling tests passed.")
    }

    private static func testPartialRecoveryAndBackup() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.json")
        let first = BatteryService.reading(from: properties)!
        let second = BatteryService.reading(from: properties)!
        var entries = try JSONSerialization.jsonObject(with: JSONEncoder().encode([first, second])) as! [[String: Any]]
        entries.insert(["amperage": "invalid"], at: 1)
        let original = try JSONSerialization.data(withJSONObject: entries)
        try original.write(to: url)
        do {
            let store = HistoryStore(persistenceURL: url)
            assert(store.readings.map(\.id) == [first.id, second.id])
            store.saveToDisk()
            let saved = try JSONDecoder().decode([BatteryReading].self, from: Data(contentsOf: url))
            assert(saved.count == 2)
            assert(tryBackup(in: directory) == original, "Keep the original file before writing recovered records")
        }
    }

    private static func testTruncatedFileBackup() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.json")
        let original = Data("[{\"id\":".utf8)
        try original.write(to: url)
        do {
            let store = HistoryStore(persistenceURL: url)
            assert(store.readings.isEmpty)
            store.append(BatteryService.reading(from: properties)!)
            store.saveToDisk()
            assert(tryBackup(in: directory) == original)
            let recovered = try JSONDecoder().decode([BatteryReading].self, from: Data(contentsOf: url))
            assert(recovered.count == 1)
        }
    }

    private static func testTimestampValidationAndOrdering() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.json")
        let now = Date().timeIntervalSinceReferenceDate
        let timestamps = [now - 5, 1e300, now - 20, now - 10, now - 8 * 24 * 3600]
        var entries = try JSONSerialization.jsonObject(with: JSONEncoder().encode(
            timestamps.map { _ in BatteryService.reading(from: properties)! }
        )) as! [[String: Any]]
        for index in entries.indices { entries[index]["timestamp"] = timestamps[index] }
        let original = try JSONSerialization.data(withJSONObject: entries)
        try original.write(to: url)
        do {
            let store = HistoryStore(persistenceURL: url)
            assert(store.readings.map { $0.timestamp.timeIntervalSinceReferenceDate } == [now - 20, now - 10, now - 5])
            assert(tryBackup(in: directory) == original)
        }
    }

    private static func testFailedBackupDisablesSaves() throws {
        guard geteuid() != 0 else { return } // Root can bypass the permission premise.
        let directory = try temporaryDirectory()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        let url = directory.appendingPathComponent("history.json")
        let original = Data("[{\"id\":".utf8)
        try original.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        do {
            let store = HistoryStore(persistenceURL: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            store.append(BatteryService.reading(from: properties)!)
            store.saveToDisk()
            let retained = try Data(contentsOf: url)
            assert(retained == original, "A failed backup must disable later saves even after permissions recover")
        }
    }

    private static func testStorageBounds() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.json")
        let oversized = Data(repeating: 32, count: 16 * 1024 * 1024 + 1)
        try oversized.write(to: url)
        do {
            let store = HistoryStore(persistenceURL: url)
            assert(store.readings.isEmpty)
            store.append(BatteryService.reading(from: properties)!)
            store.saveToDisk()
            let retained = try Data(contentsOf: url)
            assert(retained == oversized, "Never replace an unprocessed oversized file")
        }

        let many = (0..<10_001).map { _ in BatteryService.reading(from: properties)! }
        var entries = try JSONSerialization.jsonObject(with: JSONEncoder().encode(many)) as! [[String: Any]]
        let start = Date().timeIntervalSinceReferenceDate.rounded(.down) - 3000
        for index in entries.indices { entries[index]["timestamp"] = start + Double(index) / 4 }
        try JSONSerialization.data(withJSONObject: entries).write(to: url)
        do {
            let store = HistoryStore(persistenceURL: url)
            assert(store.readings.count == 10_000, "Expected 10,000 retained records, got \(store.readings.count)")
            assert(store.readings.first?.id == many[1].id)
            assert(store.readings.last?.id == many.last?.id)
        }
    }

    private static func testDisplayDownsampling() {
        let readings = (0..<200).map { _ in BatteryService.reading(from: properties)! }
        assert(downsampleForDisplay(readings, targetCount: 0).isEmpty)
        assert(downsampleForDisplay(readings, targetCount: Int.min).isEmpty)
        assert(downsampleForDisplay([], targetCount: 10).isEmpty)
        assert(downsampleForDisplay(readings, targetCount: 1).first?.id == readings.last?.id)
        for count in [31, 45, 60, 200] {
            let sample = Array(readings.prefix(count))
            let result = downsampleForDisplay(sample, targetCount: 30)
            assert(result.count == 30, "Use every display bucket, even when there are fewer than two inputs per bucket")
            assert(result.first?.id == sample.first?.id && result.last?.id == sample.last?.id)
            assert(Set(result.map(\.id)).count == result.count)
        }
        var peakProperties = properties
        peakProperties["Amperage"] = -9000
        let peak = BatteryService.reading(from: peakProperties)!
        var withPeak = readings
        withPeak[50] = peak
        assert(downsampleForDisplay(withPeak, targetCount: 30).contains { $0.id == peak.id })
    }

    private static func tryBackup(in directory: URL) -> Data? {
        let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        guard let backup = files?.first(where: { $0.lastPathComponent.contains(".unreadable-") }) else { return nil }
        return try? Data(contentsOf: backup)
    }

    private static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("batterybar-history-tests-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
