import Foundation

struct GuideArticleDTO: Codable, Identifiable {
    let id: String
    let title: String
    let summary: String
    let body: String
    let category: String
    let regionScope: String?
    let federalState: String?
    let city: String?
    let officialSourceURL: String?
    let sourceName: String?
    let isPinned: Bool
    let moderationStatus: String
    let createdAt: Date
    let updatedAt: Date
    let contentType: String?
    let status: String?
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
    let reviewInterval: String?
    let archivedAt: Date?
}

extension GuideArticle {
    init?(dto: GuideArticleDTO) {
        guard let category = GuideCategory(rawValue: dto.category),
              let moderationStatus = ModerationStatus(rawValue: dto.moderationStatus) else {
            return nil
        }

        self.init(
            id: dto.id,
            title: dto.title,
            summary: dto.summary,
            body: dto.body,
            category: category,
            regionScope: dto.regionScope.flatMap(RegionScope.init(rawValue:)) ?? .austria,
            federalState: dto.federalState.flatMap(AustrianFederalState.init(rawValue:)),
            city: dto.city,
            officialSourceURL: dto.officialSourceURL,
            sourceName: dto.sourceName,
            isPinned: dto.isPinned,
            moderationStatus: moderationStatus,
            createdAt: dto.createdAt,
            updatedAt: dto.updatedAt,
            contentType: dto.contentType.flatMap(GuideContentType.init(rawValue:)),
            status: dto.status.flatMap(GuideStatus.init(rawValue:)),
            contentBlocks: dto.contentBlocks,
            audience: dto.audience,
            sourceLinks: dto.sourceLinks,
            officialSourcesRequired: dto.officialSourcesRequired,
            priority: dto.priority,
            isFeatured: dto.isFeatured,
            createdBy: dto.createdBy,
            updatedBy: dto.updatedBy,
            reviewedBy: dto.reviewedBy,
            publishedAt: dto.publishedAt,
            lastReviewedAt: dto.lastReviewedAt,
            nextReviewAt: dto.nextReviewAt,
            reviewInterval: dto.reviewInterval.flatMap(ReviewInterval.init(rawValue:)),
            archivedAt: dto.archivedAt
        )
    }

    var dto: GuideArticleDTO {
        GuideArticleDTO(
            id: id,
            title: title,
            summary: summary,
            body: body,
            category: category.rawValue,
            regionScope: regionScope?.rawValue,
            federalState: federalState?.rawValue,
            city: city,
            officialSourceURL: officialSourceURL,
            sourceName: sourceName,
            isPinned: isPinned,
            moderationStatus: moderationStatus.rawValue,
            createdAt: createdAt,
            updatedAt: updatedAt,
            contentType: contentType?.rawValue,
            status: status?.rawValue,
            contentBlocks: contentBlocks,
            audience: audience,
            sourceLinks: sourceLinks,
            officialSourcesRequired: officialSourcesRequired,
            priority: priority,
            isFeatured: isFeatured,
            createdBy: createdBy,
            updatedBy: updatedBy,
            reviewedBy: reviewedBy,
            publishedAt: publishedAt,
            lastReviewedAt: lastReviewedAt,
            nextReviewAt: nextReviewAt,
            reviewInterval: reviewInterval?.rawValue,
            archivedAt: archivedAt
        )
    }
}
