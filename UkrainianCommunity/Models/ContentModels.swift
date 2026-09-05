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

    var displayName: String {
        AppStrings.FederalStates.title(for: self)
    }
}

enum RegionScope: String, CaseIterable, Codable, Identifiable {
    case austria
    case federalState
    case city

    var id: String { rawValue }
}

enum ContentPublicationMode: String, CaseIterable, Codable, Identifiable {
    case now
    case scheduled

    var id: String { rawValue }
}

enum NewsCategory: String, CaseIterable, Codable, Identifiable {
    case news
    case event
    case lawAndDocuments
    case benefitsAndSupport
    case financeTaxesAndConsumerRights
    case health
    case safetyAndEmergencies
    case work
    case education
    case housing
    case transport
    case communityAndIntegration
    case culture
    case other

    var id: String { rawValue }

    nonisolated static let maximumAdditionalCategoryCount = 2

    var title: String {
        switch self {
        case .news:
            AppStrings.NewsEditor.categoryNews
        case .event:
            AppStrings.NewsEditor.categoryEvent
        case .lawAndDocuments:
            AppStrings.NewsEditor.categoryLawAndDocuments
        case .benefitsAndSupport:
            AppStrings.NewsEditor.categoryBenefitsAndSupport
        case .financeTaxesAndConsumerRights:
            AppStrings.NewsEditor.categoryFinanceTaxesAndConsumerRights
        case .health:
            AppStrings.NewsEditor.categoryHealth
        case .safetyAndEmergencies:
            AppStrings.NewsEditor.categorySafetyAndEmergencies
        case .work:
            AppStrings.NewsEditor.categoryWork
        case .education:
            AppStrings.NewsEditor.categoryEducation
        case .housing:
            AppStrings.NewsEditor.categoryHousing
        case .transport:
            AppStrings.NewsEditor.categoryTransport
        case .communityAndIntegration:
            AppStrings.NewsEditor.categoryCommunityAndIntegration
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
        case .lawAndDocuments:
            "doc.text"
        case .benefitsAndSupport:
            "hand.raised"
        case .financeTaxesAndConsumerRights:
            "eurosign.circle"
        case .health:
            "cross.case"
        case .safetyAndEmergencies:
            "exclamationmark.shield"
        case .work:
            "briefcase"
        case .education:
            "graduationcap"
        case .housing:
            "house"
        case .transport:
            "tram"
        case .communityAndIntegration:
            "person.3"
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
    let schemaVersion: Int
    let localizations: [String: NewsLocalizedContent]
    let id: String
    let title: String
    let subtitle: String
    let regionScope: RegionScope?
    let federalState: AustrianFederalState?
    let city: String?
    let category: NewsCategory
    let additionalCategories: [NewsCategory]
    let tags: [String]
    let source: ContentSourceMetadata
    let sourceName: String?
    let sourceURL: String?
    let imageURL: String?
    let mediaMetadata: NewsMediaMetadata?
    let externalAction: ExternalContentAction?
    let body: String
    let authorId: String?
    let authorName: String
    let publishedAt: Date
    let scheduledAt: Date?
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
        schemaVersion: Int = 1,
        localizations: [String: NewsLocalizedContent] = [:],
        title: String,
        subtitle: String,
        regionScope: RegionScope? = .federalState,
        federalState: AustrianFederalState? = .tirol,
        city: String? = nil,
        category: NewsCategory = .news,
        additionalCategories: [NewsCategory] = [],
        tags: [String] = [],
        source: ContentSourceMetadata = ContentSourceMetadata(),
        sourceName: String? = nil,
        sourceURL: String? = nil,
        imageURL: String? = nil,
        mediaMetadata: NewsMediaMetadata? = nil,
        externalAction: ExternalContentAction? = nil,
        body: String,
        authorId: String? = nil,
        authorName: String,
        publishedAt: Date,
        scheduledAt: Date? = nil,
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
        self.schemaVersion = max(1, schemaVersion)
        self.localizations = localizations
        self.title = title
        self.subtitle = subtitle
        self.regionScope = regionScope
        self.federalState = federalState
        self.city = city
        self.category = category
        self.additionalCategories = Array(additionalCategories.reduce(into: [NewsCategory]()) { result, candidate in
            guard candidate != category, !result.contains(candidate) else { return }
            result.append(candidate)
        }.prefix(NewsCategory.maximumAdditionalCategoryCount))
        self.tags = tags
        self.source = source
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.imageURL = imageURL
        self.mediaMetadata = mediaMetadata
        self.externalAction = externalAction
        self.body = body
        self.authorId = authorId
        self.authorName = authorName
        self.publishedAt = publishedAt
        self.scheduledAt = scheduledAt
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

    nonisolated var localizedContent: NewsLocalizedContent {
        localizations.resolved(for: LocalizationStore.language)
            ?? NewsLocalizedContent(title: title, subtitle: subtitle, body: body)
    }

    nonisolated var localizedTitle: String { localizedContent.title }
    nonisolated var localizedSubtitle: String { localizedContent.subtitle }
    nonisolated var localizedBody: String { localizedContent.body }
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

struct EventRegistrationAttendee: Identifiable, Codable, Equatable {
    let id: String
    let eventID: String
    let userID: String
    let registeredAt: Date?
    let displayName: String?
    let email: String?
    let avatarURL: URL?

    nonisolated init(
        id: String,
        eventID: String,
        userID: String,
        registeredAt: Date? = nil,
        displayName: String? = nil,
        email: String? = nil,
        avatarURL: URL? = nil
    ) {
        self.id = id
        self.eventID = eventID
        self.userID = userID
        self.registeredAt = registeredAt
        self.displayName = Self.trimmedOptional(displayName)
        self.email = Self.trimmedOptional(email)
        self.avatarURL = avatarURL
    }

    var displayTitle: String {
        displayName ?? AppStrings.Events.registrationParticipantFallback
    }

    var displaySubtitle: String {
        email ?? userID
    }

    var initials: String {
        let source = displayName ?? userID
        return String(source.prefix(1)).uppercased()
    }

    nonisolated private static func trimmedOptional(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == true ? nil : trimmed
    }
}

enum EventCategory: String, CaseIterable, Codable, Identifiable {
    case unspecified
    case meetups
    case training
    case culture
    case education
    case childrenAndFamily
    case sportsAndWellness
    case excursionsAndNature
    case music
    case nightlifeAndParties
    case foodAndMarket
    case festivalsAndFairs
    case businessAndNetworking
    case volunteering
    case supportAndIntegration
    case celebration
    case saleAndPromotion
    case other

    static var allCases: [EventCategory] {
        [
            .meetups, .childrenAndFamily, .culture, .music, .education,
            .training, .sportsAndWellness, .excursionsAndNature,
            .nightlifeAndParties, .foodAndMarket, .festivalsAndFairs,
            .businessAndNetworking, .volunteering, .supportAndIntegration,
            .celebration, .saleAndPromotion, .other
        ]
    }

    var id: String { rawValue }

    nonisolated static let maximumAdditionalCategoryCount = 2

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
        case .childrenAndFamily:
            AppStrings.Events.categoryChildrenAndFamily
        case .sportsAndWellness:
            AppStrings.Events.categorySportsAndWellness
        case .excursionsAndNature:
            AppStrings.Events.categoryExcursionsAndNature
        case .music:
            AppStrings.Events.categoryMusic
        case .nightlifeAndParties:
            AppStrings.Events.categoryNightlifeAndParties
        case .foodAndMarket:
            AppStrings.Events.categoryFoodAndMarket
        case .festivalsAndFairs:
            AppStrings.Events.categoryFestivalsAndFairs
        case .businessAndNetworking:
            AppStrings.Events.categoryBusinessAndNetworking
        case .volunteering:
            AppStrings.Events.categoryVolunteering
        case .supportAndIntegration:
            AppStrings.Events.categorySupportAndIntegration
        case .celebration:
            AppStrings.Events.categoryCelebration
        case .saleAndPromotion:
            AppStrings.Events.categorySaleAndPromotion
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
        case .childrenAndFamily:
            "figure.2.and.child.holdinghands"
        case .sportsAndWellness:
            "figure.run"
        case .excursionsAndNature:
            "mountain.2"
        case .music:
            "music.note"
        case .nightlifeAndParties:
            "moon.stars"
        case .foodAndMarket:
            "fork.knife"
        case .festivalsAndFairs:
            "flag.2.crossed"
        case .businessAndNetworking:
            "briefcase"
        case .volunteering:
            "hands.sparkles"
        case .supportAndIntegration:
            "person.2.wave.2"
        case .celebration:
            "party.popper"
        case .saleAndPromotion:
            "tag"
        case .other:
            "square.grid.2x2"
        }
    }
}

enum EventAudience: String, CaseIterable, Codable, Identifiable {
    case everyone
    case families
    case children
    case teens
    case adults
    case seniors

