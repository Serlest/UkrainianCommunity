import Foundation

enum LikeState: String, Codable {
    case liked
    case notLiked

    var isLiked: Bool { self == .liked }

    func toggled() -> LikeState {
        isLiked ? .notLiked : .liked
    }
}

enum AustrianFederalState: String, CaseIterable, Codable, Identifiable {
    case burgenland
    case kaernten
    case niederoesterreich
    case oberoesterreich
    case salzburg
    case steiermark
    case tirol
    case vorarlberg
    case wien

    var id: String { rawValue }
}

enum RegionScope: String, CaseIterable, Codable, Identifiable {
    case austria
    case federalState
    case city

    var id: String { rawValue }
}

enum ContentSourceType: String, CaseIterable, Codable, Identifiable {
    case app
    case organization

    var id: String { rawValue }
}

struct ContentSourceMetadata: Codable, Equatable {
    let sourceType: ContentSourceType
    let organizationId: String?
    let organizationName: String?
    let organizationImageURL: String?

    nonisolated init(
        sourceType: ContentSourceType = .app,
        organizationId: String? = nil,
        organizationName: String? = nil,
        organizationImageURL: String? = nil
    ) {
        self.sourceType = sourceType
        self.organizationId = organizationId
        self.organizationName = organizationName
        self.organizationImageURL = organizationImageURL
    }
}

struct Comment: Identifiable, Codable {
    let id: String
    let authorName: String
    let body: String
    let createdAt: Date
    let updatedAt: Date
}

struct NewsPost: Identifiable, Codable {
    let id: String
    let title: String
    let subtitle: String
    let regionScope: RegionScope?
    let federalState: AustrianFederalState?
    let city: String?
    let source: ContentSourceMetadata
    let imageURL: String?
    let body: String
    let authorName: String
    let publishedAt: Date
    let createdAt: Date
    let updatedAt: Date
    let comments: [Comment]
    var moderationStatus: ModerationStatus
    var likeCount: Int
    var likeState: LikeState

    nonisolated init(
        id: String,
        title: String,
        subtitle: String,
        regionScope: RegionScope? = .federalState,
        federalState: AustrianFederalState? = .tirol,
        city: String? = nil,
        source: ContentSourceMetadata = ContentSourceMetadata(),
        imageURL: String? = nil,
        body: String,
        authorName: String,
        publishedAt: Date,
        createdAt: Date,
        updatedAt: Date,
        comments: [Comment],
        moderationStatus: ModerationStatus,
        likeCount: Int,
        likeState: LikeState
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.regionScope = regionScope
        self.federalState = federalState
        self.city = city
        self.source = source
        self.imageURL = imageURL
        self.body = body
        self.authorName = authorName
        self.publishedAt = publishedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.comments = comments
        self.moderationStatus = moderationStatus
        self.likeCount = likeCount
        self.likeState = likeState
    }
}

enum EventRegistrationState: String, Codable {
    case notRegistered
    case registered
    case waitlisted

    var title: String {
        switch self {
        case .notRegistered:
            AppStrings.Events.register
        case .registered:
            AppStrings.Events.registered
        case .waitlisted:
            AppStrings.Events.waitlisted
        }
    }
}

struct Event: Identifiable, Codable {
    let id: String
    let title: String
    let summary: String
    let details: String
    let regionScope: RegionScope?
    let federalState: AustrianFederalState?
    let source: ContentSourceMetadata
    let city: String
    let venue: String
    let imageURL: String?
    let startDate: Date
    let endDate: Date
    let createdAt: Date
    let updatedAt: Date
    let capacity: Int?
    let registeredCount: Int
    let comments: [Comment]
    var moderationStatus: ModerationStatus
    var registrationState: EventRegistrationState
    var likeCount: Int
    var likeState: LikeState

    nonisolated init(
        id: String,
        title: String,
        summary: String,
        details: String,
        regionScope: RegionScope? = .city,
        federalState: AustrianFederalState? = .tirol,
        source: ContentSourceMetadata = ContentSourceMetadata(),
        city: String,
        venue: String,
        imageURL: String? = nil,
        startDate: Date,
        endDate: Date,
        createdAt: Date,
        updatedAt: Date,
        capacity: Int?,
        registeredCount: Int,
        comments: [Comment],
        moderationStatus: ModerationStatus,
        registrationState: EventRegistrationState,
        likeCount: Int,
        likeState: LikeState
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.details = details
        self.regionScope = regionScope
        self.federalState = federalState
        self.source = source
        self.city = city
        self.venue = venue
        self.imageURL = imageURL
        self.startDate = startDate
        self.endDate = endDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.capacity = capacity
        self.registeredCount = registeredCount
        self.comments = comments
        self.moderationStatus = moderationStatus
        self.registrationState = registrationState
        self.likeCount = likeCount
        self.likeState = likeState
    }
}

