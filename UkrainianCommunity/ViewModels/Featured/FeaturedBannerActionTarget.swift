import Foundation

enum FeaturedBannerActionTargetKind: String, CaseIterable, Identifiable, Hashable {
    case news
    case event
    case organization

    var id: String { rawValue }

    init?(actionType: FeaturedBannerActionType) {
        switch actionType {
        case .news:
            self = .news
        case .event:
            self = .event
        case .organization:
            self = .organization
        case .none, .unsupportedLegacy, .externalURL:
            return nil
        }
    }

    var title: String {
        switch self {
        case .news:
            return AppStrings.News.title
        case .event:
            return AppStrings.Tabs.events
        case .organization:
            return AppStrings.Tabs.organizations
        }
    }

    var systemImage: String {
        switch self {
        case .news:
            return "newspaper"
        case .event:
            return "calendar"
        case .organization:
            return "building.2"
        }
    }
}

struct FeaturedBannerActionTargetItem: Identifiable, Hashable {
    let id: String
    let kind: FeaturedBannerActionTargetKind
    let title: String
    let subtitle: String?
    let metadata: String?
    let searchText: String

    init(news: NewsPost) {
        id = news.id
        kind = .news
        title = news.localizedTitle
        subtitle = Self.nonEmpty(news.localizedSubtitle)
        metadata = Self.joined([
            news.source.displayOrganizationName ?? news.authorName,
            Self.dateText(news.publishedAt)
        ])
        searchText = Self.searchText([
            news.title,
            news.subtitle,
            news.source.displayOrganizationName,
            news.sourceName,
            news.authorName,
            news.id
        ])
    }

    init(event: Event) {
        id = event.id
        kind = .event
        title = event.localizedTitle
        subtitle = Self.nonEmpty(event.localizedSummary)
        metadata = Self.joined([
            Self.nonEmpty(event.organizerName) ?? event.source.displayOrganizationName,
            Self.joined([Self.nonEmpty(event.city), Self.nonEmpty(event.venue)]),
            Self.dateText(event.startDate)
        ])
        searchText = Self.searchText([
            event.title,
            event.summary,
            Self.dateText(event.startDate),
            Self.dateText(event.endDate),
            event.city,
            event.venue,
            event.address,
            event.locationNote,
            event.organizerName,
            event.source.displayOrganizationName,
            event.authorName,
            event.id
        ])
    }

    init(organization: Organization) {
        id = organization.id
        kind = .organization
        title = organization.localizedName
        subtitle = Self.nonEmpty(organization.localizedShortDescription)
        metadata = Self.joined([
            Self.nonEmpty(organization.organizationType),
            Self.nonEmpty(organization.city)
        ])
        searchText = Self.searchText([
            organization.localizedName,
            organization.localizedShortDescription,
            organization.city,
            organization.organizationType,
            organization.id
        ])
    }

    private static func joined(_ values: [String?]) -> String? {
        let joined = values.compactMap { nonEmpty($0) }.joined(separator: " · ")
        return joined.isEmpty ? nil : joined
    }

    private static func dateText(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    private static func searchText(_ values: [String?]) -> String {
        values
            .compactMap { nonEmpty($0) }
            .joined(separator: " ")
            .lowercased()
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
