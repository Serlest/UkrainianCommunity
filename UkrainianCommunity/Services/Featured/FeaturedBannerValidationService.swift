import Foundation

struct FeaturedBannerValidationService {
    static let displayDurationBounds = 3...12
    static let priorityBounds = 0...1000
    static let internalNameMaxLength = 120
    static let titleMaxLength = 120
    static let subtitleMaxLength = 240
    static let URLMaxLength = 2_048

    func validate(_ banner: FeaturedBanner, allowsUnsupportedLegacy: Bool = false) throws {
        guard !trimmed(banner.id).isEmpty,
              !trimmed(banner.createdBy).isEmpty else {
            throw AppError.validationFailed
        }

        guard allowsUnsupportedLegacy
                || (banner.actionType.isSupported && banner.visibleSections.allSatisfy(\.isSupported)) else {
            throw AppError.validationFailed
        }

        guard trimmed(banner.internalName).count <= Self.internalNameMaxLength,
              trimmed(banner.title).count <= Self.titleMaxLength,
              trimmed(banner.subtitle).count <= Self.subtitleMaxLength,
              trimmed(banner.imageURL).count <= Self.URLMaxLength,
              trimmed(banner.externalURL).count <= Self.URLMaxLength else {
            throw AppError.validationFailed
        }

        if requiresActionTarget(banner.actionType) {
            guard !trimmed(banner.actionTargetID).isEmpty else {
                throw AppError.validationFailed
            }
        }

        if requiresExternalURL(banner.actionType) {
            guard isValidHTTPURL(trimmed(banner.externalURL)) else {
                throw AppError.validationFailed
            }
        }

        guard isValidHTTPURL(trimmed(banner.imageURL)) else {
            throw AppError.validationFailed
        }

        if banner.regionScope == .federalState, banner.federalState == nil {
            throw AppError.validationFailed
        }

        guard !banner.visibleSections.isEmpty else {
            throw AppError.validationFailed
        }

        guard Self.displayDurationBounds.contains(banner.displayDurationSeconds) else {
            throw AppError.validationFailed
        }

        guard Self.priorityBounds.contains(banner.priority) else {
            throw AppError.validationFailed
        }

        if let startsAt = banner.startsAt, let endsAt = banner.endsAt, startsAt >= endsAt {
            throw AppError.validationFailed
        }
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
