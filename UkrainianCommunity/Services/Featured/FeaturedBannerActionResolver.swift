import Foundation

enum FeaturedBannerActionIntent: Equatable {
    case noAction
    case openURL(URL)
    case openGuide(id: String)
    case openNews(id: String)
    case openEvent(id: String)
    case openOrganization(id: String)
}

struct FeaturedBannerURLNormalizer {
    static func normalizedExternalURL(from value: String?) -> URL? {
        let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedValue.isEmpty, !trimmedValue.contains(where: { $0.isWhitespace }) else { return nil }

        if let url = URL(string: trimmedValue), isSupportedExternalURL(url) {
            return url
        }

        guard !trimmedValue.contains("://"), let url = URL(string: "https://\(trimmedValue)") else {
            return nil
        }
        return isSupportedExternalURL(url) ? url : nil
    }

    private static func isSupportedExternalURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            return false
        }
        return url.host?.isEmpty == false
    }
}

struct FeaturedBannerActionResolver {
    func resolve(
        _ banner: FeaturedBanner,
        opensPartnerURL: Bool = true
    ) -> FeaturedBannerActionIntent {
        switch banner.actionType {
        case .none, .announcement, .emergency:
            return .noAction
        case .externalURL:
            return externalURLIntent(from: banner.externalURL)
        case .partner:
            guard opensPartnerURL else { return .noAction }
            return externalURLIntent(from: banner.externalURL)
        case .guide:
            return targetIntent(banner.actionTargetID, makeIntent: FeaturedBannerActionIntent.openGuide)
        case .news:
            return targetIntent(banner.actionTargetID, makeIntent: FeaturedBannerActionIntent.openNews)
        case .event:
            return targetIntent(banner.actionTargetID, makeIntent: FeaturedBannerActionIntent.openEvent)
        case .organization:
            return targetIntent(banner.actionTargetID, makeIntent: FeaturedBannerActionIntent.openOrganization)
        }
    }

    private func externalURLIntent(from value: String?) -> FeaturedBannerActionIntent {
        guard let url = FeaturedBannerURLNormalizer.normalizedExternalURL(from: value) else {
            return .noAction
        }
        return .openURL(url)
    }

    private func targetIntent(
        _ value: String?,
        makeIntent: (String) -> FeaturedBannerActionIntent
    ) -> FeaturedBannerActionIntent {
        let trimmedID = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedID.isEmpty else { return .noAction }
        return makeIntent(trimmedID)
    }
}