    var id: String { rawValue }

    var title: String {
        switch self {
        case .everyone: AppStrings.Events.audienceEveryone
        case .families: AppStrings.Events.audienceFamilies
        case .children: AppStrings.Events.audienceChildren
        case .teens: AppStrings.Events.audienceTeens
        case .adults: AppStrings.Events.audienceAdults
        case .seniors: AppStrings.Events.audienceSeniors
        }
    }

    var systemImage: String {
        switch self {
        case .everyone: "person.3"
        case .families: "figure.2.and.child.holdinghands"
        case .children: "figure.and.child.holdinghands"
        case .teens: "person.2"
        case .adults: "person.crop.circle"
        case .seniors: "figure.walk"
        }
    }
}

struct Event: Identifiable, Codable {
    let schemaVersion: Int
    let localizations: [String: EventLocalizedContent]
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
    let organizerName: String?
    let organizerURL: String?
    let contactPhone: String?
    let contactEmail: String?
    let contactURL: String?
    let imageURL: String?
    let mediaMetadata: EventMediaMetadata?
    let startDate: Date
    let endDate: Date
    let occurrences: [EventOccurrence]
    let createdAt: Date
    let updatedAt: Date
    let scheduledAt: Date?
    let requiresRegistration: Bool
    let participationMode: EventParticipationMode
    let externalAction: ExternalContentAction?
    let price: Double
    let pricing: EventPricing
    let capacity: Int?
    let registeredCount: Int
    var comments: [Comment]
    var moderationStatus: ModerationStatus
    var registrationState: EventRegistrationState
    var likeCount: Int
    var likeState: LikeState
    var viewCount: Int
    let category: EventCategory
    let additionalCategories: [EventCategory]
    let audience: EventAudience
    let minimumAge: Int?
    let maximumAge: Int?
    let tags: [String]
    let isAllDay: Bool
    var isBookmarked: Bool
    var commentCount: Int
    let cancellationState: String?
    let cancelledAt: Date?
    let cancellationReason: String?

