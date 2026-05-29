import Foundation

enum GuideReportType: String, Codable, CaseIterable, Identifiable {
    case incorrectInformation
    case outdatedLink
    case rulesChanged
    case missingInformation
    case other

    var id: String { rawValue }
}

struct GuideReport: Identifiable, Codable, Equatable {
    let id: String
    let articleId: String
    let type: GuideReportType
    let message: String
    let reportedByUserId: String?
    let reporterEmail: String?
    let createdAt: Date
    let resolvedAt: Date?
    let resolvedByUserId: String?

    nonisolated init(
        id: String,
        articleId: String,
        type: GuideReportType,
        message: String,
        reportedByUserId: String? = nil,
        reporterEmail: String? = nil,
        createdAt: Date,
        resolvedAt: Date? = nil,
        resolvedByUserId: String? = nil
    ) {
        self.id = id
        self.articleId = articleId
        self.type = type
        self.message = message
        self.reportedByUserId = reportedByUserId
        self.reporterEmail = reporterEmail
        self.createdAt = createdAt
        self.resolvedAt = resolvedAt
        self.resolvedByUserId = resolvedByUserId
    }
}
