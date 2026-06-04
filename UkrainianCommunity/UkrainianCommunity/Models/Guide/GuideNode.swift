import Foundation

struct GuideNode: Identifiable, Codable, Equatable {
    let id: String
    let parentID: String?
    let kind: GuideNodeKind
    let category: GuideCategory
    let title: String
    let summary: String
    let sortOrder: Int
    let regionScope: RegionScope?
    let federalState: AustrianFederalState?
    let healthStatus: GuideHealthStatus
    let moderationStatus: ModerationStatus
    let publishedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let createdBy: String?
    let updatedBy: String?
    let archivedAt: Date?

    init(
        id: String,
        parentID: String? = nil,
        kind: GuideNodeKind = .section,
        category: GuideCategory,
        title: String,
        summary: String,
        sortOrder: Int = 0,
        regionScope: RegionScope? = .austria,
        federalState: AustrianFederalState? = nil,
        healthStatus: GuideHealthStatus = .current,
        moderationStatus: ModerationStatus = .approved,
        publishedAt: Date? = nil,
        createdAt: Date,
        updatedAt: Date,
        createdBy: String? = nil,
        updatedBy: String? = nil,
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.parentID = parentID
        self.kind = kind
        self.category = category
        self.title = title
        self.summary = summary
        self.sortOrder = sortOrder
        self.regionScope = regionScope
        self.federalState = federalState
        self.healthStatus = healthStatus
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
}
