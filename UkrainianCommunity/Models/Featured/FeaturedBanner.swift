import Foundation

enum FeaturedBannerActionType: String, CaseIterable, Codable, Identifiable {
    case none
    case news
    case event
    case organization
    // Retained only to decode and retire existing Firestore banners.
    case unsupportedLegacy = "guide"
    case externalURL

    var id: String { rawValue }

    static let supportedCases: [Self] = [.none, .news, .event, .organization, .externalURL]

    var isSupported: Bool {
        self != .unsupportedLegacy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        guard let actionType = Self.normalized(from: rawValue) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported featured banner action type: \(rawValue)"
            )
        }
        self = actionType
    }

    static func normalized(from rawValue: String) -> FeaturedBannerActionType? {
        switch rawValue {
        case "announcement", "emergency":
            return FeaturedBannerActionType.none
        case "partner":
            return .externalURL
        default:
            return FeaturedBannerActionType(rawValue: rawValue)
        }
    }
}

enum FeaturedBannerRegionScope: String, CaseIterable, Codable, Identifiable {
    case allAustria
    case federalState

    var id: String { rawValue }
}

enum FeaturedBannerVisibleSection: String, CaseIterable, Codable, Identifiable, Hashable {
    case home
    case events
    case organizations
    // Retained only to decode and retire existing Firestore banners.
    case unsupportedLegacy = "guide"

    var id: String { rawValue }

    static let supportedCases: [Self] = [.home, .events, .organizations]

    var isSupported: Bool {
        self != .unsupportedLegacy
    }
}

enum FeaturedBannerLifecycleState: Equatable {
    case migrationRequired
    case inactive
    case scheduled
    case live
    case expired
}

struct FeaturedBannerLocalizedContent: Codable, Equatable {
    let title: String
    let subtitle: String
}

struct FeaturedBanner: Identifiable, Equatable {
    static let collectionPath = "featuredBanners"

    let id: String
    let internalName: String?
    let localizations: [String: FeaturedBannerLocalizedContent]
    let title: String
    let subtitle: String?
    let imageURL: String?
    let actionType: FeaturedBannerActionType
    let actionTargetID: String?
    let externalURL: String?
    let regionScope: FeaturedBannerRegionScope
    let federalState: AustrianFederalState?
    let visibleSections: Set<FeaturedBannerVisibleSection>
    let displayDurationSeconds: Int
    let priority: Int
    let isActive: Bool
    let startsAt: Date?
    let endsAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let createdBy: String
    let updatedBy: String?
    let requiresDataRepair: Bool

    var hasUnsupportedLegacyConfiguration: Bool {
        requiresDataRepair || !actionType.isSupported || visibleSections.contains { !$0.isSupported }
    }

    var supportedVisibleSections: Set<FeaturedBannerVisibleSection> {
        Set(visibleSections.filter(\.isSupported))
    }

    var localizedContent: FeaturedBannerLocalizedContent {
        localizedContent(for: LocalizationStore.language)
    }

    func localizedContent(for language: AppLanguage) -> FeaturedBannerLocalizedContent {
        localizations.resolved(for: language)
            ?? FeaturedBannerLocalizedContent(title: title, subtitle: subtitle ?? "")
    }

    var localizedTitle: String { localizedContent.title }
    var localizedSubtitle: String { localizedContent.subtitle }

    func localizedTitle(for language: AppLanguage) -> String {
        localizedContent(for: language).title
    }

    func localizedSubtitle(for language: AppLanguage) -> String {
        localizedContent(for: language).subtitle
    }

    func lifecycleState(at date: Date = Date()) -> FeaturedBannerLifecycleState {
        if hasUnsupportedLegacyConfiguration {
            return .migrationRequired
        }
        guard isActive else {
            return .inactive
        }
        if let startsAt, startsAt > date {
            return .scheduled
        }
        if let endsAt, endsAt < date {
            return .expired
        }
        return .live
    }

    func isVisible(on date: Date) -> Bool {
        let startsBeforeNow = startsAt.map { $0 <= date } ?? true
        let endsAfterNow = endsAt.map { $0 >= date } ?? true
        return startsBeforeNow && endsAfterNow
    }

    func matchesRegion(_ selectedFederalState: AustrianFederalState?) -> Bool {
        // “All Austria” is an inclusive feed: it shows national and regional
        // highlights. Choosing a state narrows regional banners to that state
        // while national banners remain visible.
        guard let selectedFederalState else { return true }

        switch regionScope {
        case .allAustria:
            return true
        case .federalState:
            guard let federalState else { return false }
            return federalState == selectedFederalState
        }
    }

    init(
        id: String,
        internalName: String? = nil,
        localizations: [String: FeaturedBannerLocalizedContent] = [:],
        title: String,
        subtitle: String? = nil,
        imageURL: String? = nil,
        actionType: FeaturedBannerActionType = .none,
        actionTargetID: String? = nil,
        externalURL: String? = nil,
        regionScope: FeaturedBannerRegionScope = .allAustria,
        federalState: AustrianFederalState? = nil,
        visibleSections: Set<FeaturedBannerVisibleSection>,
        displayDurationSeconds: Int = 6,
        priority: Int = 0,
        isActive: Bool = true,
        startsAt: Date? = nil,
        endsAt: Date? = nil,
        createdAt: Date,
        updatedAt: Date,
        createdBy: String,
        updatedBy: String? = nil,
        requiresDataRepair: Bool = false
    ) {
        self.id = id
        self.internalName = internalName
        self.localizations = localizations
        self.title = title
        self.subtitle = subtitle
        self.imageURL = imageURL
        self.actionType = actionType
        self.actionTargetID = actionTargetID
        self.externalURL = externalURL
        self.regionScope = regionScope
        self.federalState = federalState
        self.visibleSections = visibleSections
        self.displayDurationSeconds = displayDurationSeconds
        self.priority = priority
        self.isActive = isActive
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.createdBy = createdBy
        self.updatedBy = updatedBy
        self.requiresDataRepair = requiresDataRepair
    }
}
