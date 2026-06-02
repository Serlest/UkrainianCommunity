import Foundation

enum FeaturedBannerActionType: String, CaseIterable, Codable, Identifiable {
    case none
    case news
    case event
    case organization
    case guide
    case externalURL

    var id: String { rawValue }

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
    case guide

    var id: String { rawValue }
}

struct FeaturedBanner: Identifiable, Equatable, Codable {
    static let collectionPath = "featuredBanners"

    let id: String
    let internalName: String?
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

    init(
        id: String,
        internalName: String? = nil,
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
        updatedBy: String? = nil
    ) {
        self.id = id
        self.internalName = internalName
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
    }
}
