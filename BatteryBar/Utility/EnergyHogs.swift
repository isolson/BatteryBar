import AppKit

struct EnergyHog: Identifiable {
    let id: pid_t
    let name: String
    let icon: NSImage?
}

private var cachedHogs: [EnergyHog] = []
private var cacheTimestamp: Date = .distantPast

func topEnergyApps(limit: Int = 3, threshold: Double = 5.0) -> [EnergyHog] {
    // Return cached result if fresh (< 10s old)
    if Date().timeIntervalSince(cacheTimestamp) < 10 { return cachedHogs }

    // Get top CPU processes via ps
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/ps")
    task.arguments = ["-eo", "pid,pcpu,comm", "-r"]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = FileHandle.nullDevice

    do {
        try task.run()
    } catch {
        return []
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()

    guard let output = String(data: data, encoding: .utf8) else { return [] }

    // Parse ps output: "  PID  %CPU COMM"
    let lines = output.components(separatedBy: "\n").dropFirst() // skip header

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

    // Parse and aggregate by app bundle
    struct RawProcess {
        let pid: pid_t
        let cpu: Double
        let comm: String
    }

    var rawProcs: [RawProcess] = []
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { continue }
        let parts = trimmed.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 3,
              let pid = Int32(parts[0]),
              let cpu = Double(parts[1]),
              cpu >= threshold else { continue }

        let comm = String(parts[2])
        // Extract process name from path
        let procName = (comm as NSString).lastPathComponent
        guard !excludedNames.contains(procName) else { continue }

        rawProcs.append(RawProcess(pid: pid, cpu: cpu, comm: comm))
    }

    // Group by app: find the NSRunningApplication for each PID, group by bundle
    var appGroups: [String: (name: String, icon: NSImage?, totalCPU: Double, pid: pid_t)] = [:]

    for proc in rawProcs {
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
        .prefix(limit)

    let result = sorted.map { EnergyHog(id: $0.pid, name: $0.name, icon: $0.icon) }
    cachedHogs = result
    cacheTimestamp = Date()
    return result
}
