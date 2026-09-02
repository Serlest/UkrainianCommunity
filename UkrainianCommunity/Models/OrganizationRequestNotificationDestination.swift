import Foundation

enum OrganizationRequestNotificationDestination: Equatable {
    case review(organizationID: String?)
    case organization(organizationID: String)
    case management
    case unavailable

    static func resolve(
        type: AppNotificationType,
        organizationID: String?,
        canReviewRequests: Bool
    ) -> Self {
        let trimmedID = organizationID?.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetID = trimmedID.flatMap { $0.isEmpty ? nil : $0 }
        switch type {
        case .organizationRequestSubmitted:
            return canReviewRequests ? .review(organizationID: targetID) : .unavailable
        case .organizationRequestApproved:
            return targetID.map { .organization(organizationID: $0) } ?? .management
        default:
            // Revision/rejection notices belong to the applicant's management flow.
            return .management
        }
    }
}
