import Foundation
import FirebaseAuth
import FirebaseFirestore

struct FirestoreGuideRepository: GuideRepositoryProtocol {
    static let rootParentID = "root"

    private let database: Firestore

    init(database: Firestore = Firestore.firestore()) {
        self.database = database
    }

    func fetchRootNodes(
        category: GuideCategory,
        selectedFederalState: AustrianFederalState?
    ) async throws -> [GuideNode] {
        do {
            let rootQuery = guideNodesCollection
                .whereField("category", isEqualTo: category.rawValue)
                .whereField("parentID", isEqualTo: Self.rootParentID)
            let documents = try await regionScopedNodeDocuments(
                for: rootQuery,
                selectedFederalState: selectedFederalState
            )
            return sortNodes(documents.compactMap(makeGuideNode))
        } catch {
            await logGuidePermissionFailure(
                error,
                operationName: "fetchRootNodes",
                collectionName: "guideNodes",
                metadata: ["category": category.rawValue]
            )
            throw mapFirestoreError(error)
        }
    }

    func fetchChildNodes(
        parentId: String,
        selectedFederalState: AustrianFederalState?
    ) async throws -> [GuideNode] {
        do {
            let childQuery = guideNodesCollection
                .whereField("parentID", isEqualTo: parentId)
            let documents = try await regionScopedNodeDocuments(
                for: childQuery,
                selectedFederalState: selectedFederalState
            )
            return sortNodes(documents.compactMap(makeGuideNode))
        } catch {
            await logGuidePermissionFailure(
                error,
                operationName: "fetchChildNodes",
                collectionName: "guideNodes"
            )
            throw mapFirestoreError(error)
        }
    }

    func fetchMaterials(
        nodeId: String,
        selectedFederalState: AustrianFederalState?
    ) async throws -> [GuideMaterial] {
        do {
            let materialsQuery = guideMaterialsCollection
                .whereField("nodeID", isEqualTo: nodeId)
            let documents = try await regionScopedMaterialDocuments(
                for: materialsQuery,
                selectedFederalState: selectedFederalState
            )
            return sortMaterials(documents.compactMap(makeGuideMaterial))
        } catch {
            await logGuidePermissionFailure(
                error,
                operationName: "fetchMaterials",
                collectionName: "guideMaterials",
                targetType: .guideMaterial
            )
            throw mapFirestoreError(error)
        }
    }

    func fetchAllNodesForSearch(
        selectedFederalState: AustrianFederalState?
    ) async throws -> [GuideNode] {
        do {
            let documents = try await regionScopedNodeDocuments(
                for: guideNodesCollection,
                selectedFederalState: selectedFederalState
            )
            return sortNodes(documents.compactMap(makeGuideNode))
        } catch {
            await logGuidePermissionFailure(
                error,
                operationName: "fetchAllNodesForSearch",
                collectionName: "guideNodes"
            )
            throw mapFirestoreError(error)
        }
    }

    func fetchAllMaterialsForSearch(
        selectedFederalState: AustrianFederalState?
    ) async throws -> [GuideMaterial] {
        do {
            let documents = try await regionScopedMaterialDocuments(
                for: guideMaterialsCollection,
                selectedFederalState: selectedFederalState
            )
            return sortMaterials(documents.compactMap(makeGuideMaterial))
        } catch {
            await logGuidePermissionFailure(
                error,
                operationName: "fetchAllMaterialsForSearch",
                collectionName: "guideMaterials",
                targetType: .guideMaterial
            )
            throw mapFirestoreError(error)
        }
    }

    func fetchMaterialsNeedingReview() async throws -> [GuideMaterial] {
        do {
            let snapshot = try await guideMaterialsCollection
                .whereField("archivedAt", isEqualTo: NSNull())
                .getDocuments()

            return sortMaterials(snapshot.documents.compactMap(makeGuideMaterial))
                .filter { material in
                    let status = material.healthStatus
                    return status == .dueSoon || status == .overdue
                }
        } catch {
            await logGuidePermissionFailure(
                error,
                operationName: "fetchMaterialsNeedingReview",
                collectionName: "guideMaterials",
                targetType: .guideMaterial
            )
            throw mapFirestoreError(error)
        }
    }

    func fetchSavedMaterialIDs() async throws -> [String] {
        guard let uid = Auth.auth().currentUser?.uid else {
            return []
        }

        do {
            let snapshot = try await guideMaterialBookmarksCollection(userID: uid)
                .order(by: "createdAt", descending: true)
                .getDocuments()

            return snapshot.documents.compactMap { document in
                document.data()["materialId"] as? String
            }
        } catch {
            await logGuidePermissionFailure(
                error,
                operationName: "fetchSavedMaterialIDs",
                collectionName: "guideMaterialBookmarks",
                targetType: .guideMaterial
            )
            throw mapFirestoreError(error)
        }
    }

    func bookmarkMaterial(id: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AppError.permissionDenied
        }