struct Organization: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let regionScope: RegionScope?
    let federalState: AustrianFederalState?
    let city: String
    let imageURL: String?
    let contactEmail: String?
    let website: String?
    let createdAt: Date
    let updatedAt: Date
    var moderationStatus: ModerationStatus
    var likeCount: Int
    var likeState: LikeState

    nonisolated init(
        id: String,
        name: String,
        description: String,
        regionScope: RegionScope? = .city,
        federalState: AustrianFederalState? = .tirol,
        city: String,
        imageURL: String? = nil,
        contactEmail: String? = nil,
        website: String? = nil,
        createdAt: Date,
        updatedAt: Date,
        moderationStatus: ModerationStatus,
        likeCount: Int,
        likeState: LikeState
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.regionScope = regionScope
        self.federalState = federalState
        self.city = city
        self.imageURL = imageURL
        self.contactEmail = contactEmail
        self.website = website
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.moderationStatus = moderationStatus
        self.likeCount = likeCount
        self.likeState = likeState
    }
}

enum ModerationStatus: String, Codable {
    case draft
    case pendingReview
    case approved
    case rejected
    case archived

    var title: String {
        switch self {
        case .draft:
            AppStrings.Common.draft
        case .pendingReview:
            AppStrings.Common.pendingReview
        case .approved:
            AppStrings.Common.approved
        case .rejected:
            AppStrings.Common.rejected
        case .archived:
            AppStrings.Common.archived
        }
    }
}

struct HomeHighlight: Identifiable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
}

enum HomeFeedSourceType: String, Codable {
    case app
    case organization
}

enum HomeFeedItemType: String, Codable {
    case news
    case event
    case organization
}

enum HomeFeedDestinationReference: Equatable {
    case news(id: String)
    case event(id: String)
    case organization(id: String)
}

struct HomeFeedItem: Identifiable, Equatable {
    let id: String
    let sourceType: HomeFeedSourceType
    let itemType: HomeFeedItemType
    let title: String
    let summary: String
    let imageURL: String?
    let publishedAt: Date
    let regionScope: RegionScope?
    let federalState: AustrianFederalState?
    let city: String?
    let eventStartDate: Date?
    let eventVenue: String?
    let organizationId: String?
    let organizationName: String?
    let likeCount: Int
    let destination: HomeFeedDestinationReference

    init(post: NewsPost) {
        id = "news-\(post.id)"
        sourceType = post.source.sourceType == .organization ? .organization : .app
        itemType = .news
        title = post.title
        summary = post.subtitle
        imageURL = post.imageURL
        publishedAt = post.publishedAt
        regionScope = post.regionScope
        federalState = post.federalState
        city = post.city
        eventStartDate = nil
        eventVenue = nil
        organizationId = post.source.organizationId
        organizationName = post.source.organizationName
        likeCount = post.likeCount
        destination = .news(id: post.id)
    }

    init(event: Event) {
        id = "event-\(event.id)"
        sourceType = event.source.sourceType == .organization ? .organization : .app
        itemType = .event
        title = event.title
        summary = event.summary
        imageURL = event.imageURL
        publishedAt = event.createdAt
        regionScope = event.regionScope
        federalState = event.federalState
        city = event.city
        eventStartDate = event.startDate
        eventVenue = event.venue
        organizationId = event.source.organizationId
        organizationName = event.source.organizationName
        likeCount = event.likeCount
        destination = .event(id: event.id)
    }

    init(organization: Organization) {
        id = "organization-\(organization.id)"
        sourceType = .organization
        itemType = .organization
        title = organization.name
        summary = organization.description
        imageURL = organization.imageURL
        publishedAt = organization.createdAt
        regionScope = organization.regionScope
        federalState = organization.federalState
        city = organization.city
        eventStartDate = nil
        eventVenue = nil
        organizationId = organization.id
        organizationName = organization.name
        likeCount = organization.likeCount
        destination = .organization(id: organization.id)
    }
}

enum OrganizationActivityItemType: String, Codable {
    case news
    case event
    case organizationProfile
}

