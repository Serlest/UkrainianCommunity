import Foundation

enum SystemLogCategory: String, Codable, CaseIterable, Hashable {
    case authentication
    case authorization
    case audit
    case moderation
    case content
    case organization
    case userAccount
    case configuration
    case notification
    case dataIntegrity
    case diagnostics
    case unknown
}