    nonisolated init(
        id: String,
        schemaVersion: Int = 1,
        localizations: [String: EventLocalizedContent] = [:],
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
        organizerName: String? = nil,
        organizerURL: String? = nil,
        contactPhone: String? = nil,
        contactEmail: String? = nil,
        contactURL: String? = nil,
        imageURL: String? = nil,
        mediaMetadata: EventMediaMetadata? = nil,
        startDate: Date,
        endDate: Date,
        occurrences: [EventOccurrence] = [],
        createdAt: Date,
        updatedAt: Date,
        scheduledAt: Date? = nil,
        requiresRegistration: Bool = true,
        participationMode: EventParticipationMode? = nil,
        externalAction: ExternalContentAction? = nil,
        price: Double = 0,
        pricing: EventPricing? = nil,
        capacity: Int?,
        registeredCount: Int,
        comments: [Comment],
        moderationStatus: ModerationStatus,
        registrationState: EventRegistrationState,
        likeCount: Int,
        likeState: LikeState,
        viewCount: Int = 0,
        category: EventCategory = .meetups,
        additionalCategories: [EventCategory] = [],
        audience: EventAudience = .everyone,
        minimumAge: Int? = nil,
        maximumAge: Int? = nil,
        tags: [String] = [],
        isAllDay: Bool = false,
        isBookmarked: Bool = false,
        commentCount: Int? = nil,
        cancellationState: String? = nil,
        cancelledAt: Date? = nil,
        cancellationReason: String? = nil
    ) {
        self.id = id
        self.schemaVersion = max(1, schemaVersion)
        self.localizations = localizations
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
        self.organizerName = Self.trimmedOptional(organizerName)
        self.organizerURL = Self.trimmedOptional(organizerURL)
        self.contactPhone = Self.trimmedOptional(contactPhone)
        self.contactEmail = Self.trimmedOptional(contactEmail)
        self.contactURL = Self.trimmedOptional(contactURL)
        self.imageURL = imageURL
        self.mediaMetadata = mediaMetadata
        let validOccurrences = occurrences.filter(\.isValid).sorted { $0.startDate < $1.startDate }
        self.occurrences = validOccurrences.isEmpty
            ? [EventOccurrence(startDate: startDate, endDate: endDate, isAllDay: isAllDay)]
            : validOccurrences
        self.startDate = self.occurrences.first?.startDate ?? startDate
        self.endDate = self.occurrences.map(\.endDate).max() ?? endDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.scheduledAt = scheduledAt
        self.requiresRegistration = requiresRegistration
        self.participationMode = participationMode ?? (requiresRegistration ? .inAppRegistration : .none)
        self.externalAction = externalAction
        self.price = max(0, price)
        self.pricing = pricing ?? EventPricing(
            kind: price > 0 ? .exact : .free,
            amount: price > 0 ? price : nil
        )
        self.capacity = capacity
        self.registeredCount = registeredCount
        self.comments = comments
        self.moderationStatus = moderationStatus
        self.registrationState = registrationState
        self.likeCount = likeCount
        self.likeState = likeState
        self.viewCount = viewCount
        self.category = category
        self.additionalCategories = Array(additionalCategories.reduce(into: [EventCategory]()) { result, candidate in
            guard candidate != category, candidate != .unspecified, !result.contains(candidate) else { return }
            result.append(candidate)
        }.prefix(EventCategory.maximumAdditionalCategoryCount))
        self.audience = audience
        let normalizedMinimumAge = minimumAge.map { min(max(0, $0), 120) }
        let normalizedMaximumAge = maximumAge.map { min(max(0, $0), 120) }
        if let normalizedMinimumAge, let normalizedMaximumAge, normalizedMaximumAge < normalizedMinimumAge {
            self.minimumAge = nil
            self.maximumAge = nil
        } else {
            self.minimumAge = normalizedMinimumAge
            self.maximumAge = normalizedMaximumAge
        }
        self.tags = Self.normalizedTags(tags)
        self.isAllDay = isAllDay
        self.isBookmarked = isBookmarked
        self.commentCount = max(0, commentCount ?? comments.filter { !$0.isDeleted }.count)
        self.cancellationState = Self.trimmedOptional(cancellationState)
        self.cancelledAt = cancelledAt
        self.cancellationReason = Self.trimmedOptional(cancellationReason)
    }

