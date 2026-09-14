import Foundation
import AppKit

@MainActor
enum BatteryServiceTests {
    private static let properties: [String: Any] = [
        "CurrentCapacity": 77, "MaxCapacity": 100, "Voltage": 12000,
        "Amperage": 1000, "IsCharging": true, "ExternalConnected": true,
        "PowerTelemetryData": ["SystemPowerIn": 30000, "BatteryPower": 12000]
    ]

    static func runAll() async throws {
        testMeasurementLayouts()
        testPackTemperature()
        testUnavailableMeasurements()
        testSignedCurrentAndUnavailablePower()
        testFullChargeStatus()
        try testHistoryCompatibility()
        try await testReadFailureAndRecovery()
        try await testExtremeSmoothing()
        try await testSmoothingTransitions()
        try await testSleepWakeAndStop()
        print("Battery data, history, and polling tests passed.")
    }

    private static func testMeasurementLayouts() {
        var props = properties
        props["Temperature"] = 3032
        props["DesignCapacity"] = 6000
        props["NominalChargeCapacity"] = 5400
        let old = BatteryService.reading(from: props)!
        assert(abs(old.temperatureCelsius! - 30.32) < 0.001)
        assert(old.batteryHealth == 90)

        // macOS 27 on the development Mac supplies capacities in BatteryData.
        props = properties
        props["BatteryData"] = ["DesignCapacity": 6249, "NominalChargeCapacity": 5522]
        let nested = BatteryService.reading(from: props)!
        assert(abs(nested.batteryHealth! - 88.366) < 0.001)
        assert(nested.temperature == nil)
        assert(BatteryFormatters.formatTemperature(nested.temperatureCelsius) == "Unavailable")

        // Existing valid fields take priority; zero is an unavailable measurement.
        props["DesignCapacity"] = 6000
        props["NominalChargeCapacity"] = 5400
        assert(BatteryService.reading(from: props)!.batteryHealth == 90)
        props["DesignCapacity"] = 0
        props["NominalChargeCapacity"] = -1
        assert(BatteryService.reading(from: props)!.designCapacity == 6249)
        assert(BatteryService.reading(from: props)!.nominalChargeCapacity == 5522)

        props["Amperage"] = -1000
        props["IsCharging"] = false
        props["ExternalConnected"] = false
        props["PowerTelemetryData"] = ["BatteryPower": Int64(-12000)]
        let discharge = BatteryService.reading(from: props)!
        assert(discharge.batteryPower == -12000)
        assert(discharge.consumptionWatts == 12)
        props["PowerTelemetryData"] = ["BatteryPower": UInt64(bitPattern: -12000)]
        assert(BatteryService.reading(from: props)!.batteryPower == -12000)
    }

    private static func testPackTemperature() {
        // Captured from AppleSmartBatteryPack.BatteryData on the development Mac.
        // SMC TB1T independently reported 31.7 C for this 3169 registry value.
        let pack: [String: Any] = ["BatteryData": ["Temperature": 3169, "VirtualTemperature": 3169]]
        let reading = BatteryService.reading(from: properties, packs: [pack])!
        assert(abs(reading.temperatureCelsius! - 31.69) < 0.001)
        assert(BatteryFormatters.formatTemperature(reading.temperatureCelsius) == "31.7°C")

        var aggregate = properties
        aggregate["Temperature"] = 3032
        assert(BatteryService.reading(from: aggregate, packs: [pack])!.temperature == 3032)
        aggregate.removeValue(forKey: "Temperature")
        aggregate["BatteryData"] = ["Temperature": 3011]
        assert(BatteryService.reading(from: aggregate, packs: [pack])!.temperature == 3011)

        let coolerPack: [String: Any] = ["Temperature": 2800]
        assert(BatteryService.reading(from: properties, packs: [coolerPack, pack])!.temperature == 3169)
        let noLiveTemperature: [String: Any] = [
            "BatteryData": ["Temperature": 0, "VirtualTemperature": 3169,
                            "AverageTemperature": 240, "MaximumTemperature": 46]
        ]
        assert(BatteryService.reading(from: properties, packs: [noLiveTemperature])!.temperature == nil)
    }

