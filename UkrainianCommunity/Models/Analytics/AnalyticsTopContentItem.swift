import Foundation

enum AnalyticsContentType: String, CaseIterable, Codable, Identifiable {
    case news
    case event
    case organization
    case guideArticle

    var id: String { rawValue }
}

struct AnalyticsTopContentItem: Codable, Equatable, Identifiable {
    let contentID: String
    let contentType: AnalyticsContentType
    let title: String
    let category: String?
    let organizationID: String?
    let organizationName: String?
    let regionScope: RegionScope?
    let federalState: AustrianFederalState?
    let viewCount: Int
    let rank: Int

    var id: String { "\(contentType.rawValue):\(contentID)" }

    init(
        contentID: String,
        contentType: AnalyticsContentType,
        title: String,
        category: String?,
        organizationID: String? = nil,
        organizationName: String? = nil,
        regionScope: RegionScope? = nil,
        federalState: AustrianFederalState? = nil,
        viewCount: Int,
        rank: Int
    ) {
        self.contentID = contentID
        self.contentType = contentType
        self.title = title
        self.category = category
        self.organizationID = organizationID
        self.organizationName = organizationName
        self.regionScope = regionScope
        self.federalState = federalState
        self.viewCount = viewCount
        self.rank = rank
    }
}
