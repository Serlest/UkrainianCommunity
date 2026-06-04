import Foundation
import FirebaseFirestore

extension FirestoreGuideRepository {
    func publishedGuideNodesQuery(_ query: Query) -> Query {
        query
            .whereField("moderationStatus", isEqualTo: ModerationStatus.approved.rawValue)
            .whereField("publishedAt", isGreaterThan: minimumPublishedTimestamp())
            .whereField("archivedAt", isEqualTo: NSNull())
    }

    func publishedGuideMaterialsQuery(_ query: Query) -> Query {
        query
            .whereField("moderationStatus", isEqualTo: ModerationStatus.approved.rawValue)
            .whereField("publishedAt", isGreaterThan: minimumPublishedTimestamp())
            .whereField("archivedAt", isEqualTo: NSNull())
    }

    func minimumPublishedTimestamp() -> Timestamp {
        Timestamp(date: Date(timeIntervalSince1970: 0))
    }

    func publishedAustriaScopedNodesQuery(_ query: Query) -> Query {
        publishedGuideNodesQuery(query)
            .whereField("regionScope", isEqualTo: RegionScope.austria.rawValue)
    }

    func publishedFederalStateScopedNodesQuery(
        _ query: Query,
        federalState: AustrianFederalState
    ) -> Query {
        publishedGuideNodesQuery(query)
            .whereField("regionScope", isEqualTo: RegionScope.federalState.rawValue)
            .whereField("federalState", isEqualTo: federalState.rawValue)
    }

    func publishedAustriaScopedMaterialsQuery(_ query: Query) -> Query {
        publishedGuideMaterialsQuery(query)
            .whereField("regionScope", isEqualTo: RegionScope.austria.rawValue)
    }

    func publishedFederalStateScopedMaterialsQuery(
        _ query: Query,
        federalState: AustrianFederalState
    ) -> Query {
        publishedGuideMaterialsQuery(query)
            .whereField("regionScope", isEqualTo: RegionScope.federalState.rawValue)
            .whereField("federalState", isEqualTo: federalState.rawValue)
    }

    func mapFirestoreError(_ error: Error) -> AppError {
        let nsError = error as NSError

        guard let code = FirestoreErrorCode.Code(rawValue: nsError.code) else {
            return .unknown
        }

        switch code {
        case .permissionDenied:
            return .permissionDenied
        case .notFound:
            return .notFound
        case .unavailable, .deadlineExceeded:
            return .network
        default:
            return .unknown
        }
    }
}
