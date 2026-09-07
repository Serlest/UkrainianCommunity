import FirebaseFirestore

/// Read dependencies are separate from the privileged mutation service.
@MainActor
struct UserManagementReads {
    struct Page {
        let users: [AppUser]
        let cursor: QueryDocumentSnapshot?
        let hasMore: Bool
    }

    struct SearchResult {
        let users: [AppUser]
        let totalMatches: Int
    }

    var users: (Int) async throws -> Page
    var user: (String) async throws -> AppUser?
    var organizations: () async throws -> [ManagedOrganization]
    var securityMetadata: (String) async throws -> ManagedUserSecurityMetadata
    var presence: (String) async throws -> ManagedUserPresenceSnapshot = UserPresenceAPI.load

    var search: (String) async throws -> SearchResult = liveSearch

    private static func liveSearch(_ query: String) async throws -> SearchResult {
        let response = try await CloudFunctionsClient.shared.searchManagedUsers(query: query)
        var usersByID: [String: AppUser] = [:]
        for ids in response.userIds.chunked(into: 30) where !ids.isEmpty {
            try Task.checkCancellation()
            let snapshot = try await Firestore.firestore().collection("users")
                .whereField(FieldPath.documentID(), in: Array(ids)).getDocuments(source: .server)
            for document in snapshot.documents {
                usersByID[document.documentID] = UserManagementViewModel.makeUser(from: document)
            }
        }
        return SearchResult(users: response.userIds.compactMap { usersByID[$0] }, totalMatches: response.totalMatches)
    }

    static let live = UserManagementReads(
        users: { limit in
            let snapshot = try await Firestore.firestore().collection("users")
                .order(by: "createdAt", descending: true).limit(to: limit).getDocuments(source: .server)
            return Page(users: snapshot.documents.map(UserManagementViewModel.makeUser(from:)),
                        cursor: snapshot.documents.last, hasMore: snapshot.documents.count == limit)
        },
        user: { id in
            let document = try await Firestore.firestore().collection("users").document(id).getDocument(source: .server)
            guard document.exists, let data = document.data() else { return nil }
            return UserManagementViewModel.makeUser(id: document.documentID, data: data)
        },
        organizations: {
            let collection = Firestore.firestore().collection("organizations")
            async let approved = collection.whereField("moderationStatus", isEqualTo: ModerationStatus.approved.rawValue)
                .getDocuments(source: .server)
            async let reviewable = collection.whereField("moderationStatus", in: [
                ModerationStatus.pendingReview.rawValue, ModerationStatus.needsRevision.rawValue,
                ModerationStatus.rejected.rawValue
            ]).getDocuments(source: .server)
            let snapshots = try await (approved, reviewable)
            return UserManagementViewModel.uniqueOrganizationDocuments(snapshots.0.documents + snapshots.1.documents)
                .map(UserManagementViewModel.makeManagedOrganization(from:))
                .sorted {
                    let result = LocalizationStore.compareForSorting($0.name, $1.name)
                    return result == .orderedSame ? $0.id < $1.id : result == .orderedAscending
                }
        },
        securityMetadata: { id in
            let response = try await CloudFunctionsClient.shared.getManagedUserSecurityMetadata(userId: id)
            guard response.targetUserId == id else { throw AppError.permissionDenied }
            return ManagedUserSecurityMetadata(response: response)
        }
    )
}
