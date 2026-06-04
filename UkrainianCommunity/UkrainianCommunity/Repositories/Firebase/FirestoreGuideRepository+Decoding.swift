import Foundation
import FirebaseFirestore

extension FirestoreGuideRepository {
    func makeGuideNode(from document: QueryDocumentSnapshot) -> GuideNode? {
        makeGuideNode(documentID: document.documentID, data: document.data())
    }

    func makeGuideMaterial(from document: QueryDocumentSnapshot) -> GuideMaterial? {
        makeGuideMaterial(documentID: document.documentID, data: document.data())
    }

    func makeGuideMaterial(from document: DocumentSnapshot) -> GuideMaterial? {
        guard let data = document.data() else {
            logSkippedGuideMaterial(documentID: document.documentID, reason: "missing document data")
            return nil
        }

        return makeGuideMaterial(documentID: document.documentID, data: data)
    }

    private func makeGuideNode(documentID: String, data: [String: Any]) -> GuideNode? {
        guard
            let kindRawValue = data["kind"] as? String,
            let kind = GuideNodeKind(rawValue: kindRawValue),
            let categoryRawValue = data["category"] as? String,
            let category = GuideCategory(rawValue: categoryRawValue),
            let title = data["title"] as? String,
            let summary = data["summary"] as? String,
            let healthStatusRawValue = data["healthStatus"] as? String,
            let healthStatus = GuideHealthStatus(rawValue: healthStatusRawValue),
            let moderationStatusRawValue = data["moderationStatus"] as? String,
            let moderationStatus = ModerationStatus(rawValue: moderationStatusRawValue),
            let createdAt = GuideFirestoreDecoding.date(from: data["createdAt"]),
            let updatedAt = GuideFirestoreDecoding.date(from: data["updatedAt"])
        else {
            logSkippedGuideNode(documentID: documentID, reason: "missing required fields")
            return nil
        }

        let federalState = (data["federalState"] as? String).flatMap(AustrianFederalState.init(rawValue:))
        let regionScope = (data["regionScope"] as? String).flatMap(RegionScope.init(rawValue:))

        return GuideNode(
            id: data["id"] as? String ?? documentID,
            parentID: data["parentID"] as? String ?? Self.rootParentID,
            kind: kind,
            category: category,
            title: title,
            summary: summary,
            sortOrder: data["sortOrder"] as? Int ?? 0,
            regionScope: regionScope,
            federalState: federalState,
            healthStatus: healthStatus,
            moderationStatus: moderationStatus,
            publishedAt: GuideFirestoreDecoding.date(from: data["publishedAt"]),
            createdAt: createdAt,
            updatedAt: updatedAt,
            createdBy: data["createdBy"] as? String,
            updatedBy: data["updatedBy"] as? String,
            archivedAt: GuideFirestoreDecoding.date(from: data["archivedAt"])
        )
    }

