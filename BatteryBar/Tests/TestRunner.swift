@main
struct TestRunner {
    @MainActor
    static func main() async throws {
        CrashGuardTests.runAll()
        TextLengthTests.runAll()
        try await BatteryServiceTests.runAll()
        try await UpdateCheckerTests.runAll()
        print("All BatteryBar tests passed.")
    }
}
