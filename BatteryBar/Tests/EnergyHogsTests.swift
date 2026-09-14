import Foundation

@MainActor
enum EnergyHogsTests {
    static func runAll() async {
        testProcessParsing()
        await testSuccessfulQuery()
        await testTimeoutAndCancellation()
        await testRefreshDoesNotOverlap()
        print("Energy query timeout, cancellation, parsing, and refresh tests passed.")
    }

    private static func testProcessParsing() {
        let samples = EnergyHogMonitor.parse("""
          PID %CPU COMM
          123 12.5 /Applications/Example  App.app/Contents/MacOS/Example  App
          124 nan /bad
          125 inf /bad
          -1 20 /bad
          126 -4 /bad
          invalid line
          127 0 /idle
        """)
        assert(samples == [
            EnergyProcessSample(pid: 123, cpu: 12.5, comm: "/Applications/Example  App.app/Contents/MacOS/Example  App"),
            EnergyProcessSample(pid: 127, cpu: 0, comm: "/idle")
        ])
    }

    private static func testSuccessfulQuery() async {
        let output = await EnergyProcessQuery.output(executable: "/usr/bin/printf", arguments: ["sample"])
        assert(output == Data("sample".utf8))
        let environment = await EnergyProcessQuery.output(executable: "/usr/bin/env", arguments: [])
        let environmentLines = String(data: environment!, encoding: .utf8)!.split(separator: "\n")
        assert(environmentLines.contains("LC_ALL=C"), "CPU parsing must not depend on the user's locale")
        let failure = await EnergyProcessQuery.output(executable: "/usr/bin/false", arguments: [])
        assert(failure == nil)
        let missing = await EnergyProcessQuery.output(executable: "/does/not/exist", arguments: [])
        assert(missing == nil)
        let oversized = await EnergyProcessQuery.output(executable: "/usr/bin/head",
                                                        arguments: ["-c", "5000000", "/dev/zero"])
        assert(oversized == nil, "Unexpected process output must have a fixed size limit")
    }

    private static func testTimeoutAndCancellation() async {
        let started = Date()
        // This child has no descendants and deliberately ignores graceful termination.
        let output = await EnergyProcessQuery.output(executable: "/bin/sh", arguments: [
            "-c", "trap '' TERM; while :; do :; done"
        ], timeout: 0.1)
        assert(output == nil)
        assert(Date().timeIntervalSince(started) < 3, "An unresponsive child must have a bounded lifetime")

        let queryStarted = Date()
        let cancelled = Task {
            await EnergyProcessQuery.output(executable: "/bin/sleep", arguments: ["10"], timeout: 10)
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        assert(Date().timeIntervalSince(queryStarted) < 3,
               "The main actor must remain available while the process is running")
        let cancellationStarted = Date()
        cancelled.cancel()
        let cancelledOutput = await cancelled.value
        assert(cancelledOutput == nil)
        assert(Date().timeIntervalSince(cancellationStarted) < 3)

        let alreadyCancelled = Task {
            await EnergyProcessQuery.output(executable: "/bin/sleep", arguments: ["10"], timeout: 10)
        }
        alreadyCancelled.cancel()
        let preCancelledOutput = await alreadyCancelled.value
        assert(preCancelledOutput == nil)
    }

    private static func testRefreshDoesNotOverlap() async {
        let fixture = PendingQuery()
        let monitor = EnergyHogMonitor(query: { await fixture.run() })
        let first = Task { await monitor.refresh() }
        while await fixture.count == 0 { await Task.yield() }
        await monitor.refresh()
        let countDuringRefresh = await fixture.count
        assert(countDuringRefresh == 1, "Opening the panel again must not overlap a pending query")
        await fixture.finish()
        await first.value
        await monitor.refresh()
        let countAfterRefresh = await fixture.count
        assert(countAfterRefresh == 1, "A fresh result should be reused")
    }
}

private actor PendingQuery {
    private(set) var count = 0
    private var continuation: CheckedContinuation<[EnergyProcessSample]?, Never>?

    func run() async -> [EnergyProcessSample]? {
        count += 1
        return await withCheckedContinuation { continuation = $0 }
    }

    func finish() {
        continuation?.resume(returning: [])
        continuation = nil
    }
}
