import Foundation

enum SystemLogTargetType: String, Codable, CaseIterable, Hashable {
    case account
    case userProfile
    case newsPost
    case event
    case organization
    case organizationRequest
    case guideArticle
    case guideMaterial
    case feedback
    case report
    case notification
    case donationConfig
    case legalDocument
    case systemConfiguration
    case diagnosticSnapshot
    case none
    case unknown
}