    nonisolated var isCancelled: Bool {
        cancellationState == "cancelled"
    }

    nonisolated var localizedContent: EventLocalizedContent {
        localizations.resolved(for: LocalizationStore.language)
            ?? EventLocalizedContent(title: title, summary: summary, details: details)
    }

    nonisolated var localizedTitle: String { localizedContent.title }
    nonisolated var localizedSummary: String { localizedContent.summary }
    nonisolated var localizedDetails: String { localizedContent.details }

    nonisolated func nextOccurrence(relativeTo date: Date = Date()) -> EventOccurrence? {
        occurrences.first { $0.status == .scheduled && $0.endDate >= date }
    }

    nonisolated func accepts(age: Int) -> Bool {
        guard age >= 0 else { return false }
        if let minimumAge, age < minimumAge { return false }
        if let maximumAge, age > maximumAge { return false }
        return true
    }

    nonisolated private static func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.compactMap { tag in
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return trimmed
        }
    }

    nonisolated private static func trimmedOptional(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == true ? nil : trimmed
    }
}

enum OrganizationProfileKind: String, Codable, CaseIterable, Identifiable {
    case community
    case business
    case restaurant
    case specialist
    case institution
    case mediaProject

    var id: String { rawValue }
}

enum OrganizationServiceMode: String, Codable, CaseIterable, Identifiable {
    case inStore
    case pickup
    case delivery
    case online
    case onSite

    var id: String { rawValue }
}

struct OrganizationDirectoryProfile: Codable, Equatable {
    nonisolated static let maximumSecondaryCategoryCount = 2
    nonisolated static let maximumServiceCount = 8

