import Foundation

enum CrashGuardTests {
    static func runAll() {
        testAllowsUpToThreeRestartsWithinWindow()
        testOlderAttemptsFallOutOfWindow()
        testRecordingRestartTrimsExpiredAttempts()
        testStateRoundTrip()
        testRecoverIfNeededRemovesCleanExitMarker()
        testRecoverIfNeededRelaunchesAndPersistsAttempt()
        testRecoverIfNeededSuppressesWhenBudgetExhausted()
    }

    private static func testAllowsUpToThreeRestartsWithinWindow() {
        let now: TimeInterval = 1_000
        let state = CrashGuard.RestartPolicyState(attempts: [now - 50, now - 20, now - 1])

        assert(CrashGuard.shouldRelaunch(.init(attempts: []), now: now))
        assert(CrashGuard.shouldRelaunch(.init(attempts: [now - 50, now - 20]), now: now))
        assert(!CrashGuard.shouldRelaunch(state, now: now))
    }

    private static func testOlderAttemptsFallOutOfWindow() {
        let now: TimeInterval = 1_000
        let state = CrashGuard.RestartPolicyState(attempts: [now - 120, now - 61, now - 10])
        let normalized = CrashGuard.normalizedState(state, now: now)

        assert(normalized.attempts == [now - 10], "Expected expired attempts to be removed")
        assert(CrashGuard.shouldRelaunch(state, now: now))
    }

    private static func testRecordingRestartTrimsExpiredAttempts() {
        let now: TimeInterval = 1_000
        let state = CrashGuard.RestartPolicyState(attempts: [now - 90, now - 30, now - 5])
        let updated = CrashGuard.stateByRecordingRelaunch(state, now: now)

        assert(updated.attempts == [now - 30, now - 5, now], "Expected only in-window attempts plus the new one")
    }

    private static func testStateRoundTrip() {
        let original = CrashGuard.RestartPolicyState(attempts: [10, 20, 30])
        let contents = CrashGuard.serializeRestartState(original)
        let decoded = CrashGuard.parseRestartState(contents)

        assert(decoded == original, "Expected restart policy state to round-trip through serialization")
    }

    private static func testRecoverIfNeededRemovesCleanExitMarker() {
        let supportDir = makeTempSupportDir()
        defer { try? FileManager.default.removeItem(at: supportDir) }

        let marker = supportDir.appendingPathComponent(".clean_exit")
        FileManager.default.createFile(atPath: marker.path, contents: nil)

        var relaunched = false
        let outcome = CrashGuard.recoverIfNeeded(
            supportDirectory: supportDir,
            bundlePath: "/tmp/BatteryBar.app",
            now: 1_000,
            beforeRelaunch: {},
            relaunch: { _ in relaunched = true }
        )

        assert(outcome == .cleanExit, "Expected helper path to treat marker as a clean exit")
        assert(!FileManager.default.fileExists(atPath: marker.path), "Expected clean-exit marker to be removed")
        assert(!relaunched, "Expected clean exit not to relaunch")
    }

    private static func testRecoverIfNeededRelaunchesAndPersistsAttempt() {
        let supportDir = makeTempSupportDir()
        defer { try? FileManager.default.removeItem(at: supportDir) }

        let stateURL = supportDir.appendingPathComponent(".restart_state")
        CrashGuard.saveRestartState(.init(attempts: [950]), to: stateURL)

        var relaunchedPath: String?
        let outcome = CrashGuard.recoverIfNeeded(
            supportDirectory: supportDir,
            bundlePath: "/tmp/BatteryBar.app",
            now: 1_000,
            beforeRelaunch: {},
            relaunch: { path in relaunchedPath = path }
        )

        let savedState = CrashGuard.loadRestartState(from: stateURL)
        assert(outcome == .relaunched, "Expected recovery path to relaunch when under budget")
        assert(relaunchedPath == "/tmp/BatteryBar.app", "Expected relaunch callback to receive the bundle path")
        assert(savedState.attempts == [950, 1_000], "Expected recovery path to persist the new attempt")
    }

    private static func testRecoverIfNeededSuppressesWhenBudgetExhausted() {
        let supportDir = makeTempSupportDir()
        defer { try? FileManager.default.removeItem(at: supportDir) }

        let stateURL = supportDir.appendingPathComponent(".restart_state")
        let now: TimeInterval = 1_000
        CrashGuard.saveRestartState(.init(attempts: [now - 50, now - 20, now - 1]), to: stateURL)

        var relaunched = false
        let outcome = CrashGuard.recoverIfNeeded(
            supportDirectory: supportDir,
            bundlePath: "/tmp/BatteryBar.app",
            now: now,
            beforeRelaunch: {},
            relaunch: { _ in relaunched = true }
        )

        let savedState = CrashGuard.loadRestartState(from: stateURL)
        assert(outcome == .suppressed, "Expected recovery path to stop relaunching once the budget is exhausted")
        assert(!relaunched, "Expected suppressed recovery not to relaunch")
        assert(savedState.attempts == [now - 50, now - 20, now - 1], "Expected suppression to preserve the normalized in-window attempts")
    }

    private static func makeTempSupportDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        return dir
    }
}
