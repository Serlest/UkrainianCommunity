import Foundation
import StoreKit

nonisolated protocol AppUpdateChecking: Sendable {
    func availableUpdate() async throws -> AppStoreUpdate?
}

actor AppStoreUpdateClient: AppUpdateChecking {
    private let session: URLSession
    private let installedVersion: String
    private let operatingSystem: String
    private var cached: (country: String, checkedAt: Date, update: AppStoreUpdate?)?

    init(installedVersion: String) {
        self.installedVersion = installedVersion
        let system = ProcessInfo.processInfo.operatingSystemVersion
        operatingSystem = "\(system.majorVersion).\(system.minorVersion).\(system.patchVersion)"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 10
        configuration.waitsForConnectivity = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    func availableUpdate() async throws -> AppStoreUpdate? {
        let storefront = await Storefront.current
        try Task.checkCancellation()
        guard let country = AppStoreCountry.lookupCode(
            storefront: storefront?.countryCode, deviceRegion: Locale.current.region?.identifier
        ) else { return nil }
        // Rapid close/open cycles reuse a fresh response, not a permanent snooze.
        if let cached, cached.country == country, Date().timeIntervalSince(cached.checkedAt) < 60 {
            return cached.update
        }
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [
            URLQueryItem(name: "id", value: String(AppStoreUpdate.appID)),
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "entity", value: "software")
        ]
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              data.count <= 512_000 else { return nil }
        let responseBody = try JSONDecoder().decode(AppStoreLookupResponse.self, from: data)
        let update = responseBody.availableUpdate(installedVersion: installedVersion, operatingSystem: operatingSystem)
        cached = (country, Date(), update)
        return update
    }
}

nonisolated struct FixtureAppUpdateClient: AppUpdateChecking {
    let version: String?
    func availableUpdate() async throws -> AppStoreUpdate? { version.map { AppStoreUpdate(version: $0) } }
}

@MainActor
enum AppUpdateClientFactory {
    static func make() -> any AppUpdateChecking {
        let process = ProcessInfo.processInfo
        if process.arguments.contains("-ui-testing") {
            return FixtureAppUpdateClient(version: process.environment["UITestAvailableAppVersion"])
        }
        if process.environment["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil {
            return FixtureAppUpdateClient(version: nil)
        }
        return AppStoreUpdateClient(installedVersion:
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
    }
}
