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

enum NewsCategory: String, CaseIterable, Codable, Identifiable {
    case news
    case event
    case education
    case culture
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .news:
            AppStrings.NewsEditor.categoryNews
        case .event:
            AppStrings.NewsEditor.categoryEvent
        case .education:
            AppStrings.NewsEditor.categoryEducation
        case .culture:
            AppStrings.NewsEditor.categoryCulture
        case .other:
            AppStrings.NewsEditor.categoryOther
        }
    }

    var systemImage: String {
        switch self {
        case .news:
            "newspaper"
        case .event:
            "calendar"
        case .education:
            "graduationcap"
        case .culture:
            "theatermasks"
        case .other:
            "square.grid.2x2"
        }
    }
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

    var displayOrganizationId: String? {
        if sourceType == .app {
            return Organization.systemOrganizationID
        }
        return organizationId
    }

    var displayOrganizationName: String? {
        let trimmedName = organizationName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedName, !trimmedName.isEmpty {
            return trimmedName
        }
        if sourceType == .app {
            return Organization.systemOrganizationName
        }
        return nil
    }
}

enum CommentParentType: String, Codable {
    case news
    case event
    case organization
}

struct Comment: Identifiable, Codable {
    let id: String
    let parentType: CommentParentType?
    let parentId: String?
    let authorId: String?
    let authorName: String
    let authorPhotoURL: String?
    let text: String
    let createdAt: Date
    let updatedAt: Date?
    let moderationStatus: ModerationStatus
    let isDeleted: Bool

    var body: String { text }

    nonisolated init(
        id: String,
        parentType: CommentParentType? = nil,
        parentId: String? = nil,
        authorId: String? = nil,
        authorName: String,
        authorPhotoURL: String? = nil,
        text: String? = nil,
        body: String? = nil,
        createdAt: Date,
        updatedAt: Date? = nil,
        moderationStatus: ModerationStatus = .approved,
        isDeleted: Bool = false
    ) {
        self.id = id
        self.parentType = parentType
        self.parentId = parentId
        self.authorId = authorId
        self.authorName = authorName
        self.authorPhotoURL = authorPhotoURL
        self.text = text ?? body ?? ""
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.moderationStatus = moderationStatus
        self.isDeleted = isDeleted
    }
}

struct NewsPost: Identifiable, Codable {
    let id: String
    let title: String
    let subtitle: String
    let regionScope: RegionScope?
    let federalState: AustrianFederalState?
    let city: String?
    let category: NewsCategory
    let tags: [String]
    let source: ContentSourceMetadata
    let imageURL: String?
    let body: String
    let authorName: String
    let publishedAt: Date
    let createdAt: Date
    let updatedAt: Date
    var comments: [Comment]
    var moderationStatus: ModerationStatus
    var likeCount: Int
    var likeState: LikeState
    var viewCount: Int
    var isBookmarked: Bool
    var commentCount: Int

    nonisolated init(
        id: String,
        title: String,
        subtitle: String,
        regionScope: RegionScope? = .federalState,
        federalState: AustrianFederalState? = .tirol,
        city: String? = nil,
        category: NewsCategory = .news,
        tags: [String] = [],
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
        likeState: LikeState,
        viewCount: Int = 0,
        isBookmarked: Bool = false,
        commentCount: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.regionScope = regionScope
        self.federalState = federalState
        self.city = city
        self.category = category
        self.tags = tags
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
        self.viewCount = viewCount
        self.isBookmarked = isBookmarked
        self.commentCount = max(0, commentCount ?? comments.filter { !$0.isDeleted }.count)
    }
}

struct OrganizationPhoto: Identifiable, Codable, Equatable {
    let id: String
    let organizationId: String
    let imageURL: String
    let caption: String?
    let uploadedBy: String
    let createdAt: Date
    let updatedAt: Date?

