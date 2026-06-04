import Foundation

struct GuideMaterial: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let summary: String
    let body: String
    let sortOrder: Int
    let contentBlocks: [GuideContentBlock]
    let sourceLinks: [GuideSourceLink]
    let officialSourceURL: String?
    let sourceName: String?
    let officialSourcesRequired: Bool
    let kind: GuideMaterialKind
    let category: GuideCategory
    let nodeID: String
    let nodePath: GuideTreePath
    let regionScope: RegionScope?
    let federalState: AustrianFederalState?
    let reviewInterval: ReviewInterval
    let lastReviewedAt: Date?
    let nextReviewAt: Date?
    let reviewedBy: String?
    let moderationStatus: ModerationStatus
    let publishedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let createdBy: String?
    let updatedBy: String?
    let archivedAt: Date?

    init(
        id: String,
        title: String,
        summary: String,
        body: String,
        sortOrder: Int = 0,
        contentBlocks: [GuideContentBlock] = [],
        sourceLinks: [GuideSourceLink] = [],
        officialSourceURL: String? = nil,
        sourceName: String? = nil,
        officialSourcesRequired: Bool = false,
        kind: GuideMaterialKind = .page,
        category: GuideCategory,
        nodeID: String,
        nodePath: GuideTreePath,
        regionScope: RegionScope? = .austria,
        federalState: AustrianFederalState? = nil,
        reviewInterval: ReviewInterval = .normal,
        lastReviewedAt: Date? = nil,
        nextReviewAt: Date? = nil,
        reviewedBy: String? = nil,
        moderationStatus: ModerationStatus = .approved,
        publishedAt: Date? = nil,
        createdAt: Date,
        updatedAt: Date,
        createdBy: String? = nil,
        updatedBy: String? = nil,
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.body = body
        self.sortOrder = sortOrder
        self.contentBlocks = contentBlocks
        self.sourceLinks = sourceLinks
        self.officialSourceURL = officialSourceURL
        self.sourceName = sourceName
        self.officialSourcesRequired = officialSourcesRequired
        self.kind = kind
        self.category = category
        self.nodeID = nodeID
        self.nodePath = nodePath
        self.regionScope = regionScope
        self.federalState = federalState
        self.reviewInterval = reviewInterval
        self.lastReviewedAt = lastReviewedAt
        self.nextReviewAt = nextReviewAt
        self.reviewedBy = reviewedBy
        self.moderationStatus = moderationStatus
        self.publishedAt = publishedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.createdBy = createdBy
        self.updatedBy = updatedBy
        self.archivedAt = archivedAt
    }

    var isPublished: Bool {
        moderationStatus == .approved && publishedAt != nil && archivedAt == nil
    }

    var healthStatus: GuideHealthStatus {
        guard archivedAt == nil else { return .archived }
        guard let nextReviewAt else { return .current }

        let now = Date()
        if nextReviewAt < now {
            return .overdue
        }

        let dueSoonCutoff = Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now
        if nextReviewAt <= dueSoonCutoff {
            return .dueSoon
        }

        return .current
    }
}
