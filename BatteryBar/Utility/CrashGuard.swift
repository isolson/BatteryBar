import Foundation

/// Spawns a lightweight watcher process that relaunches the app after a crash.
///
/// On launch, the watcher polls `kill -0 <pid>` every 2 seconds. When the main
/// process exits, it invokes the app binary in a helper mode that checks for a
/// `.clean_exit` sentinel file, consults a small restart state file, and only
/// relaunches if the crash budget has not been exhausted.
enum CrashGuard {
    struct RestartPolicyState: Equatable {
        var attempts: [TimeInterval] = []
    }

    enum RecoveryOutcome: Equatable {
        case cleanExit
        case relaunched
        case suppressed
    }

    static let maxRestartAttempts = 3
    static let restartWindow: TimeInterval = 60
    private static let helperArgument = "--crashguard-recover"

    private static let supportDir: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("BatteryBar")
    }()

    private static let cleanExitURL = supportDir.appendingPathComponent(".clean_exit")
    private static let restartStateURL = supportDir.appendingPathComponent(".restart_state")

    @discardableResult
    static func handleHelperInvocationIfNeeded(arguments: [String] = CommandLine.arguments) -> Bool {
        guard arguments.dropFirst().contains(helperArgument) else { return false }
        _ = recoverIfNeeded()
        Foundation.exit(0)
    }

    /// Call once at app launch to start the background watcher.
    static func install() {
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true, attributes: nil)
        try? FileManager.default.removeItem(at: cleanExitURL)

        guard let executablePath = Bundle.main.executablePath else { return }

        let helperExecutable = shellQuote(executablePath)
        let pid = ProcessInfo.processInfo.processIdentifier

        let script = """
        while kill -0 \(pid) 2>/dev/null; do
            sleep 2
        done
        exec \(helperExecutable) \(helperArgument)
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try? process.run()
    }

    /// Call before any intentional termination so the watcher doesn't relaunch.
    static func markCleanExit() {
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true, attributes: nil)
        FileManager.default.createFile(atPath: cleanExitURL.path, contents: nil)
        resetRestartState()
    }

    @discardableResult
    static func recoverIfNeeded(
        supportDirectory: URL = supportDir,
        bundlePath: String = Bundle.main.bundlePath,
        now: TimeInterval = Date().timeIntervalSince1970,
        beforeRelaunch: () -> Void = { Thread.sleep(forTimeInterval: 1) },
        relaunch: (String) -> Void = relaunchApp
    ) -> RecoveryOutcome {
        let cleanExitURL = cleanExitURL(in: supportDirectory)
        let restartStateURL = restartStateURL(in: supportDirectory)

        if FileManager.default.fileExists(atPath: cleanExitURL.path) {
            try? FileManager.default.removeItem(at: cleanExitURL)
            return .cleanExit
        }

        let state = normalizedState(loadRestartState(from: restartStateURL), now: now)
        guard shouldRelaunch(state, now: now) else {
            saveRestartState(state, to: restartStateURL)
            return .suppressed
        }

        let updatedState = stateByRecordingRelaunch(state, now: now)
        saveRestartState(updatedState, to: restartStateURL)

        beforeRelaunch()
        relaunch(bundlePath)
        return .relaunched
    }

    static func normalizedState(_ state: RestartPolicyState, now: TimeInterval) -> RestartPolicyState {
        let cutoff = now - restartWindow
        return RestartPolicyState(attempts: state.attempts.filter { $0 >= cutoff }.sorted())
    }

    static func shouldRelaunch(_ state: RestartPolicyState, now: TimeInterval) -> Bool {
        normalizedState(state, now: now).attempts.count < maxRestartAttempts
    }

    static func stateByRecordingRelaunch(_ state: RestartPolicyState, now: TimeInterval) -> RestartPolicyState {
        var trimmed = normalizedState(state, now: now)
        trimmed.attempts.append(now)
        return trimmed
    }

    static func loadRestartState() -> RestartPolicyState {
        loadRestartState(from: restartStateURL)
    }

    static func loadRestartState(from url: URL) -> RestartPolicyState {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return RestartPolicyState()
        }
        return parseRestartState(contents)
    }

    static func saveRestartState(_ state: RestartPolicyState) {
        saveRestartState(state, to: restartStateURL)
    }

    static func saveRestartState(_ state: RestartPolicyState, to url: URL) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try? serializeRestartState(state).write(to: url, atomically: true, encoding: .utf8)
    }

    static func resetRestartState() {
        try? FileManager.default.removeItem(at: restartStateURL)
    }

    static func parseRestartState(_ contents: String) -> RestartPolicyState {
        let attempts = contents
            .split(whereSeparator: \.isNewline)
            .compactMap { TimeInterval(String($0)) }
        return RestartPolicyState(attempts: attempts)
    }

    static func serializeRestartState(_ state: RestartPolicyState) -> String {
        let trimmed = state.attempts.sorted().map { String(Int($0.rounded(.down))) }
        guard !trimmed.isEmpty else { return "" }
        return trimmed.joined(separator: "\n") + "\n"
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private static func cleanExitURL(in supportDirectory: URL) -> URL {
        supportDirectory.appendingPathComponent(".clean_exit")
    }

    private static func restartStateURL(in supportDirectory: URL) -> URL {
        supportDirectory.appendingPathComponent(".restart_state")
    }

    private static func relaunchApp(at bundlePath: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [bundlePath]
        try? process.run()
    }
}
