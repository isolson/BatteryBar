import Foundation

@MainActor
class UpdateChecker: ObservableObject {
    @Published var updateAvailable = false
    @Published var latestVersion: String? = nil
    @Published var downloadURL: URL? = nil

    private let repo = "isolson/BatteryBar"
    private let checkInterval: TimeInterval = 6 * 3600
    private let session: URLSession
    private let defaults: UserDefaults
    private let currentVersion: String
    private let cacheKey = "validatedRelease"
    private var cachedRelease: CachedRelease?
    private var isChecking = false

    private struct CachedRelease: Codable {
        let version: String
        let url: URL
        let checkedAt: TimeInterval
    }

    init(session: URLSession = .shared, defaults: UserDefaults = .standard, currentVersion: String? = nil) {
        self.session = session
        self.defaults = defaults
        self.currentVersion = currentVersion
            ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        if let data = defaults.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(CachedRelease.self, from: data),
           versionComponents(cached.version) != nil, isReleaseURL(cached.url, version: cached.version),
           cached.checkedAt.isFinite {
            cachedRelease = cached
            apply(cached)
        }
    }

    func checkIfNeeded() async {
        if let cached = cachedRelease {
            let age = Date().timeIntervalSince1970 - cached.checkedAt
            if age >= 0 && age < checkInterval { return }
        }
        await checkForUpdates()
    }

    func checkForUpdates() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let htmlURL = json["html_url"] as? String else { return }

            let remote = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            guard versionComponents(remote) != nil,
                  let download = URL(string: htmlURL), isReleaseURL(download, version: remote) else { return }
            let cached = CachedRelease(version: remote, url: download, checkedAt: Date().timeIntervalSince1970)
            cachedRelease = cached
            if let data = try? JSONEncoder().encode(cached) { defaults.set(data, forKey: cacheKey) }
            apply(cached)
        } catch {
            // Silently fail — update check is best-effort
        }
    }

    private func apply(_ release: CachedRelease) {
        updateAvailable = isNewer(remote: release.version, local: currentVersion)
        latestVersion = updateAvailable ? release.version : nil
        downloadURL = updateAvailable ? release.url : nil
    }

    private func isReleaseURL(_ url: URL, version: String) -> Bool {
        let prefix = "https://github.com/\(repo)/releases/tag/"
        return url.absoluteString == prefix + "v" + version || url.absoluteString == prefix + version
    }

    private func versionComponents(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count) else { return nil }
        let values = parts.compactMap { part -> Int? in
            guard !part.isEmpty, part.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return nil }
            return Int(part)
        }
        return values.count == parts.count ? values : nil
    }

    private func isNewer(remote: String, local: String) -> Bool {
        guard let r = versionComponents(remote), let l = versionComponents(local) else { return false }
        let count = max(r.count, l.count)
        for i in 0..<count {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }
}
