import Foundation
import FirebaseFirestore

struct FirestoreGuideWriteRepository: GuideWriteRepositoryProtocol {
    static let rootParentID = FirestoreGuideRepository.rootParentID

    private let database: Firestore

    init(database: Firestore = Firestore.firestore()) {
        self.database = database
    }

    func hasAnyChildNodes(parentId: String) async throws -> Bool {
        do {
            let snapshot = try await getDocuments(
                guideNodesCollection
                    .whereField("parentID", isEqualTo: parentId)
                    .limit(to: 1)
            )
            return !snapshot.documents.isEmpty
        } catch {
            throw mapFirestoreError(error)
        }
    }

    func hasAnyMaterials(nodeId: String) async throws -> Bool {
        do {
            let snapshot = try await getDocuments(
                guideMaterialsCollection
                    .whereField("nodeID", isEqualTo: nodeId)
                    .limit(to: 1)
            )
            return !snapshot.documents.isEmpty
        } catch {
            throw mapFirestoreError(error)
        }
    }

    func createRootNode(_ node: GuideNode) async throws -> GuideNode {
        let normalizedNode = normalizedRootNode(node)

        do {
            try await setData(
                makeGuideNodeCreateData(from: normalizedNode),
                for: guideNodesCollection.document(normalizedNode.id)
            )
            return normalizedNode
        } catch {
            throw mapFirestoreError(error)
        }
    }

    func createChildNode(_ node: GuideNode) async throws -> GuideNode {
        let normalizedNode = try normalizedChildNode(node)

        do {
            try await setData(
                makeGuideNodeCreateData(from: normalizedNode),
                for: guideNodesCollection.document(normalizedNode.id)
            )
            return normalizedNode
        } catch let error as AppError {
            throw error
        } catch {
            throw mapFirestoreError(error)
        }
    }

    func updateNode(_ node: GuideNode) async throws {
        do {
            try await updateData(
                makeGuideNodeUpdateData(from: node),
                for: guideNodesCollection.document(node.id)
            )
        } catch {
            throw mapFirestoreError(error)
        }
    }

    func updateNodeSortOrders(_ updates: [GuideSortOrderUpdate], updatedAt: Date, updatedBy: String?) async throws {
        guard !updates.isEmpty else { return }

        do {
            let batch = database.batch()
            for update in updates {
                batch.updateData(
                    [
                        "sortOrder": update.sortOrder,
                        "updatedAt": Timestamp(date: updatedAt),
                        "updatedBy": updatedBy ?? NSNull()
                    ],
                    forDocument: guideNodesCollection.document(update.id)
                )
            }
            try await batch.commit()
        } catch {
            throw mapFirestoreError(error)
        }
    }

    func deleteNode(id: String) async throws {
        do {
            try await deleteDocument(guideNodesCollection.document(id))
        } catch {
            throw mapFirestoreError(error)
        }
    }

    func archiveNode(id: String, archivedAt: Date, updatedBy: String?) async throws {
        do {
            try await updateData(
                [
                    "moderationStatus": ModerationStatus.archived.rawValue,
                    "archivedAt": Timestamp(date: archivedAt),
                    "updatedAt": Timestamp(date: archivedAt),
                    "updatedBy": updatedBy ?? NSNull()
                ],
                for: guideNodesCollection.document(id)
            )
        } catch {
            throw mapFirestoreError(error)
        }
    }

    func publishNode(id: String, publishedAt: Date, updatedBy: String?) async throws {
        do {
            try await updateData(
                [
                    "moderationStatus": ModerationStatus.approved.rawValue,
                    "publishedAt": Timestamp(date: publishedAt),
                    "archivedAt": NSNull(),
                    "updatedAt": Timestamp(date: publishedAt),
                    "updatedBy": updatedBy ?? NSNull()
                ],
                for: guideNodesCollection.document(id)
            )
        } catch {
            throw mapFirestoreError(error)
        }
    }

    func createMaterial(_ material: GuideMaterial) async throws -> GuideMaterial {
        do {
            try await setData(
                makeGuideMaterialCreateData(from: material),
                for: guideMaterialsCollection.document(material.id)
            )
            return material
        } catch {
            throw mapFirestoreError(error)
        }
    }

    func updateMaterial(_ material: GuideMaterial) async throws {
        do {
            try await updateData(
                makeGuideMaterialUpdateData(from: material),
                for: guideMaterialsCollection.document(material.id)
            )
        } catch {
            throw mapFirestoreError(error)
        }
    }