    nonisolated init(
        id: String,
        organizationId: String,
        imageURL: String,
        caption: String? = nil,
        uploadedBy: String,
        createdAt: Date,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.organizationId = organizationId
        self.imageURL = imageURL
        self.caption = caption
        self.uploadedBy = uploadedBy
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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

enum EventCategory: String, CaseIterable, Codable, Identifiable {
    case unspecified
    case meetups
    case training
    case culture
    case education
    case other

    static var allCases: [EventCategory] {
        [.meetups, .training, .culture, .education, .other]
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unspecified:
            AppStrings.Events.genericEventBadge
        case .meetups:
            AppStrings.Events.categoryMeetups
        case .training:
            AppStrings.Events.categoryTraining
        case .culture:
            AppStrings.Events.categoryCulture
        case .education:
            AppStrings.Events.categoryEducation
        case .other:
            AppStrings.Events.categoryOther
        }
    }

    var systemImage: String {
        switch self {
        case .unspecified:
            "calendar"
        case .meetups:
            "person.2"
        case .training:
            "graduationcap"
        case .culture:
            "theatermasks"
        case .education:
            "book"
        case .other:
            "square.grid.2x2"
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
    let authorId: String?
    let authorName: String?
    let city: String
    let venue: String
    let address: String?
    let locationNote: String?
    let latitude: Double?
    let longitude: Double?
    let imageURL: String?
    let startDate: Date
    let endDate: Date
    let createdAt: Date
    let updatedAt: Date
    let price: Double
    let capacity: Int?
    let registeredCount: Int
    var comments: [Comment]
    var moderationStatus: ModerationStatus
    var registrationState: EventRegistrationState
    var likeCount: Int
    var likeState: LikeState
    var viewCount: Int
    let category: EventCategory
    let isAllDay: Bool
    var isBookmarked: Bool
    var commentCount: Int

    nonisolated init(
        id: String,
        title: String,
        summary: String,
        details: String,
        regionScope: RegionScope? = .city,
        federalState: AustrianFederalState? = .tirol,
        source: ContentSourceMetadata = ContentSourceMetadata(),
        authorId: String? = nil,
        authorName: String? = nil,
        city: String,
        venue: String,
        address: String? = nil,
        locationNote: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        imageURL: String? = nil,
        startDate: Date,
        endDate: Date,
        createdAt: Date,
        updatedAt: Date,
        price: Double = 0,
        capacity: Int?,
        registeredCount: Int,
        comments: [Comment],
        moderationStatus: ModerationStatus,
        registrationState: EventRegistrationState,
        likeCount: Int,
        likeState: LikeState,
        viewCount: Int = 0,
        category: EventCategory = .meetups,
        isAllDay: Bool = false,
        isBookmarked: Bool = false,
        commentCount: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.details = details
        self.regionScope = regionScope
        self.federalState = federalState
        self.source = source
        self.authorId = authorId
        self.authorName = authorName
        self.city = city
        self.venue = venue
        self.address = address
        let trimmedLocationNote = locationNote?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.locationNote = trimmedLocationNote?.isEmpty == true ? nil : trimmedLocationNote
        self.latitude = latitude
        self.longitude = longitude
        self.imageURL = imageURL
        self.startDate = startDate
        self.endDate = endDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.price = max(0, price)
        self.capacity = capacity
        self.registeredCount = registeredCount
        self.comments = comments
        self.moderationStatus = moderationStatus
        self.registrationState = registrationState
        self.likeCount = likeCount
        self.likeState = likeState
        self.viewCount = viewCount
        self.category = category
        self.isAllDay = isAllDay
        self.isBookmarked = isBookmarked
        self.commentCount = max(0, commentCount ?? comments.filter { !$0.isDeleted }.count)
    }
}

struct Organization: Identifiable, Codable {
    let id: String
    let name: String
    let description: String
    let shortDescription: String
    let fullDescription: String
    let regionScope: RegionScope?
    let federalState: AustrianFederalState?
    let city: String
    let imageURL: String?
    let logoURL: String?
    let coverURL: String?
    let contactEmail: String?
    let email: String?
    let phone: String?
    let website: String?
    let address: String?
    let latitude: Double?
    let longitude: Double?
    let organizationType: String?
    let foundedYear: Int?
    let foundedMonth: Int?
    let languages: [String]
    let socialLinks: [String: String]
    let telegramURL: String?
    let donationURL: String?
    let missionStatement: String?
    let contactPerson: String?
    var subscriberCount: Int
    let eventsHeldCount: Int
    let volunteersCount: Int
    let helpedPeopleCount: Int
    let ownerId: String?
    let adminIds: [String]
    let moderatorIds: [String]
    let isSystemManaged: Bool?
    let sourceType: ContentSourceType?
    let pinnedNewsId: String?
    let pinnedEventId: String?
    let submittedByUserId: String?
    let submittedByDisplayName: String?
    let submittedAt: Date?
    let reviewMessage: String?
    let reviewedByUserId: String?
    let reviewedAt: Date?
    let rejectionReason: String?
    let createdAt: Date
    let updatedAt: Date
    var moderationStatus: ModerationStatus
    var likeCount: Int
    var likeState: LikeState
    var isSubscribed: Bool
    var isBookmarked: Bool

    nonisolated init(
        id: String,
        name: String,
        description: String,
        shortDescription: String? = nil,
        fullDescription: String? = nil,
        regionScope: RegionScope? = .city,
        federalState: AustrianFederalState? = .tirol,
        city: String,
        imageURL: String? = nil,
        logoURL: String? = nil,
        coverURL: String? = nil,
        contactEmail: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        website: String? = nil,
        address: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        organizationType: String? = nil,
        foundedYear: Int? = nil,
        foundedMonth: Int? = nil,
        languages: [String] = [],
        socialLinks: [String: String] = [:],
        telegramURL: String? = nil,
        donationURL: String? = nil,
        missionStatement: String? = nil,
        contactPerson: String? = nil,
        subscriberCount: Int = 0,
        eventsHeldCount: Int = 0,
        volunteersCount: Int = 0,
        helpedPeopleCount: Int = 0,
        ownerId: String? = nil,
        adminIds: [String] = [],
        moderatorIds: [String] = [],
        isSystemManaged: Bool? = nil,
        sourceType: ContentSourceType? = nil,
        pinnedNewsId: String? = nil,
        pinnedEventId: String? = nil,
        submittedByUserId: String? = nil,
        submittedByDisplayName: String? = nil,
        submittedAt: Date? = nil,
        reviewMessage: String? = nil,
        reviewedByUserId: String? = nil,
        reviewedAt: Date? = nil,
        rejectionReason: String? = nil,
        createdAt: Date,
        updatedAt: Date,
        moderationStatus: ModerationStatus,
        likeCount: Int,
        likeState: LikeState,
        isSubscribed: Bool = false,
        isBookmarked: Bool = false
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.shortDescription = Self.normalizedOptionalString(shortDescription) ?? description
        self.fullDescription = Self.normalizedOptionalString(fullDescription) ?? description
        self.regionScope = regionScope
        self.federalState = federalState
        self.city = city
        self.logoURL = Self.normalizedOptionalString(logoURL) ?? Self.normalizedOptionalString(imageURL)
        self.coverURL = Self.normalizedOptionalString(coverURL) ?? Self.normalizedOptionalString(imageURL)
        self.imageURL = Self.normalizedOptionalString(imageURL) ?? self.logoURL ?? self.coverURL
        self.contactEmail = Self.normalizedOptionalString(contactEmail) ?? Self.normalizedOptionalString(email)
        self.email = Self.normalizedOptionalString(email) ?? Self.normalizedOptionalString(contactEmail)
        self.phone = Self.normalizedOptionalString(phone)
        self.website = website
        self.address = Self.normalizedOptionalString(address)
        self.latitude = latitude
        self.longitude = longitude
        self.organizationType = Self.normalizedOptionalString(organizationType)
        self.foundedYear = foundedYear
        self.foundedMonth = foundedMonth.flatMap { (1...12).contains($0) ? $0 : nil }
        self.languages = languages
        self.socialLinks = socialLinks
        self.telegramURL = Self.normalizedOptionalString(telegramURL)
        self.donationURL = Self.normalizedOptionalString(donationURL)
        self.missionStatement = Self.normalizedOptionalString(missionStatement)
        self.contactPerson = Self.normalizedOptionalString(contactPerson)
        self.subscriberCount = max(0, subscriberCount)
        self.eventsHeldCount = max(0, eventsHeldCount)
        self.volunteersCount = max(0, volunteersCount)
        self.helpedPeopleCount = max(0, helpedPeopleCount)
        self.ownerId = Self.normalizedOptionalString(ownerId)
        self.adminIds = adminIds
        self.moderatorIds = moderatorIds
        self.isSystemManaged = isSystemManaged
        self.sourceType = sourceType
        self.pinnedNewsId = Self.normalizedOptionalString(pinnedNewsId)
        self.pinnedEventId = Self.normalizedOptionalString(pinnedEventId)
        self.submittedByUserId = Self.normalizedOptionalString(submittedByUserId)
        self.submittedByDisplayName = Self.normalizedOptionalString(submittedByDisplayName)
        self.submittedAt = submittedAt
        self.reviewMessage = Self.normalizedOptionalString(reviewMessage)
        self.reviewedByUserId = Self.normalizedOptionalString(reviewedByUserId)
        self.reviewedAt = reviewedAt
        self.rejectionReason = Self.normalizedOptionalString(rejectionReason)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.moderationStatus = moderationStatus
        self.likeCount = likeCount
        self.likeState = likeState
        self.isSubscribed = isSubscribed
        self.isBookmarked = isBookmarked
    }

    nonisolated private static func normalizedOptionalString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension Organization {
    static let systemOrganizationID = "ukrainian-community"
    static let systemOrganizationName = "Ukrainian Community"

    var isSystemOrganization: Bool {
        isSystemManaged == true || id == Self.systemOrganizationID
    }
}

struct OrganizationSubscriberReference: Identifiable, Hashable {
    let userID: String
    let followedAt: Date?
    let documentID: String

    var id: String { userID }
}

struct OrganizationSubscriberCursor: Hashable {
    let followedAt: Date
    let documentID: String
}

struct OrganizationSubscriberPage: Hashable {
    let items: [OrganizationSubscriberReference]
    let nextCursor: OrganizationSubscriberCursor?
    let hasMore: Bool
}

enum ModerationStatus: String, Codable {
    case draft
    case pendingReview
    case needsRevision
    case approved
    case rejected
    case archived

    var title: String {
        switch self {
        case .draft:
            AppStrings.Common.draft
        case .pendingReview:
            AppStrings.Common.pendingReview
        case .needsRevision:
            AppStrings.Common.needsRevision
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
    let eventEndDate: Date?
    let eventVenue: String?
    let organizationId: String?
    let organizationName: String?
    let organizationType: String?
    let authorName: String?
    let isSaved: Bool
    let likeCount: Int
    let subscriberCount: Int
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
        eventEndDate = nil
        eventVenue = nil
        organizationId = post.source.organizationId
        organizationName = post.source.displayOrganizationName
        organizationType = nil
        authorName = post.authorName
        isSaved = post.isBookmarked
        likeCount = post.likeCount
        subscriberCount = 0
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
        eventEndDate = event.endDate
        eventVenue = event.venue
        organizationId = event.source.organizationId
        organizationName = event.source.displayOrganizationName
        organizationType = nil
        authorName = event.authorName
        isSaved = event.isBookmarked
        likeCount = event.likeCount
        subscriberCount = 0
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
        eventEndDate = nil
        eventVenue = nil
        organizationId = organization.id
        organizationName = organization.name
        organizationType = organization.organizationType
        authorName = nil
        isSaved = false
        likeCount = organization.likeCount
        subscriberCount = organization.subscriberCount
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
    let eventRegistrationState: EventRegistrationState?
    let isBookmarked: Bool
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
        eventRegistrationState = nil
        isBookmarked = false
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
        eventRegistrationState = nil
        isBookmarked = post.isBookmarked
        organizationId = post.source.displayOrganizationId ?? ""
        organizationName = post.source.displayOrganizationName ?? ""
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
        eventRegistrationState = event.registrationState
        isBookmarked = event.isBookmarked
        organizationId = event.source.displayOrganizationId ?? ""
        organizationName = event.source.displayOrganizationName ?? ""
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
