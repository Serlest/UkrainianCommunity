import Foundation

enum SystemLogRetentionPolicy: String, Codable, CaseIterable, Identifiable {
    case normalAudit
    case technicalError
    case security
    case moderationDispute

    var id: String { rawValue }

    var defaultRetentionDays: Int {
        switch self {
        case .normalAudit:
            365
        case .technicalError:
            90
        case .security:
            730
        case .moderationDispute:
            1_095
        }
    }
}
