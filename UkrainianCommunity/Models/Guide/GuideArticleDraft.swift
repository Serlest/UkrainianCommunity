import Foundation

struct GuideArticleDraft: Equatable {
    var title: String
    var summary: String
    var body: String
    var category: GuideCategory?
    var contentType: GuideContentType
    var federalState: AustrianFederalState?
    var audience: [String]
    var sourceLinks: [GuideSourceLink]
    var reviewInterval: ReviewInterval
    var priority: Int
    var isFeatured: Bool
    var contentBlocks: [GuideContentBlock]
    var officialSourcesRequired: Bool

    nonisolated init(
        title: String = "",
        summary: String = "",
        body: String = "",
        category: GuideCategory? = nil,
        contentType: GuideContentType = .guide,
        federalState: AustrianFederalState? = nil,
        audience: [String] = [],
        sourceLinks: [GuideSourceLink] = [],
        reviewInterval: ReviewInterval = .normal,
        priority: Int = 0,
        isFeatured: Bool = false,
        contentBlocks: [GuideContentBlock] = [],
        officialSourcesRequired: Bool = false
    ) {
        self.title = title
        self.summary = summary
        self.body = body
        self.category = category
        self.contentType = contentType
        self.federalState = federalState
        self.audience = audience
        self.sourceLinks = sourceLinks
        self.reviewInterval = reviewInterval
        self.priority = priority
        self.isFeatured = isFeatured
        self.contentBlocks = contentBlocks
        self.officialSourcesRequired = officialSourcesRequired
    }

    nonisolated init(article: GuideArticle) {
        self.init(
            title: article.title,
            summary: article.summary,
            body: article.body,
            category: article.category,
            contentType: article.contentType ?? .guide,
            federalState: article.federalState,
            audience: article.audience ?? [],
            sourceLinks: article.sourceLinks ?? [],
            reviewInterval: article.reviewInterval ?? .normal,
            priority: article.priority ?? 0,
            isFeatured: article.isFeatured ?? false,
            contentBlocks: article.contentBlocks ?? [],
            officialSourcesRequired: article.officialSourcesRequired ?? false
        )
    }
}