        do {
            try await guideMaterialBookmarkReference(materialID: id, userID: uid).setData([
                "id": id,
                "materialId": id,
                "userId": uid,
                "createdAt": FieldValue.serverTimestamp()
            ], merge: true)
        } catch {
            await logGuidePermissionFailure(
                error,
                operationName: "bookmarkMaterial",
                collectionName: "guideMaterialBookmarks",
                targetType: .guideMaterial
            )
            throw mapFirestoreError(error)
        }
    }

    func unbookmarkMaterial(id: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AppError.permissionDenied
        }

        do {
            try await guideMaterialBookmarkReference(materialID: id, userID: uid).delete()
        } catch {
            await logGuidePermissionFailure(
                error,
                operationName: "unbookmarkMaterial",
                collectionName: "guideMaterialBookmarks",
                targetType: .guideMaterial
            )
            throw mapFirestoreError(error)
        }
    }

    func fetchMaterial(id: String) async throws -> GuideMaterial {
        do {
            let document = try await guideMaterialsCollection.document(id).getDocument()

            guard document.exists, document.data() != nil else {
                try? await removeCurrentUserBookmark(for: id)
                throw AppError.notFound
            }

            guard let material = makeGuideMaterial(from: document) else {
                throw AppError.validationFailed
            }

            guard material.isPublished else {
                throw AppError.notFound
            }

            return material
        } catch let error as AppError {
            throw error
        } catch {
            await logGuidePermissionFailure(
                error,
                operationName: "fetchMaterial",
                collectionName: "guideMaterials",
                targetType: .guideMaterial
            )
            throw mapFirestoreError(error)
        }
    }

    private func removeCurrentUserBookmark(for materialID: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try await guideMaterialBookmarkReference(materialID: materialID, userID: uid).delete()
    }

    private func logGuidePermissionFailure(
        _ error: Error,
        operationName: String,
        collectionName: String,
        targetType: SystemLogTargetType = .diagnosticSnapshot,
        metadata: [String: String] = [:]
    ) async {
        let nsError = error as NSError
        guard nsError.domain == FirestoreErrorDomain,
              FirestoreErrorCode.Code(rawValue: nsError.code) == .permissionDenied else {
            return
        }

        var metadata = metadata
        metadata["collection"] = collectionName

        await SystemTechnicalErrorLoggingService.shared.logFailure(
            error,
            context: SystemTechnicalErrorContext(
                moduleName: "Guide",
                operationName: operationName,
                screenName: "Guide",
                targetType: targetType,
                metadata: metadata
            )
        )
    }
}

extension FirestoreGuideRepository {
    func regionScopedNodeDocuments(
        for baseQuery: Query,
        selectedFederalState: AustrianFederalState?
    ) async throws -> [QueryDocumentSnapshot] {
        if let selectedFederalState {
            async let austriaSnapshot = publishedAustriaScopedNodesQuery(baseQuery).getDocuments()
            async let regionalSnapshot = publishedFederalStateScopedNodesQuery(
                baseQuery,
                federalState: selectedFederalState
            ).getDocuments()

            let (resolvedAustriaSnapshot, resolvedRegionalSnapshot) = try await (
                austriaSnapshot,
                regionalSnapshot
            )
            return mergeRegionScopedDocuments(
                from: [resolvedAustriaSnapshot, resolvedRegionalSnapshot]
            )
        }

        let snapshot = try await publishedGuideNodesQuery(baseQuery).getDocuments()
        return snapshot.documents
    }

    func regionScopedMaterialDocuments(
        for baseQuery: Query,
        selectedFederalState: AustrianFederalState?
    ) async throws -> [QueryDocumentSnapshot] {
        if let selectedFederalState {
            async let austriaSnapshot = publishedAustriaScopedMaterialsQuery(baseQuery).getDocuments()
            async let regionalSnapshot = publishedFederalStateScopedMaterialsQuery(
                baseQuery,
                federalState: selectedFederalState
            ).getDocuments()

            let (resolvedAustriaSnapshot, resolvedRegionalSnapshot) = try await (
                austriaSnapshot,
                regionalSnapshot
            )
            return mergeRegionScopedDocuments(
                from: [resolvedAustriaSnapshot, resolvedRegionalSnapshot]
            )
        }

        let snapshot = try await publishedGuideMaterialsQuery(baseQuery).getDocuments()
        return snapshot.documents
    }

    func mergeRegionScopedDocuments(
        from snapshots: [QuerySnapshot]
    ) -> [QueryDocumentSnapshot] {
        var documentsByID: [String: QueryDocumentSnapshot] = [:]

        for snapshot in snapshots {
            for document in snapshot.documents {
                documentsByID[document.documentID] = document
            }
        }

        return Array(documentsByID.values)
    }

    func sortNodes(_ nodes: [GuideNode]) -> [GuideNode] {
        nodes.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }

            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    func sortMaterials(_ materials: [GuideMaterial]) -> [GuideMaterial] {
        materials.sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }

            if lhs.title != rhs.title {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }

            return lhs.updatedAt > rhs.updatedAt
        }
    }

    var guideNodesCollection: CollectionReference {
        database.collection("guideNodes")
    }

    var guideMaterialsCollection: CollectionReference {
        database.collection("guideMaterials")
    }

    func guideMaterialBookmarksCollection(userID: String) -> CollectionReference {
        database.collection("users")
            .document(userID)
            .collection("guideMaterialBookmarks")
    }

    func guideMaterialBookmarkReference(materialID: String, userID: String) -> DocumentReference {
        guideMaterialBookmarksCollection(userID: userID)
            .document(materialID)
    }
}