struct OrganizationActivityItem: Identifiable, Equatable {
    let id: String
    let itemType: OrganizationActivityItemType
    let title: String
    let summary: String
    let imageURL: String?
    let publishedAt: Date
    let city: String?
    let eventStartDate: Date?
    let eventVenue: String?
    let organizationId: String
    let organizationName: String
    let destination: HomeFeedDestinationReference?

    init(profile organization: Organization) {
        id = "organization-profile-\(organization.id)"
        itemType = .organizationProfile
        title = organization.name
        summary = organization.description
        imageURL = organization.imageURL
        publishedAt = organization.updatedAt
        city = organization.city
        eventStartDate = nil
        eventVenue = nil
        organizationId = organization.id
        organizationName = organization.name
        destination = nil
    }

    init(post: NewsPost) {
        id = "organization-news-\(post.id)"
        itemType = .news
        title = post.title
        summary = post.subtitle
        imageURL = post.imageURL
        publishedAt = post.publishedAt
        city = post.city
        eventStartDate = nil
        eventVenue = nil
        organizationId = post.source.organizationId ?? ""
        organizationName = post.source.organizationName ?? ""
        destination = .news(id: post.id)
    }

    init(event: Event) {
        id = "organization-event-\(event.id)"
        itemType = .event
        title = event.title
        summary = event.summary
        imageURL = event.imageURL
        publishedAt = event.createdAt
        city = event.city
        eventStartDate = event.startDate
        eventVenue = event.venue
        organizationId = event.source.organizationId ?? ""
        organizationName = event.source.organizationName ?? ""
        destination = .event(id: event.id)
    }
}

enum GuideCategory: String, CaseIterable, Codable, Identifiable {
    case documents
    case anmeldung
    case work
    case ams
    case housing
    case medicine
    case children
    case education
    case business
    case contacts
    case emergency

    var id: String { rawValue }

    var title: String {
        switch self {
        case .documents:
            AppStrings.Info.categoryDocuments
        case .anmeldung:
            AppStrings.Info.categoryAnmeldung
        case .work:
            AppStrings.Info.categoryWork
        case .ams:
            AppStrings.Info.categoryAMS
        case .housing:
            AppStrings.Info.categoryHousing
        case .medicine:
            AppStrings.Info.categoryMedicine
        case .children:
            AppStrings.Info.categoryChildren
        case .education:
            AppStrings.Info.categoryEducation
        case .business:
            AppStrings.Info.categoryBusiness
        case .contacts:
            AppStrings.Info.categoryContacts
        case .emergency:
            AppStrings.Info.categoryEmergency
        }
    }

    var systemImage: String {
        switch self {
        case .documents:
            "doc.text"
        case .anmeldung:
            "building.columns"
        case .work:
            "briefcase"
        case .ams:
            "person.text.rectangle"
        case .housing:
            "house"
        case .medicine:
            "cross.case"
        case .children:
            "figure.and.child.holdinghands"
        case .education:
            "book"
        case .business:
            "building.2"
        case .contacts:
            "phone"
        case .emergency:
            "exclamationmark.triangle"
        }
    }
}

struct GuideArticle: Identifiable, Codable {
    let id: String
    let title: String
    let summary: String
    let body: String
    let category: GuideCategory
    let regionScope: RegionScope?
    let federalState: AustrianFederalState?
    let city: String?
    let officialSourceURL: String?
    let sourceName: String?
    let isPinned: Bool
    let moderationStatus: ModerationStatus
    let createdAt: Date
    let updatedAt: Date

    nonisolated init(
        id: String,
        title: String,
        summary: String,
        body: String,
        category: GuideCategory,
        regionScope: RegionScope? = .austria,
        federalState: AustrianFederalState? = nil,
        city: String? = nil,
        officialSourceURL: String? = nil,
        sourceName: String? = nil,
        isPinned: Bool = false,
        moderationStatus: ModerationStatus = .approved,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.body = body
        self.category = category
        self.regionScope = regionScope
        self.federalState = federalState
        self.city = city
        self.officialSourceURL = officialSourceURL
        self.sourceName = sourceName
        self.isPinned = isPinned
        self.moderationStatus = moderationStatus
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct InfoItem: Identifiable {
    let id: String
    let title: String
    let body: String
    let systemImage: String
    let regionScope: RegionScope?
    let federalState: AustrianFederalState?
    let city: String?

    nonisolated init(
        id: String,
        title: String,
        body: String,
        systemImage: String,
        regionScope: RegionScope? = .austria,
        federalState: AustrianFederalState? = nil,
        city: String? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.systemImage = systemImage
        self.regionScope = regionScope
        self.federalState = federalState
        self.city = city
    }
}
