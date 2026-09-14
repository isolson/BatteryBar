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

        let current = UpdateChecker(session: session, defaults: defaults, currentVersion: "1.1.0")
        await current.checkForUpdates()
        assert(!current.updateAvailable)
        print("Update checks passed for versions 1.0 and 1.1.0.")
    }
}

private final class ReleaseResponse: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        assert(request.url?.absoluteString == "https://api.github.com/repos/isolson/BatteryBar/releases/latest")
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        let body = Data("""
        {"tag_name":"v1.1.0","html_url":"https://github.com/isolson/BatteryBar/releases/tag/v1.1.0"}
        """.utf8)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
