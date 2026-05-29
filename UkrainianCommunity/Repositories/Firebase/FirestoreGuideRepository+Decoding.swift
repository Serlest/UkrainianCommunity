import Foundation
import FirebaseFirestore

extension FirestoreGuideRepository {
    func makeGuideArticle(from document: QueryDocumentSnapshot) -> GuideArticle? {
        makeGuideArticle(documentID: document.documentID, data: document.data())
    }

    func makeGuideArticle(from document: DocumentSnapshot) -> GuideArticle? {
        guard let data = document.data() else {
            logSkippedGuideArticle(documentID: document.documentID, reason: "missing document data")
            return nil
        }

        return makeGuideArticle(documentID: document.documentID, data: data)
    }

    private func makeGuideArticle(documentID: String, data: [String: Any]) -> GuideArticle? {
        guard
            let title = data["title"] as? String,
            let summary = data["summary"] as? String,
            let body = data["body"] as? String,
            let category = data["category"] as? String,
            let createdAt = (data["createdAt"] as? Timestamp)?.dateValue(),
            let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue(),
            let moderationStatus = data["moderationStatus"] as? String
        else {
            logSkippedGuideArticle(documentID: documentID, reason: "missing required fields")
            return nil
        }

        let dto = GuideArticleDTO(
            id: data["id"] as? String ?? documentID,
            title: title,
            summary: summary,
            body: body,
            category: category,
            regionScope: data["regionScope"] as? String,
            federalState: data["federalState"] as? String,
            city: data["city"] as? String,
            officialSourceURL: data["officialSourceURL"] as? String,
            sourceName: data["sourceName"] as? String,
            isPinned: data["isPinned"] as? Bool ?? false,
            moderationStatus: moderationStatus,
            createdAt: createdAt,
            updatedAt: updatedAt,
            contentType: data["contentType"] as? String,
            status: data["status"] as? String,
            contentBlocks: GuideFirestoreDecoding.decodeValue([GuideContentBlock].self, from: data["contentBlocks"]),
            audience: data["audience"] as? [String],
            sourceLinks: GuideFirestoreDecoding.decodeValue([GuideSourceLink].self, from: data["sourceLinks"]),
            officialSourcesRequired: data["officialSourcesRequired"] as? Bool,
            priority: data["priority"] as? Int,
            isFeatured: data["isFeatured"] as? Bool,
            createdBy: data["createdBy"] as? String,
            updatedBy: data["updatedBy"] as? String,
            reviewedBy: data["reviewedBy"] as? String,
            publishedAt: GuideFirestoreDecoding.date(from: data["publishedAt"]),
            lastReviewedAt: GuideFirestoreDecoding.date(from: data["lastReviewedAt"]),
            nextReviewAt: GuideFirestoreDecoding.date(from: data["nextReviewAt"]),
            reviewInterval: data["reviewInterval"] as? String,
            archivedAt: GuideFirestoreDecoding.date(from: data["archivedAt"])
        )

        guard let article = GuideArticle(dto: dto) else {
            logSkippedGuideArticle(
                documentID: documentID,
                reason: "invalid category or moderationStatus"
            )
            return nil
        }

        return article
    }

    private func logSkippedGuideArticle(documentID: String, reason: String) {
        #if DEBUG
        print("Guide article skipped: id=\(documentID) reason=\(reason)")
        #endif
    }
}