    func updateMaterialSortOrders(_ updates: [GuideSortOrderUpdate], updatedAt: Date, updatedBy: String?) async throws {
        guard !updates.isEmpty else { return }

        do {
            let batch = database.batch()
            for update in updates {
                batch.updateData(
                    [
                        "sortOrder": update.sortOrder,
                        "updatedAt": Timestamp(date: updatedAt),
                        "updatedBy": updatedBy ?? NSNull()
                    ],
                    forDocument: guideMaterialsCollection.document(update.id)
                )
            }
            try await batch.commit()
        } catch {
            throw mapFirestoreError(error)
        }
    }

    func deleteMaterial(id: String) async throws {
        do {
            try await deleteDocument(guideMaterialsCollection.document(id))
        } catch {
            throw mapFirestoreError(error)
        }
    }

    func archiveMaterial(id: String, archivedAt: Date, updatedBy: String?) async throws {
        do {
            try await updateData(
                [
                    "moderationStatus": ModerationStatus.archived.rawValue,
                    "archivedAt": Timestamp(date: archivedAt),
                    "updatedAt": Timestamp(date: archivedAt),
                    "updatedBy": updatedBy ?? NSNull()
                ],
                for: guideMaterialsCollection.document(id)
            )
        } catch {
            throw mapFirestoreError(error)
        }
    }

    func publishMaterial(id: String, publishedAt: Date, updatedBy: String?) async throws {
        do {
            try await updateData(
                [
                    "moderationStatus": ModerationStatus.approved.rawValue,
                    "publishedAt": Timestamp(date: publishedAt),
                    "archivedAt": NSNull(),
                    "updatedAt": Timestamp(date: publishedAt),
                    "updatedBy": updatedBy ?? NSNull()
                ],
                for: guideMaterialsCollection.document(id)
            )
        } catch {
            throw mapFirestoreError(error)
        }
    }

    func markMaterialReviewed(
        id: String,
        reviewedAt: Date,
        nextReviewAt: Date,
        reviewedBy: String?
    ) async throws {
        do {
            try await updateData(
                [
                    "lastReviewedAt": Timestamp(date: reviewedAt),
                    "nextReviewAt": Timestamp(date: nextReviewAt),
                    "reviewedBy": reviewedBy ?? NSNull(),
                    "updatedAt": Timestamp(date: reviewedAt),
                    "updatedBy": reviewedBy ?? NSNull()
                ],
                for: guideMaterialsCollection.document(id)
            )
        } catch {
            throw mapFirestoreError(error)
        }
    }
}

extension FirestoreGuideWriteRepository {
    var guideNodesCollection: CollectionReference {
        database.collection("guideNodes")
    }

    var guideMaterialsCollection: CollectionReference {
        database.collection("guideMaterials")
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

    private func normalizedRootNode(_ node: GuideNode) -> GuideNode {
        GuideNode(
            id: node.id,
            parentID: Self.rootParentID,
            kind: node.kind,
            category: node.category,
            title: node.title,
            summary: node.summary,
            sortOrder: node.sortOrder,
            regionScope: node.regionScope,
            federalState: node.federalState,
            healthStatus: node.healthStatus,
            moderationStatus: node.moderationStatus,
            publishedAt: node.publishedAt,
            createdAt: node.createdAt,
            updatedAt: node.updatedAt,
            createdBy: node.createdBy,
            updatedBy: node.updatedBy,
            archivedAt: node.archivedAt
        )
    }

    private func normalizedChildNode(_ node: GuideNode) throws -> GuideNode {
        guard let parentID = node.parentID?.trimmingCharacters(in: .whitespacesAndNewlines), !parentID.isEmpty else {
            throw AppError.validationFailed
        }

        guard parentID != Self.rootParentID else {
            throw AppError.validationFailed
        }

        return GuideNode(
            id: node.id,
            parentID: parentID,
            kind: node.kind,
            category: node.category,
            title: node.title,
            summary: node.summary,
            sortOrder: node.sortOrder,
            regionScope: node.regionScope,
            federalState: node.federalState,
            healthStatus: node.healthStatus,
            moderationStatus: node.moderationStatus,
            publishedAt: node.publishedAt,
            createdAt: node.createdAt,
            updatedAt: node.updatedAt,
            createdBy: node.createdBy,
            updatedBy: node.updatedBy,
            archivedAt: node.archivedAt
        )
    }

    private func setData(_ data: [String: Any], for document: DocumentReference) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            document.setData(data) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func updateData(_ data: [AnyHashable: Any], for document: DocumentReference) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            document.updateData(data) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func deleteDocument(_ document: DocumentReference) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            document.delete { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func getDocuments(_ query: Query) async throws -> QuerySnapshot {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<QuerySnapshot, Error>) in
            query.getDocuments { snapshot, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let snapshot {
                    continuation.resume(returning: snapshot)
                } else {
                    continuation.resume(throwing: AppError.unknown)
                }
            }
        }
    }
}
