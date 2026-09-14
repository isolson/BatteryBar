@main
struct TestRunner {
    @MainActor
    static func main() async throws {
        CrashGuardTests.runAll()
        TextLengthTests.runAll()
        try await BatteryServiceTests.runAll()
        try HistoryStoreTests.runAll()
        try await UpdateCheckerTests.runAll()
        await EnergyHogsTests.runAll()
        print("All BatteryBar tests passed.")
    }
}
