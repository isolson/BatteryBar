import AppKit

struct EnergyHog: Identifiable {
    let id: pid_t
    let name: String
    let icon: NSImage?
}

struct EnergyProcessSample: Sendable, Equatable {
    let pid: pid_t
    let cpu: Double
    let comm: String
}

/// Owns only this query's child process. Cancellation never targets another app.
final class EnergyProcessQuery: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    static func output(executable: String = "/bin/ps",
                       arguments: [String] = ["-eo", "pid,pcpu,comm", "-r"],
                       timeout: TimeInterval = 2) async -> Data? {
        let query = EnergyProcessQuery()
        return await withTaskCancellationHandler {
            if Task.isCancelled { query.cancel() }
            return await Task.detached(priority: .utility) {
                query.run(executable: executable, arguments: arguments, timeout: timeout)
            }.value
        } onCancel: {
            query.cancel()
        }
    }

    private func run(executable: String, arguments: [String], timeout: TimeInterval) -> Data? {
        guard timeout.isFinite, timeout > 0 else { return nil }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        task.environment = environment
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        lock.lock()
        guard !cancelled else { lock.unlock(); return nil }
        process = task
        do { try task.run() }
        catch { process = nil; lock.unlock(); return nil }
        lock.unlock()

        let deadline = DispatchWorkItem { [weak self] in self?.cancel() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: deadline)
        defer {
            deadline.cancel()
            try? pipe.fileHandleForReading.close()
            lock.lock()
            process = nil
            lock.unlock()
        }

        var output = Data()
        do {
            while let chunk = try pipe.fileHandleForReading.read(upToCount: 64 * 1024), !chunk.isEmpty {
                // A normal process list is small; cap unexpected output as well as runtime.
                guard output.count + chunk.count <= 4 * 1024 * 1024 else { cancel(); break }
                output.append(chunk)
            }
        } catch { cancel() }
        task.waitUntilExit()
        lock.lock()
        let succeeded = !cancelled && task.terminationStatus == 0
        lock.unlock()
        return succeeded ? output : nil
    }

    private func cancel() {
        lock.lock()
        cancelled = true
        if let task = process, task.isRunning {
            task.terminate()
            // A child can ignore SIGTERM. Bound that case too.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.2) { [self] in
                lock.lock()
                if let task = process, task.isRunning {
                    kill(task.processIdentifier, SIGKILL)
                }
                lock.unlock()
            }
        }
        lock.unlock()
    }
}

@MainActor
final class EnergyHogMonitor: ObservableObject {
    @Published private(set) var hogs: [EnergyHog] = []
    private let query: @Sendable () async -> [EnergyProcessSample]?
    private var isRefreshing = false
    private var lastRefresh = Date.distantPast

    init(query: @escaping @Sendable () async -> [EnergyProcessSample]? = { await EnergyHogMonitor.readProcesses() }) {
        self.query = query
    }

    /// SwiftUI cancels this task when the panel or expanded details disappear.
    func poll() async {
        while !Task.isCancelled {
            await refresh()
            do { try await Task.sleep(nanoseconds: 10_000_000_000) }
            catch { return }
        }
    }

    func refresh() async {
        guard !Task.isCancelled, !isRefreshing,
              Date().timeIntervalSince(lastRefresh) >= 10 else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let processes = await query()
        guard !Task.isCancelled else { return }
        hogs = processes.map(Self.identifyApps) ?? []
        lastRefresh = Date()
    }

    nonisolated static func readProcesses() async -> [EnergyProcessSample]? {
        guard let data = await EnergyProcessQuery.output(),
              let output = String(data: data, encoding: .utf8) else { return nil }
        return parse(output)
    }

    nonisolated static func parse(_ output: String) -> [EnergyProcessSample] {
        output.split(separator: "\n").dropFirst().compactMap { line in
            let parts = line.split(maxSplits: 2, omittingEmptySubsequences: true,
                                   whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 3, let pid = Int32(parts[0]), pid > 0,
                  let cpu = Double(parts[1]), cpu.isFinite, cpu >= 0 else { return nil }
            return EnergyProcessSample(pid: pid, cpu: cpu, comm: parts[2].trimmingCharacters(in: .whitespaces))
        }
    }

    private static func identifyApps(_ processes: [EnergyProcessSample]) -> [EnergyHog] {
        // Build map of running apps by PID for name/icon lookup
        let runningApps = NSWorkspace.shared.runningApplications
        var appByPID: [pid_t: NSRunningApplication] = [:]
        for app in runningApps {
            appByPID[app.processIdentifier] = app
        }

        // System processes to exclude
        let excludedNames: Set<String> = [
            "WindowServer", "kernel_task", "loginwindow", "launchd",
            "BatteryBar", "syslogd", "opendirectoryd", "mds", "mds_stores",
            "hidd", "coreaudiod", "bluetoothd", "diskarbitrationd"
        ]

        // Group by app: find the NSRunningApplication for each PID, group by bundle
        var appGroups: [String: (name: String, icon: NSImage?, totalCPU: Double, pid: pid_t)] = [:]

        for proc in processes where proc.cpu >= 5 {
            guard !excludedNames.contains((proc.comm as NSString).lastPathComponent) else { continue }
            if let app = appByPID[proc.pid], let bundleID = app.bundleIdentifier {
                let name = app.localizedName ?? (proc.comm as NSString).lastPathComponent
                if var existing = appGroups[bundleID] {
                    existing.totalCPU += proc.cpu
                    appGroups[bundleID] = existing
                } else {
                    appGroups[bundleID] = (name: name, icon: app.icon, totalCPU: proc.cpu, pid: proc.pid)
                }
            } else {
                // Try to find parent app by checking if any running app's PID group includes this
                // Fall back to looking up by executable path
                let procName = (proc.comm as NSString).lastPathComponent
                    .replacingOccurrences(of: " Helper", with: "")
                    .replacingOccurrences(of: " (Renderer)", with: "")
                    .replacingOccurrences(of: " (GPU)", with: "")

                // Try matching by name
                if let app = runningApps.first(where: {
                    $0.localizedName == procName || $0.bundleIdentifier?.contains(procName.lowercased()) == true
                }), let bundleID = app.bundleIdentifier {
                    let name = app.localizedName ?? procName
                    if var existing = appGroups[bundleID] {
                        existing.totalCPU += proc.cpu
                        appGroups[bundleID] = existing
                    } else {
                        appGroups[bundleID] = (name: name, icon: app.icon, totalCPU: proc.cpu, pid: proc.pid)
                    }
                }
                // Skip processes we can't match to a user-facing app
            }
        }

        // Sort by total CPU, take top N
        let sorted = appGroups.values
            .sorted { $0.totalCPU > $1.totalCPU }
            .prefix(3)

        let result = sorted.map { EnergyHog(id: $0.pid, name: $0.name, icon: $0.icon) }
        return result
    }
}