    let profileKind: OrganizationProfileKind
    let secondaryCategories: [String]
    let serviceModes: [OrganizationServiceMode]
    let serviceArea: String?
    /// ISO weekday keys (`monday` ... `sunday`) with `HH:mm-HH:mm` or `closed` values.
    let regularHours: [String: String]
    let specialHoursNote: String?
    let services: [String]
    let orderURL: String?
    let bookingURL: String?
    let currentOfferTitle: String?
    let currentOfferDetails: String?
    let currentOfferURL: String?
    let currentOfferValidUntil: Date?

    nonisolated init(
        profileKind: OrganizationProfileKind = .community,
        secondaryCategories: [String] = [],
        serviceModes: [OrganizationServiceMode] = [],
        serviceArea: String? = nil,
        regularHours: [String: String] = [:],
        specialHoursNote: String? = nil,
        services: [String] = [],
        orderURL: String? = nil,
        bookingURL: String? = nil,
        currentOfferTitle: String? = nil,
        currentOfferDetails: String? = nil,
        currentOfferURL: String? = nil,
        currentOfferValidUntil: Date? = nil
    ) {
        self.profileKind = profileKind
        self.secondaryCategories = Array(secondaryCategories.prefix(Self.maximumSecondaryCategoryCount))
        self.serviceModes = Self.unique(serviceModes)
        self.serviceArea = Self.normalized(serviceArea)
        self.regularHours = regularHours.filter { !$0.key.isEmpty && !$0.value.isEmpty }
        self.specialHoursNote = Self.normalized(specialHoursNote)
        self.services = Array(Self.unique(services.compactMap(Self.normalized)).prefix(Self.maximumServiceCount))
        self.orderURL = Self.normalized(orderURL)
        self.bookingURL = Self.normalized(bookingURL)
        self.currentOfferTitle = Self.normalized(currentOfferTitle)
        self.currentOfferDetails = Self.normalized(currentOfferDetails)
        self.currentOfferURL = Self.normalized(currentOfferURL)
        self.currentOfferValidUntil = currentOfferValidUntil
    }

    nonisolated private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated private static func unique<Value: Hashable>(_ values: [Value]) -> [Value] {
        var seen = Set<Value>()
        return values.filter { seen.insert($0).inserted }
    }
}

struct Organization: Identifiable, Codable {
    var accessRevision: String? = nil
    let id: String
    let localizations: [String: OrganizationLocalizedContent]
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
    let directoryProfile: OrganizationDirectoryProfile?
    let foundedYear: Int?
    let foundedMonth: Int?
    let languages: [String]
    let socialLinks: [String: String]
    let telegramURL: String?
    let donationURL: String?
    let facebookURL: String?
    let instagramURL: String?
    let whatsappURL: String?
    let youtubeURL: String?
    let linkedinURL: String?
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
        localizations: [String: OrganizationLocalizedContent] = [:],
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
        directoryProfile: OrganizationDirectoryProfile? = nil,
        foundedYear: Int? = nil,
        foundedMonth: Int? = nil,
        languages: [String] = [],
        socialLinks: [String: String] = [:],
        telegramURL: String? = nil,
        donationURL: String? = nil,
        facebookURL: String? = nil,
        instagramURL: String? = nil,
        whatsappURL: String? = nil,
        youtubeURL: String? = nil,
        linkedinURL: String? = nil,
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
        self.localizations = localizations
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
        self.directoryProfile = directoryProfile
        self.foundedYear = foundedYear
        self.foundedMonth = foundedMonth.flatMap { (1...12).contains($0) ? $0 : nil }
        self.languages = languages
        self.socialLinks = socialLinks
        self.telegramURL = Self.normalizedOptionalString(telegramURL)
        self.donationURL = Self.normalizedOptionalString(donationURL)
        self.facebookURL = Self.normalizedOptionalString(facebookURL)
        self.instagramURL = Self.normalizedOptionalString(instagramURL)
        self.whatsappURL = Self.normalizedOptionalString(whatsappURL)
        self.youtubeURL = Self.normalizedOptionalString(youtubeURL)
        self.linkedinURL = Self.normalizedOptionalString(linkedinURL)
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

