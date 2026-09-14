import Foundation
import Darwin

/// Spawns a lightweight watcher process that relaunches the app after a crash.
///
/// On launch, the watcher polls `kill -0 <pid>` every 2 seconds. When the main
/// process exits, it invokes the app binary in a helper mode that checks for a
/// per-launch clean-exit marker, consults a small restart state file, and only
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
    private static let sessionID = UUID()
    private static var watcher: Process?

    private static let supportDir: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("BatteryBar")
    }()

    private static let restartStateURL = supportDir.appendingPathComponent(".restart_state")

    @discardableResult
    static func handleHelperInvocationIfNeeded(arguments: [String] = CommandLine.arguments) -> Bool {
        guard arguments.dropFirst().contains(helperArgument) else { return false }
        // Older watchers used no session argument. Reject malformed helper input.
        guard arguments.count == 2 || (arguments.count == 3 && UUID(uuidString: arguments[2]) != nil),
              arguments[1] == helperArgument else { Foundation.exit(1) }
        let session = arguments.count == 3 ? UUID(uuidString: arguments[2]) : nil
        _ = recoverIfNeeded(sessionID: session)
        Foundation.exit(0)
    }

    /// Call once at app launch to start the background watcher.
    static func install() {
        guard watcher == nil else { return }
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true, attributes: nil)

        guard let executablePath = Bundle.main.executablePath else { return }

        let helperExecutable = shellQuote(executablePath)
        let pid = ProcessInfo.processInfo.processIdentifier

        let script = """
        while kill -0 \(pid) 2>/dev/null; do
            sleep 2
        done
        exec \(helperExecutable) \(helperArgument) \(sessionID.uuidString)
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        do {
            try process.run()
            watcher = process
        } catch {
            // Battery monitoring remains available if the watcher cannot start.
        }
    }

    /// Call before any intentional termination so the watcher doesn't relaunch.
    static func markCleanExit() {
        try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true, attributes: nil)
        let marker = cleanExitURL(in: supportDir, sessionID: sessionID)
        do {
            try Data().write(to: marker, options: .atomic)
        } catch {
            // If storage is unavailable, stop our own watcher before exiting.
            if watcher?.isRunning == true { watcher?.terminate() }
        }
        resetRestartState()
    }

    @discardableResult
    static func recoverIfNeeded(
        supportDirectory: URL = supportDir,
        sessionID: UUID? = nil,
        bundlePath: String = Bundle.main.bundlePath,
        now: TimeInterval = Date().timeIntervalSince1970,
        beforeRelaunch: () -> Void = { Thread.sleep(forTimeInterval: 1) },
        relaunch: (String) -> Void = relaunchApp
    ) -> RecoveryOutcome {
        let cleanExitURL = cleanExitURL(in: supportDirectory, sessionID: sessionID)
        let restartStateURL = restartStateURL(in: supportDirectory)

        if FileManager.default.fileExists(atPath: cleanExitURL.path) {
            try? FileManager.default.removeItem(at: cleanExitURL)
            return .cleanExit
        }

        guard now.isFinite else { return .suppressed }
        // Serialize helpers from separate launches. If state cannot be locked or
        // written, stop recovery rather than risk an unlimited restart loop.
        do {
            try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        } catch { return .suppressed }
        let lockURL = supportDirectory.appendingPathComponent(".restart_lock")
        let lock = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard lock >= 0 else { return .suppressed }
        defer { Darwin.close(lock) }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else { return .suppressed }
        defer { flock(lock, LOCK_UN) }

        let state = normalizedState(loadRestartState(from: restartStateURL), now: now)
        guard shouldRelaunch(state, now: now) else {
            saveRestartState(state, to: restartStateURL)
            return .suppressed
        }

        let updatedState = stateByRecordingRelaunch(state, now: now)
        guard saveRestartState(updatedState, to: restartStateURL) else { return .suppressed }

        beforeRelaunch()
        relaunch(bundlePath)
        return .relaunched
    }

    static func normalizedState(_ state: RestartPolicyState, now: TimeInterval) -> RestartPolicyState {
        let cutoff = now - restartWindow
        return RestartPolicyState(attempts: state.attempts.filter { $0.isFinite && $0 >= cutoff && $0 <= now }.sorted())
    }

    static func shouldRelaunch(_ state: RestartPolicyState, now: TimeInterval) -> Bool {
        now.isFinite && normalizedState(state, now: now).attempts.count < maxRestartAttempts
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

    @discardableResult
    static func saveRestartState(_ state: RestartPolicyState) -> Bool {
        saveRestartState(state, to: restartStateURL)
    }

    @discardableResult
    static func saveRestartState(_ state: RestartPolicyState, to url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            try serializeRestartState(state).write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch { return false }
    }

    static func resetRestartState() {
        try? FileManager.default.removeItem(at: restartStateURL)
    }

    static func parseRestartState(_ contents: String) -> RestartPolicyState {
        let attempts = contents
            .split(whereSeparator: \.isNewline)
            .compactMap { TimeInterval(String($0)) }
            .filter(\.isFinite)
        return RestartPolicyState(attempts: attempts)
    }

    static func serializeRestartState(_ state: RestartPolicyState) -> String {
        let trimmed = state.attempts.filter(\.isFinite).sorted().map { String($0.rounded(.down)) }
        guard !trimmed.isEmpty else { return "" }
        return trimmed.joined(separator: "\n") + "\n"
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private static func cleanExitURL(in supportDirectory: URL, sessionID: UUID?) -> URL {
        let suffix = sessionID.map { ".\($0.uuidString)" } ?? ""
        return supportDirectory.appendingPathComponent(".clean_exit\(suffix)")
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