    private func makeGuideMaterial(documentID: String, data: [String: Any]) -> GuideMaterial? {
        guard let kindRawValue = data["kind"] as? String else {
            logSkippedGuideMaterial(documentID: documentID, reason: "missing kind")
            return nil
        }

        guard let kind = GuideMaterialKind(rawValue: kindRawValue) else {
            logSkippedGuideMaterial(documentID: documentID, reason: "invalid kind=\(kindRawValue)")
            return nil
        }

        guard let categoryRawValue = data["category"] as? String else {
            logSkippedGuideMaterial(documentID: documentID, reason: "missing category")
            return nil
        }

        guard let category = GuideCategory(rawValue: categoryRawValue) else {
            logSkippedGuideMaterial(documentID: documentID, reason: "invalid category=\(categoryRawValue)")
            return nil
        }

        guard let nodeID = data["nodeID"] as? String else {
            logSkippedGuideMaterial(documentID: documentID, reason: "missing nodeID")
            return nil
        }

        guard let nodePath = GuideFirestoreDecoding.decodeValue(GuideTreePath.self, from: data["nodePath"]) else {
            let rawValue = data["nodePath"]
            logSkippedGuideMaterial(
                documentID: documentID,
                reason: "invalid nodePath type=\(debugValueType(rawValue)) value=\(debugValueDescription(rawValue))"
            )
            return nil
        }

        guard let title = data["title"] as? String else {
            logSkippedGuideMaterial(documentID: documentID, reason: "missing title")
            return nil
        }

        guard let summary = data["summary"] as? String else {
            logSkippedGuideMaterial(documentID: documentID, reason: "missing summary")
            return nil
        }

        guard let body = data["body"] as? String else {
            logSkippedGuideMaterial(documentID: documentID, reason: "missing body")
            return nil
        }

        guard let moderationStatusRawValue = data["moderationStatus"] as? String else {
            logSkippedGuideMaterial(documentID: documentID, reason: "missing moderationStatus")
            return nil
        }

        guard let moderationStatus = ModerationStatus(rawValue: moderationStatusRawValue) else {
            logSkippedGuideMaterial(
                documentID: documentID,
                reason: "invalid moderationStatus=\(moderationStatusRawValue)"
            )
            return nil
        }

        guard let createdAt = GuideFirestoreDecoding.date(from: data["createdAt"]) else {
            logSkippedGuideMaterial(documentID: documentID, reason: "invalid createdAt")
            return nil
        }

        guard let updatedAt = GuideFirestoreDecoding.date(from: data["updatedAt"]) else {
            logSkippedGuideMaterial(documentID: documentID, reason: "invalid updatedAt")
            return nil
        }

        let reviewInterval = (data["reviewInterval"] as? String).flatMap(ReviewInterval.init(rawValue:)) ?? .normal
        let federalState = (data["federalState"] as? String).flatMap(AustrianFederalState.init(rawValue:))
        let regionScope = (data["regionScope"] as? String).flatMap(RegionScope.init(rawValue:))

        return GuideMaterial(
            id: data["id"] as? String ?? documentID,
            title: title,
            summary: summary,
            body: body,
            sortOrder: data["sortOrder"] as? Int ?? 0,
            contentBlocks: GuideFirestoreDecoding.decodeValue([GuideContentBlock].self, from: data["contentBlocks"]) ?? [],
            sourceLinks: GuideFirestoreDecoding.decodeValue([GuideSourceLink].self, from: data["sourceLinks"]) ?? [],
            officialSourceURL: data["officialSourceURL"] as? String,
            sourceName: data["sourceName"] as? String,
            officialSourcesRequired: data["officialSourcesRequired"] as? Bool ?? false,
            kind: kind,
            category: category,
            nodeID: nodeID,
            nodePath: nodePath,
            regionScope: regionScope,
            federalState: federalState,
            reviewInterval: reviewInterval,
            lastReviewedAt: GuideFirestoreDecoding.date(from: data["lastReviewedAt"]),
            nextReviewAt: GuideFirestoreDecoding.date(from: data["nextReviewAt"]),
            reviewedBy: data["reviewedBy"] as? String,
            moderationStatus: moderationStatus,
            publishedAt: GuideFirestoreDecoding.date(from: data["publishedAt"]),
            createdAt: createdAt,
            updatedAt: updatedAt,
            createdBy: data["createdBy"] as? String,
            updatedBy: data["updatedBy"] as? String,
            archivedAt: GuideFirestoreDecoding.date(from: data["archivedAt"])
        )
    }

    private func logSkippedGuideNode(documentID: String, reason: String) {
        #if DEBUG
        print("Guide node skipped: id=\(documentID) reason=\(reason)")
        #endif
    }

    private func logSkippedGuideMaterial(documentID: String, reason: String) {
        #if DEBUG
        print("Guide material skipped: id=\(documentID) reason=\(reason)")
        #endif
    }

    private func debugValueType(_ value: Any?) -> String {
        guard let value else {
            return "nil"
        }

        return String(describing: type(of: value))
    }

    private func debugValueDescription(_ value: Any?) -> String {
        guard let value else {
            return "nil"
        }

        return String(describing: value)
    }
}