    nonisolated var localizedContent: OrganizationLocalizedContent {
        localizations.resolved(for: LocalizationStore.language)
            ?? OrganizationLocalizedContent(
                name: name,
                shortDescription: shortDescription,
                fullDescription: fullDescription,
                missionStatement: missionStatement,
                serviceArea: directoryProfile?.serviceArea,
                specialHoursNote: directoryProfile?.specialHoursNote,
                services: directoryProfile?.services ?? [],
                currentOfferTitle: directoryProfile?.currentOfferTitle,
                currentOfferDetails: directoryProfile?.currentOfferDetails
            )
    }

    nonisolated var localizedName: String { localizedContent.name }
    nonisolated var localizedShortDescription: String { localizedContent.shortDescription }
    nonisolated var localizedFullDescription: String { localizedContent.fullDescription }
    nonisolated var localizedMissionStatement: String? { localizedContent.missionStatement }

    nonisolated var localizedDirectoryProfile: OrganizationDirectoryProfile? {
        guard let profile = directoryProfile else { return nil }
        let content = localizedContent
        return OrganizationDirectoryProfile(
            profileKind: profile.profileKind,
            secondaryCategories: profile.secondaryCategories,
            serviceModes: profile.serviceModes,
            serviceArea: content.serviceArea,
            regularHours: profile.regularHours,
            specialHoursNote: content.specialHoursNote,
            services: content.services,
            orderURL: profile.orderURL,
            bookingURL: profile.bookingURL,
            currentOfferTitle: content.currentOfferTitle,
            currentOfferDetails: content.currentOfferDetails,
            currentOfferURL: profile.currentOfferURL,
            currentOfferValidUntil: profile.currentOfferValidUntil
        )
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
    /// Present for Firestore pages; Date-only callers retain their existing behavior.
    let exactTimestamp: PageCursorTimestamp?

    init(followedAt: Date, documentID: String, exactTimestamp: PageCursorTimestamp? = nil) {
        self.followedAt = followedAt
        self.documentID = documentID
        self.exactTimestamp = exactTimestamp
    }
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

enum HomeFeedSourceType: String, Codable {
    case app
    case organization
}

enum HomeFeedItemType: String, Codable {
    case news
    case event
    case organization
}

enum HomeFeedDestinationReference: Hashable {
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
        title = post.localizedTitle
        summary = post.localizedSubtitle
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
        title = event.localizedTitle
        summary = event.localizedSummary
        imageURL = event.imageURL
        publishedAt = event.createdAt
        regionScope = event.regionScope
        federalState = event.federalState
        city = event.city
        let occurrence = event.nextOccurrence() ?? event.occurrences.first
        eventStartDate = occurrence?.startDate ?? event.startDate
        eventEndDate = occurrence?.endDate ?? event.endDate
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
        title = organization.localizedName
        summary = organization.localizedShortDescription
        imageURL = organization.imageURL
        publishedAt = organization.createdAt
        regionScope = organization.regionScope
        federalState = organization.federalState
        city = organization.city
        eventStartDate = nil
        eventEndDate = nil
        eventVenue = nil
        organizationId = organization.id
        organizationName = organization.localizedName
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
    let eventCategory: EventCategory?
    let eventAudience: EventAudience?
    let eventMinimumAge: Int?
    let eventMaximumAge: Int?
    let isBookmarked: Bool
    let organizationId: String
    let organizationName: String
    let destination: HomeFeedDestinationReference?

    init(profile organization: Organization) {
        id = "organization-profile-\(organization.id)"
        itemType = .organizationProfile
        title = organization.localizedName
        summary = organization.localizedShortDescription
        imageURL = organization.imageURL
        publishedAt = organization.updatedAt
        city = organization.city
        eventStartDate = nil
        eventVenue = nil
        eventRegistrationState = nil
        eventCategory = nil
        eventAudience = nil
        eventMinimumAge = nil
        eventMaximumAge = nil
        isBookmarked = false
        organizationId = organization.id
        organizationName = organization.localizedName
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
        eventCategory = nil
        eventAudience = nil
        eventMinimumAge = nil
        eventMaximumAge = nil
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
        eventCategory = event.category
        eventAudience = event.audience
        eventMinimumAge = event.minimumAge
        eventMaximumAge = event.maximumAge
        isBookmarked = event.isBookmarked
        organizationId = event.source.displayOrganizationId ?? ""
        organizationName = event.source.displayOrganizationName ?? ""
        destination = .event(id: event.id)
    }
}
