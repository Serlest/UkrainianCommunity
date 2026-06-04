import Foundation
import FirebaseFirestore

extension FirestoreGuideWriteRepository {
    func makeGuideNodeCreateData(from node: GuideNode) -> [String: Any] {
        [
            "id": node.id,
            "parentID": node.parentID ?? Self.rootParentID,
            "kind": node.kind.rawValue,
            "category": node.category.rawValue,
            "title": node.title,
            "summary": node.summary,
            "sortOrder": node.sortOrder,
            "regionScope": node.regionScope?.rawValue ?? NSNull(),
            "federalState": node.federalState?.rawValue ?? NSNull(),
            "healthStatus": node.healthStatus.rawValue,
            "moderationStatus": node.moderationStatus.rawValue,
            "publishedAt": node.publishedAt.map(Timestamp.init(date:)) ?? NSNull(),
            "createdAt": Timestamp(date: node.createdAt),
            "updatedAt": Timestamp(date: node.updatedAt),
            "createdBy": node.createdBy ?? NSNull(),
            "updatedBy": node.updatedBy ?? NSNull(),
            "archivedAt": node.archivedAt.map(Timestamp.init(date:)) ?? NSNull()
        ]
    }

    func makeGuideNodeUpdateData(from node: GuideNode) -> [AnyHashable: Any] {
        [
            "parentID": node.parentID ?? Self.rootParentID,
            "kind": node.kind.rawValue,
            "category": node.category.rawValue,
            "title": node.title,
            "summary": node.summary,
            "sortOrder": node.sortOrder,
            "regionScope": node.regionScope?.rawValue ?? NSNull(),
            "federalState": node.federalState?.rawValue ?? NSNull(),
            "healthStatus": node.healthStatus.rawValue,
            "moderationStatus": node.moderationStatus.rawValue,
            "publishedAt": node.publishedAt.map(Timestamp.init(date:)) ?? NSNull(),
            "updatedAt": Timestamp(date: node.updatedAt),
            "updatedBy": node.updatedBy ?? NSNull(),
            "archivedAt": node.archivedAt.map(Timestamp.init(date:)) ?? NSNull()
        ]
    }

    func makeGuideMaterialCreateData(from material: GuideMaterial) throws -> [String: Any] {
        [
            "id": material.id,
            "title": material.title,
            "summary": material.summary,
            "body": material.body,
            "sortOrder": material.sortOrder,
            "contentBlocks": try makeFirestoreJSONValue(from: material.contentBlocks),
            "sourceLinks": try makeFirestoreJSONValue(from: material.sourceLinks),
            "officialSourceURL": material.officialSourceURL ?? NSNull(),
            "sourceName": material.sourceName ?? NSNull(),
            "officialSourcesRequired": material.officialSourcesRequired,
            "kind": material.kind.rawValue,
            "category": material.category.rawValue,
            "nodeID": material.nodeID,
            "nodePath": try makeFirestoreJSONValue(from: material.nodePath),
            "regionScope": material.regionScope?.rawValue ?? NSNull(),
            "federalState": material.federalState?.rawValue ?? NSNull(),
            "reviewInterval": material.reviewInterval.rawValue,
            "lastReviewedAt": material.lastReviewedAt.map(Timestamp.init(date:)) ?? NSNull(),
            "nextReviewAt": material.nextReviewAt.map(Timestamp.init(date:)) ?? NSNull(),
            "reviewedBy": material.reviewedBy ?? NSNull(),
            "moderationStatus": material.moderationStatus.rawValue,
            "publishedAt": material.publishedAt.map(Timestamp.init(date:)) ?? NSNull(),
            "createdAt": Timestamp(date: material.createdAt),
            "updatedAt": Timestamp(date: material.updatedAt),
            "createdBy": material.createdBy ?? NSNull(),
            "updatedBy": material.updatedBy ?? NSNull(),
            "archivedAt": material.archivedAt.map(Timestamp.init(date:)) ?? NSNull()
        ]
    }

    func makeGuideMaterialUpdateData(from material: GuideMaterial) throws -> [AnyHashable: Any] {
        [
            "title": material.title,
            "summary": material.summary,
            "body": material.body,
            "sortOrder": material.sortOrder,
            "contentBlocks": try makeFirestoreJSONValue(from: material.contentBlocks),
            "sourceLinks": try makeFirestoreJSONValue(from: material.sourceLinks),
            "officialSourceURL": material.officialSourceURL ?? NSNull(),
            "sourceName": material.sourceName ?? NSNull(),
            "officialSourcesRequired": material.officialSourcesRequired,
            "kind": material.kind.rawValue,
            "category": material.category.rawValue,
            "nodeID": material.nodeID,
            "nodePath": try makeFirestoreJSONValue(from: material.nodePath),
            "regionScope": material.regionScope?.rawValue ?? NSNull(),
            "federalState": material.federalState?.rawValue ?? NSNull(),
            "reviewInterval": material.reviewInterval.rawValue,
            "lastReviewedAt": material.lastReviewedAt.map(Timestamp.init(date:)) ?? NSNull(),
            "nextReviewAt": material.nextReviewAt.map(Timestamp.init(date:)) ?? NSNull(),
            "reviewedBy": material.reviewedBy ?? NSNull(),
            "moderationStatus": material.moderationStatus.rawValue,
            "publishedAt": material.publishedAt.map(Timestamp.init(date:)) ?? NSNull(),
            "updatedAt": Timestamp(date: material.updatedAt),
            "updatedBy": material.updatedBy ?? NSNull(),
            "archivedAt": material.archivedAt.map(Timestamp.init(date:)) ?? NSNull()
        ]
    }

    private func makeFirestoreJSONValue<T: Encodable>(from value: T) throws -> Any {
        do {
            let data = try JSONEncoder().encode(value)
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw AppError.validationFailed
        }
    }
}
