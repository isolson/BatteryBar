import Foundation

@MainActor
enum UpdateCheckerTests {
    static func runAll() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReleaseResponse.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let suite = "BatteryBar.UpdateTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let previous = UpdateChecker(session: session, defaults: defaults, currentVersion: "1.0")
        await previous.checkForUpdates()
        assert(previous.updateAvailable)
        assert(previous.latestVersion == "1.1.0")
        assert(previous.downloadURL?.absoluteString == "https://github.com/isolson/BatteryBar/releases/tag/v1.1.0")

        let relaunched = UpdateChecker(session: session, defaults: defaults, currentVersion: "1.0")
        assert(relaunched.updateAvailable, "Cached update must be visible before a new request")
        await relaunched.checkIfNeeded()
        assert(relaunched.updateAvailable && relaunched.latestVersion == "1.1.0")

        let current = UpdateChecker(session: session, defaults: defaults, currentVersion: "1.1.0")
        await current.checkForUpdates()
        assert(!current.updateAvailable)
        assert(current.latestVersion == nil && current.downloadURL == nil)

        for body in [
            "{\"tag_name\":\"v9.invalid.0\",\"html_url\":\"https://github.com/isolson/BatteryBar/releases/tag/v9.invalid.0\"}",
            "{\"tag_name\":\"v9.0.0\",\"html_url\":\"file:///tmp/untrusted\"}",
            "{\"tag_name\":\"v9.0.0\",\"html_url\":\"https://example.com/releases/tag/v9.0.0\"}"
        ] {
            ReleaseResponse.body = body
            await previous.checkForUpdates()
            assert(previous.latestVersion == "1.1.0", "Invalid response must preserve the last valid result")
        }
        ReleaseResponse.body = nil
        ReleaseResponse.status = 503
        await previous.checkForUpdates()
        assert(previous.updateAvailable)
        ReleaseResponse.status = 200

        // An old install's timestamp alone must not hide updates after relaunch.
        defaults.removeObject(forKey: "validatedRelease")
        defaults.set(Date().timeIntervalSince1970, forKey: "lastUpdateCheck")
        let migrated = UpdateChecker(session: session, defaults: defaults, currentVersion: "1.0")
        await migrated.checkIfNeeded()
        assert(migrated.updateAvailable)
        print("Update checks passed for versions 1.0 and 1.1.0.")
    }
}

private final class ReleaseResponse: URLProtocol {
    static var body: String?
    static var status = 200
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        assert(request.url?.absoluteString == "https://api.github.com/repos/isolson/BatteryBar/releases/latest")
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        let body = Data((Self.body ?? """
        {"tag_name":"v1.1.0","html_url":"https://github.com/isolson/BatteryBar/releases/tag/v1.1.0"}
        """).utf8)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
