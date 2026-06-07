import Foundation

enum SystemLogEventType: String, Codable, CaseIterable, Hashable {
    case signedIn
    case signedOut
    case permissionDenied
    case roleAssigned
    case roleRemoved
    case accountBlocked
    case accountUnblocked
    case userWarned
    case userProfileUpdated
    case contentCreated
    case contentUpdated
    case contentDeleted
    case contentApproved
    case contentRejected
    case reportSubmitted
    case reportReviewed
    case organizationRequestSubmitted
    case organizationRequestApproved
    case organizationRequestRejected
    case configurationUpdated
    case notificationQueued
    case diagnosticSnapshotCreated
    case technicalError
    case dataValidationFailed
    case unknown
}
