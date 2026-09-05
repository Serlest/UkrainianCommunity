import CryptoKit
import Foundation

struct AnalyticsConsentVersions: Codable, Equatable {
    let privacyVersion: String
    let disclosureVersion: String
}

protocol AnalyticsConsentProviding {
    func isAnalyticsEnabled(for principalID: String?) -> Bool
    func analyticsConsentID(for principalID: String?) -> String?
    func analyticsConsentLocale(for principalID: String?) -> String?
    func analyticsConsentVersions(for principalID: String?) -> AnalyticsConsentVersions?
    func setAnalyticsEnabled(_ isEnabled: Bool, for principalID: String?)
}

extension AnalyticsConsentProviding {
    func analyticsConsentLocale(for principalID: String?) -> String? { nil }
    func analyticsConsentVersions(for principalID: String?) -> AnalyticsConsentVersions? { nil }
}

final class AnalyticsConsentService: AnalyticsConsentProviding {
    static let disclosureVersion = "2026-08-25.1"
    private let userDefaults: UserDefaults
    private let storageKey: String
    private var localeStorageKey: String { storageKey + ".locale" }
    private var versionStorageKey: String { storageKey + ".versions" }

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
        var storedLocales = userDefaults.dictionary(forKey: localeStorageKey) ?? [:]
        var storedVersions = userDefaults.dictionary(forKey: versionStorageKey) ?? [:]
        if isEnabled {
            if storedValues[identifier] as? String == nil {
                storedValues[identifier] = UUID().uuidString
                storedLocales[identifier] = LocalizationStore.language.rawValue
                storedVersions[identifier] = ["privacyVersion": AuthService.currentPrivacyVersion, "disclosureVersion": Self.disclosureVersion]
            }
        } else {
            storedValues.removeValue(forKey: identifier)
            storedLocales.removeValue(forKey: identifier)
            storedVersions.removeValue(forKey: identifier)
        }

        userDefaults.set(storedVersions, forKey: versionStorageKey)
        if storedValues.isEmpty {
            userDefaults.removeObject(forKey: storageKey)
        } else {
            userDefaults.set(storedValues, forKey: storageKey)
        }
        if storedLocales.isEmpty {
            userDefaults.removeObject(forKey: localeStorageKey)
        } else {
            userDefaults.set(storedLocales, forKey: localeStorageKey)
        }
    }

    func analyticsConsentLocale(for principalID: String?) -> String? {
        guard analyticsConsentID(for: principalID) != nil,
              let identifier = storageIdentifier(for: principalID),
              let locale = userDefaults.dictionary(forKey: localeStorageKey)?[identifier] as? String,
              locale == "de" || locale == "uk" else { return nil }
        return locale
    }

    func analyticsConsentVersions(for principalID: String?) -> AnalyticsConsentVersions? {
        guard analyticsConsentID(for: principalID) != nil,
              let identifier = storageIdentifier(for: principalID),
              let version = userDefaults.dictionary(forKey: versionStorageKey)?[identifier] as? [String: String],
              let privacy = version["privacyVersion"], let disclosure = version["disclosureVersion"] else { return nil }
        return AnalyticsConsentVersions(privacyVersion: privacy, disclosureVersion: disclosure)
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
