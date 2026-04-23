@main
struct TestRunner {
    static func main() {
        CrashGuardTests.runAll()
        TextLengthTests.runAll()
    }
}
