import Foundation

protocol AnalyticsConsentProviding {
    var isAnalyticsEnabled: Bool { get }
    func setAnalyticsEnabled(_ isEnabled: Bool)
}

final class AnalyticsConsentService: AnalyticsConsentProviding {
    private let userDefaults: UserDefaults
    private let storageKey: String

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "analyticsCollectionEnabled"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
    }

    var isAnalyticsEnabled: Bool {
        guard let storedValue = userDefaults.object(forKey: storageKey) as? Bool else {
            return true
        }

        return storedValue
    }

    func setAnalyticsEnabled(_ isEnabled: Bool) {
        userDefaults.set(isEnabled, forKey: storageKey)
    }
}
