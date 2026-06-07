import Foundation

enum SystemLogFirestoreContract {
    static let collectionPath = "systemLogs"

    enum Field: String, CaseIterable {
        case id
        case createdAt
        case category
        case severity
        case severityRank
        case eventType
        case actorUserId
        case actorDisplayName
        case actorRole
        case targetType
        case targetId
        case targetTitle
        case organizationId
        case organizationName
        case outcome
        case summary
        case technicalMessage
        case errorCode
        case moduleName
        case screenName
        case operationName
        case appVersion
        case osVersion
        case deviceModel
        case isReviewed
        case reviewedAt
        case reviewedByUserId
        case metadata
        case retentionPolicy
        case correlationId
    }
}

extension SystemLogFirestoreContract {
    enum AccessNote {
        static let clientCreation = "Client-created logs are restricted to diagnostics plus constrained owner/admin content-write audit creates."
        static let search = "Full-text search is not supported; searchText remains client-side or future search-token work."
    }

    enum RequiredIndex {
        static let notes = [
            "category + createdAt desc",
            "severity + createdAt desc",
            "eventType + createdAt desc",
            "actorRole + createdAt desc",
            "organizationId + createdAt desc",
            "isReviewed + createdAt desc",
            "outcome + createdAt desc",
            "severityRank + createdAt desc for critical-first sorting"
        ]
    }
}
