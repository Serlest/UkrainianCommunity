import Foundation

enum LikeState: String, Codable {
    case liked
    case notLiked

    var isLiked: Bool { self == .liked }

    func toggled() -> LikeState {
        isLiked ? .notLiked : .liked
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

    init(
        id: String,
        title: String,
        subtitle: String,
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
    let city: String
    let venue: String
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
}

struct Organization: Identifiable, Codable {
    let id: String
    let name: String
    let summary: String
    let mission: String
    let city: String
    let website: String
    let contactEmail: String
    let createdAt: Date
    let updatedAt: Date
    let focusAreas: [String]
    let comments: [Comment]
    var moderationStatus: ModerationStatus
    var likeCount: Int
    var likeState: LikeState
}

enum MarketplaceContactMethod: String, Codable {
    case phone
    case email
    case telegram

    var title: String {
        switch self {
        case .phone:
            AppStrings.Marketplace.phone
        case .email:
            AppStrings.Marketplace.email
        case .telegram:
            AppStrings.Marketplace.telegram
        }
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

struct MarketplaceItem: Identifiable, Codable {
    let id: String
    let title: String
    let description: String
    let city: String
    let price: Decimal?
    let isFreeGift: Bool
    let expirationDate: Date
    let sellerName: String
    let createdAt: Date
    let updatedAt: Date
    let contactValue: String
    let contactMethod: MarketplaceContactMethod
    let comments: [Comment]
    var moderationStatus: ModerationStatus
    var likeCount: Int
    var likeState: LikeState
}

struct HomeHighlight: Identifiable {
    let id: String
    let title: String
    let detail: String
    let systemImage: String
}

struct InfoItem: Identifiable {
    let id: String
    let title: String
    let body: String
    let systemImage: String
}
