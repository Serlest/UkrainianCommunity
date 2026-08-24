import CryptoKit
import Foundation

protocol AnalyticsConsentProviding {
    func isAnalyticsEnabled(for principalID: String?) -> Bool
    func analyticsConsentID(for principalID: String?) -> String?
    func setAnalyticsEnabled(_ isEnabled: Bool, for principalID: String?)
}

final class AnalyticsConsentService: AnalyticsConsentProviding {
    private let userDefaults: UserDefaults
    private let storageKey: String

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = "analyticsCollectionConsentByPrincipal.v1",
        legacyStorageKey: String = "analyticsCollectionEnabled"
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey

        // The legacy value was global and therefore cannot safely be assigned
        // to whichever account happens to sign in after an upgrade. Dropping it
        // deliberately requires one fresh opt-in per principal.
        userDefaults.removeObject(forKey: legacyStorageKey)
    }

    func isAnalyticsEnabled(for principalID: String?) -> Bool {
        analyticsConsentID(for: principalID) != nil
    }

    func analyticsConsentID(for principalID: String?) -> String? {
        guard let identifier = storageIdentifier(for: principalID) else { return nil }
        return userDefaults.dictionary(forKey: storageKey)?[identifier] as? String
    }

    func setAnalyticsEnabled(_ isEnabled: Bool, for principalID: String?) {
        guard let identifier = storageIdentifier(for: principalID) else { return }

        var storedValues = userDefaults.dictionary(forKey: storageKey) ?? [:]
        if isEnabled {
            if storedValues[identifier] as? String == nil {
                storedValues[identifier] = UUID().uuidString
            }
        } else {
            storedValues.removeValue(forKey: identifier)
        }

        if storedValues.isEmpty {
            userDefaults.removeObject(forKey: storageKey)
        } else {
            userDefaults.set(storedValues, forKey: storageKey)
        }
    }

    private func storageIdentifier(for principalID: String?) -> String? {
        guard let principalID else { return nil }
        let normalizedPrincipalID = principalID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPrincipalID.isEmpty else { return nil }
        let consentScope = "firebase-principal:\(normalizedPrincipalID)"

        let digest = SHA256.hash(data: Data(consentScope.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
