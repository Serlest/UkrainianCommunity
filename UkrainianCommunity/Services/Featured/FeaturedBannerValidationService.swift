import Foundation

struct FeaturedBannerValidationService {
    static let displayDurationBounds = 3...12
    static let priorityBounds = 0...1000
    static let internalNameMaxLength = 120
    static let titleMaxLength = 120
    static let subtitleMaxLength = 240
    static let URLMaxLength = 2_048

    func validate(_ banner: FeaturedBanner, allowsUnsupportedLegacy: Bool = false) throws {
        if diagnosticIssue(banner, allowsUnsupportedLegacy: allowsUnsupportedLegacy) != nil {
            throw AppError.validationFailed
        }
    }

    func diagnosticIssue(_ banner: FeaturedBanner, allowsUnsupportedLegacy: Bool = false) -> FeaturedBannerDataIssue? {
        func issue(_ field: String, _ rule: String) -> FeaturedBannerDataIssue { .init(field: field, rule: rule) }
        if trimmed(banner.id).isEmpty { return issue("id", "required") }
        if trimmed(banner.createdBy).isEmpty { return issue("createdBy", "required") }
        if !allowsUnsupportedLegacy && !banner.actionType.isSupported { return issue("actionType", "unsupported") }
        if !allowsUnsupportedLegacy && !banner.visibleSections.allSatisfy(\.isSupported) { return issue("visibleSections", "unsupported") }
        for (field, value, limit) in [
            ("internalName", banner.internalName, Self.internalNameMaxLength),
            ("title", Optional(banner.title), Self.titleMaxLength),
            ("subtitle", banner.subtitle, Self.subtitleMaxLength),
            ("imageURL", banner.imageURL, Self.URLMaxLength),
            ("externalURL", banner.externalURL, Self.URLMaxLength)
        ] {
            if trimmed(value).utf16.count > limit { return issue(field, "lengthExceeded") }
        }
        if !banner.localizations.keys.allSatisfy({ PublishedContentLanguage(rawValue: $0) != nil }) {
            return issue("localizations", "unsupportedLanguage")
        }
        if !banner.localizations.values.allSatisfy({ trimmed($0.title).utf16.count <= Self.titleMaxLength && trimmed($0.subtitle).utf16.count <= Self.subtitleMaxLength }) {
            return issue("localizations", "lengthExceeded")
        }
        if requiresActionTarget(banner.actionType) && trimmed(banner.actionTargetID).isEmpty { return issue("actionTargetID", "required") }
        if requiresExternalURL(banner.actionType) && !isValidHTTPURL(trimmed(banner.externalURL)) { return issue("externalURL", "invalidHTTPURL") }
        if !isValidHTTPURL(trimmed(banner.imageURL)) { return issue("imageURL", "invalidHTTPURL") }
        if banner.regionScope == .federalState && banner.federalState == nil { return issue("federalState", "required") }
        if banner.visibleSections.isEmpty { return issue("visibleSections", "empty") }
        if !Self.displayDurationBounds.contains(banner.displayDurationSeconds) { return issue("displayDurationSeconds", "outOfRange") }
        if !Self.priorityBounds.contains(banner.priority) { return issue("priority", "outOfRange") }
        if let startsAt = banner.startsAt, let endsAt = banner.endsAt, startsAt >= endsAt { return issue("startsAt/endsAt", "invalidDateOrder") }
        return nil
    }

    private func requiresActionTarget(_ actionType: FeaturedBannerActionType) -> Bool {
        switch actionType {
        case .news, .event, .organization:
            return true
        case .none, .externalURL, .unsupportedLegacy:
            return false
        }
    }

    private func requiresExternalURL(_ actionType: FeaturedBannerActionType) -> Bool {
        switch actionType {
        case .externalURL:
            return true
        case .none, .news, .event, .organization, .unsupportedLegacy:
            return false
        }
    }

    private func trimmed(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func isValidHTTPURL(_ value: String) -> Bool {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false else {
            return false
        }
        return true
    }
}

/// Only schema field names and stable rules enter diagnostics, never field values.
nonisolated struct FeaturedBannerDataIssue: Error, Equatable, Sendable {
    let field: String
    let rule: String
}
