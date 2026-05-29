import Foundation

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
    let contentType: GuideContentType?
    let status: GuideStatus?
    let contentBlocks: [GuideContentBlock]?
    let audience: [String]?
    let sourceLinks: [GuideSourceLink]?
    let officialSourcesRequired: Bool?
    let priority: Int?
    let isFeatured: Bool?
    let createdBy: String?
    let updatedBy: String?
    let reviewedBy: String?
    let publishedAt: Date?
    let lastReviewedAt: Date?
    let nextReviewAt: Date?
    let reviewInterval: ReviewInterval?
    let archivedAt: Date?

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
        updatedAt: Date,
        contentType: GuideContentType? = nil,
        status: GuideStatus? = nil,
        contentBlocks: [GuideContentBlock]? = nil,
        audience: [String]? = nil,
        sourceLinks: [GuideSourceLink]? = nil,
        officialSourcesRequired: Bool? = nil,
        priority: Int? = nil,
        isFeatured: Bool? = nil,
        createdBy: String? = nil,
        updatedBy: String? = nil,
        reviewedBy: String? = nil,
        publishedAt: Date? = nil,
        lastReviewedAt: Date? = nil,
        nextReviewAt: Date? = nil,
        reviewInterval: ReviewInterval? = nil,
        archivedAt: Date? = nil
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
        self.contentType = contentType
        self.status = status
        self.contentBlocks = contentBlocks
        self.audience = audience
        self.sourceLinks = sourceLinks
        self.officialSourcesRequired = officialSourcesRequired
        self.priority = priority
        self.isFeatured = isFeatured
        self.createdBy = createdBy
        self.updatedBy = updatedBy
        self.reviewedBy = reviewedBy
        self.publishedAt = publishedAt
        self.lastReviewedAt = lastReviewedAt
        self.nextReviewAt = nextReviewAt
        self.reviewInterval = reviewInterval
        self.archivedAt = archivedAt
    }
}