    private static func testUnavailableMeasurements() {
        let reading = BatteryService.reading(from: properties)!
        assert(reading.temperature == nil && reading.designCapacity == nil)
        assert(reading.nominalChargeCapacity == nil && reading.batteryHealth == nil)
        assert(BatteryFormatters.formatHealth(reading.batteryHealth) == "Unavailable")
        assert(BatteryService.reading(from: [:]) == nil)
        var props = properties
        props["BatteryInstalled"] = false
        assert(BatteryService.reading(from: props) == nil)
        props = properties
        props["CurrentCapacity"] = 101
        assert(BatteryService.reading(from: props) == nil)
        props["CurrentCapacity"] = 0
        assert(BatteryService.reading(from: props)!.socPercent == 0)
        props["Temperature"] = 0
        props["DesignCapacity"] = 0
        props["NominalChargeCapacity"] = 0
        let zero = BatteryService.reading(from: props)!
        assert(zero.temperatureCelsius == nil && zero.batteryHealth == nil)
    }

    private static func testFullChargeStatus() {
        var props = properties
        props["CurrentCapacity"] = 99
        props["AvgTimeToFull"] = 12
        let nearFull = BatteryService.reading(from: props)!
        assert(BatteryFormatters.bottleneckText(nearFull.chargingBottleneck) == "Slowing near full")
        assert(nearFull.timeRemainingMinutes == 12)

        // Reported on macOS 27: 100%, still charging, and a nonzero time to full.
        props["CurrentCapacity"] = 100
        let finishing = BatteryService.reading(from: props)!
        assert(BatteryFormatters.bottleneckText(finishing.chargingBottleneck) == "Finishing charge")
        assert(finishing.timeRemainingMinutes == nil, "Do not show time to full at 100%")
        assert(finishing.avgTimeToFull == 12, "Preserve the raw estimate in history")

        props["IsCharging"] = false
        let full = BatteryService.reading(from: props)!
        if case .none = full.chargingBottleneck {} else {
            assertionFailure("A full, idle battery must show the Fully Charged fallback")
        }

        props["ExternalConnected"] = false
        props["AvgTimeToEmpty"] = 180
        let discharging = BatteryService.reading(from: props)!
        assert(discharging.timeRemainingMinutes == 180, "Keep time left on battery at 100%")
        props["AvgTimeToEmpty"] = -1
        assert(BatteryService.reading(from: props)!.timeRemainingMinutes == nil)
        props["AvgTimeToEmpty"] = Int.max
        assert(BatteryService.reading(from: props)!.timeRemainingMinutes == nil)
    }

    private static func testSignedCurrentAndUnavailablePower() {
        var props = properties
        props["Amperage"] = NSNumber(value: UInt64(bitPattern: -1000))
        props["InstantAmperage"] = UInt64(bitPattern: -1250)
        props["IsCharging"] = false
        props["ExternalConnected"] = false
        let signed = BatteryService.reading(from: props)!
        assert(signed.amperage == -1000 && signed.instantAmperage == -1250)
        assert(signed.consumptionWatts == 12)

        props = properties
        props.removeValue(forKey: "PowerTelemetryData")
        let missing = BatteryService.reading(from: props)!
        assert(missing.systemPowerIn == nil && missing.deliveringWatts == nil)
        assert(missing.consumptionWatts == nil)
        assert(BatteryFormatters.formatWatts(missing.deliveringWatts) == "Unavailable")
        assert(BatteryFormatters.formatWattsNumber(missing.consumptionWatts) == "--")
        assert(BatteryFormatters.bottleneckText(missing.chargingBottleneck) == "Detecting…")

        props["Amperage"] = 0
        props["PowerTelemetryData"] = ["SystemPowerIn": 0]
        let zero = BatteryService.reading(from: props)!
        assert(zero.deliveringWatts == 0 && zero.consumptionWatts == 0,
               "A measured zero must remain distinct from unavailable telemetry")
        props["PowerTelemetryData"] = ["SystemPowerIn": -1]
        assert(BatteryService.reading(from: props)!.systemPowerIn == nil)
    }

    private static func testExtremeSmoothing() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var next: [String: Any]? = properties
        let service = BatteryService(readProperties: { next.map { .init(battery: $0) } })
        let state = AppState(batteryService: service,
                             historyStore: HistoryStore(persistenceURL: directory.appendingPathComponent("history.json")))
        let cases: [([Int], Int)] = [
            ([Int.max], Int.max), ([Int.min], Int.min),
            ([Int.max, Int.max, Int.max], Int.max),
            ([Int.min, Int.min, Int.min], Int.min),
            ([Int.max, Int.max, Int.min], Int.max / 3),
            ([Int.min, Int.min, Int.max], Int.min / 3 - 1),
            ([-1, 2], 0), ([1, -2], 0), ([10, 20, 30], 20)
        ]
        for (values, expected) in cases {
            next = nil
            service.readBattery()
            await drainPublications()
            for value in values {
                next = properties
                next?["Amperage"] = value
                next?["PowerTelemetryData"] = ["SystemPowerIn": Int.max]
                service.readBattery()
                await drainPublications()
            }
            assert(state.smoothedReading?.amperage == expected)
            assert(state.smoothedReading?.systemPowerIn == Int.max)
        }
        state.prepareForTermination()
    }

    private static func testSmoothingTransitions() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var next = properties
        let service = BatteryService(readProperties: { .init(battery: next) })
        let state = AppState(batteryService: service,
                             historyStore: HistoryStore(persistenceURL: directory.appendingPathComponent("history.json")))
        service.readBattery()
        await drainPublications()

        next["ExternalConnected"] = false
        next["IsCharging"] = false
        next["Amperage"] = -1000
        service.readBattery()
        await drainPublications()
        assert(state.smoothedReading?.amperage == -1000, "Unplugging must not retain charging current")

        next["ExternalConnected"] = true
        next["IsCharging"] = true
        next["Amperage"] = 2000
        next["PowerTelemetryData"] = ["SystemPowerIn": 60000]
        service.readBattery()
        await drainPublications()
        assert(state.smoothedReading?.systemPowerIn == 60000)
        assert(state.smoothedReading?.amperage == 2000)

        next["IsCharging"] = false
        next["Amperage"] = 0
        service.readBattery()
        await drainPublications()
        assert(state.smoothedReading?.amperage == 0, "Finishing charge must clear the old current")

        next.removeValue(forKey: "PowerTelemetryData")
        service.readBattery()
        await drainPublications()
        assert(state.smoothedReading?.systemPowerIn == nil)
        next["PowerTelemetryData"] = ["SystemPowerIn": 10000]
        service.readBattery()
        await drainPublications()
        assert(state.smoothedReading?.systemPowerIn == 10000)

        var oldJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(service.latestReading!)) as! [String: Any]
        oldJSON["timestamp"] = Date().addingTimeInterval(-120).timeIntervalSinceReferenceDate
        service.latestReading = try JSONDecoder().decode(BatteryReading.self,
                                                        from: JSONSerialization.data(withJSONObject: oldJSON))
        await drainPublications()
        next["PowerTelemetryData"] = ["SystemPowerIn": 50000]
        service.readBattery()
        await drainPublications()
        assert(state.smoothedReading?.systemPowerIn == 50000, "Do not average across a sleep gap")
        state.prepareForTermination()
    }

    private static func testHistoryCompatibility() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.json")
        // The original schema had required numeric measurements and no adapter fields.
        let legacy = """
        [{"id":"36E12CF8-383C-4998-B83E-C48405535F30","timestamp":\(Date().timeIntervalSinceReferenceDate),
        "currentCapacity":77,"maxCapacity":100,"voltage":12000,"amperage":1000,
        "instantAmperage":1000,"isCharging":true,"externalConnected":true,"cycleCount":377,
        "temperature":3032,"avgTimeToFull":52,"avgTimeToEmpty":65535,
        "designCapacity":6000,"nominalChargeCapacity":5400,"systemPowerIn":30000,
        "systemEnergyConsumed":18000,"batteryPower":12000}]
        """
        try legacy.write(to: url, atomically: true, encoding: .utf8)
        do {
            let store = HistoryStore(persistenceURL: url)
            assert(store.readings.count == 1)
            assert(store.readings[0].batteryHealth == 90)
            assert(store.readings[0].temperatureCelsius == 30.32)
            assert(store.readings[0].adapterWatts == nil)
            store.append(BatteryService.reading(from: properties)!)
            store.saveToDisk()
        }
        do {
            let reloaded = HistoryStore(persistenceURL: url)
            assert(reloaded.readings.count == 2)
            assert(reloaded.readings[0].batteryHealth == 90)
            assert(reloaded.readings[1].batteryHealth == nil)
            assert(reloaded.readings[1].temperatureCelsius == nil)
        }
        let zeroLegacy = legacy.replacingOccurrences(of: "\"temperature\":3032", with: "\"temperature\":0")
            .replacingOccurrences(of: "\"designCapacity\":6000", with: "\"designCapacity\":0")
            .replacingOccurrences(of: "\"nominalChargeCapacity\":5400", with: "\"nominalChargeCapacity\":0")
        let zero = try JSONDecoder().decode([BatteryReading].self, from: Data(zeroLegacy.utf8))[0]
        assert(zero.temperatureCelsius == nil && zero.batteryHealth == nil)
    }

    private static func testReadFailureAndRecovery() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var next: [String: Any]? = properties
        let service = BatteryService(readProperties: {
            next.map { BatteryService.RegistryProperties(battery: $0, packs: [["BatteryData": ["Temperature": 3169]]]) }
        })
        let state = AppState(batteryService: service,
                             historyStore: HistoryStore(persistenceURL: directory.appendingPathComponent("history.json")))
        service.readBattery()
        await drainPublications()
        assert(state.latestReading?.socPercent == 77)
        assert(state.smoothedReading?.systemPowerIn == 30000)
        assert(state.smoothedReading?.temperatureCelsius == 31.69)
        assert(state.historyStore.readings.count == 1)

        next = nil
        service.readBattery()
        await drainPublications()
        assert(service.latestReading == nil)
        assert(state.latestReading == nil && state.smoothedReading == nil)
        assert(state.historyStore.readings.count == 1)

        next = properties
        next?["PowerTelemetryData"] = ["SystemPowerIn": 60000]
        service.readBattery()
        await drainPublications()
        assert(state.smoothedReading?.systemPowerIn == 60000, "Do not average stale data into recovered readings")
        assert(state.historyStore.readings.count == 2)
        state.prepareForTermination()
    }

    private static func testSleepWakeAndStop() async throws {
        var polls = 0
        let service = BatteryService(readProperties: {
            polls += 1
            return BatteryService.RegistryProperties(battery: properties)
        })
        service.startPolling(interval: 0.03)
        service.startPolling(interval: 0.03)
        assert(polls == 1, "Starting twice must not add a second poller")
        try await Task.sleep(nanoseconds: 150_000_000)
        assert(polls > 1)
        let center = NSWorkspace.shared.notificationCenter
        center.post(name: NSWorkspace.willSleepNotification, object: nil)
        let beforeSleep = polls
        try await Task.sleep(nanoseconds: 150_000_000)
        assert(polls == beforeSleep, "Pause polling during sleep")
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        assert(polls == beforeSleep + 1, "Read immediately on wake")
        try await Task.sleep(nanoseconds: 150_000_000)
        assert(polls > beforeSleep + 1)
        service.stopPolling()
        let beforeStop = polls
        center.post(name: NSWorkspace.didWakeNotification, object: nil)
        try await Task.sleep(nanoseconds: 150_000_000)
        assert(polls == beforeStop, "Stopping must remove timers and wake observers")
    }

    private static func drainPublications() async {
        // Battery and history publications each queue work on the main thread.
        for _ in 0..<2 {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
    }

    private static func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("batterybar-tests-\(UUID())")
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
