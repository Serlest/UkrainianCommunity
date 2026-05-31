import Foundation
import FirebaseFirestore

extension FirestoreGuideRepository {
    func makeCreateData(from article: GuideArticle) throws -> [String: Any] {
        var data: [String: Any] = [
            "id": article.id,
            "title": article.title,
            "summary": article.summary,
            "body": article.body,
            "category": article.category.rawValue,
            "regionScope": article.regionScope?.rawValue ?? RegionScope.austria.rawValue,
            "isPinned": article.isPinned,
            "moderationStatus": article.moderationStatus.rawValue,
            "createdAt": Timestamp(date: article.createdAt),
            "updatedAt": Timestamp(date: article.updatedAt),
            "status": (article.status ?? .draft).rawValue,
            "createdBy": article.createdBy ?? ""
        ]

        if let federalState = article.federalState {
            data["federalState"] = federalState.rawValue
        }
        if let city = article.city {
            data["city"] = city
        }
        if let officialSourceURL = article.officialSourceURL {
            data["officialSourceURL"] = officialSourceURL
        }
        if let sourceName = article.sourceName {
            data["sourceName"] = sourceName
        }
        if let contentType = article.contentType {
            data["contentType"] = contentType.rawValue
        }
        if let contentBlocks = article.contentBlocks {
            data["contentBlocks"] = try makeFirestoreJSONValue(from: contentBlocks)
        }
        if let audience = article.audience {
            data["audience"] = audience
        }
        if let sourceLinks = article.sourceLinks {
            data["sourceLinks"] = try makeFirestoreJSONValue(from: sourceLinks)
        }
        if let officialSourcesRequired = article.officialSourcesRequired {
            data["officialSourcesRequired"] = officialSourcesRequired
        }
        if let priority = article.priority {
            data["priority"] = priority
        }
        if let isFeatured = article.isFeatured {
            data["isFeatured"] = isFeatured
        }
        if let reviewInterval = article.reviewInterval {
            data["reviewInterval"] = reviewInterval.rawValue
        }

        return data
    }

    func makeUpdateData(from article: GuideArticle) throws -> [AnyHashable: Any] {
        var data: [AnyHashable: Any] = [
            "title": article.title,
            "summary": article.summary,
            "body": article.body,
            "category": article.category.rawValue,
            "regionScope": article.regionScope?.rawValue ?? RegionScope.austria.rawValue,
            "contentType": article.contentType?.rawValue ?? GuideContentType.guide.rawValue,
            "contentBlocks": try makeFirestoreJSONValue(from: article.contentBlocks ?? []),
            "audience": article.audience ?? [],
            "sourceLinks": try makeFirestoreJSONValue(from: article.sourceLinks ?? []),
            "officialSourcesRequired": article.officialSourcesRequired ?? false,
            "priority": article.priority ?? 0,
            "isFeatured": article.isFeatured ?? false,
            "reviewInterval": article.reviewInterval?.rawValue ?? ReviewInterval.normal.rawValue,
            "updatedAt": Timestamp(date: article.updatedAt),
            "updatedBy": article.updatedBy ?? ""
        ]

        data["federalState"] = article.federalState?.rawValue ?? FieldValue.delete()
        data["officialSourceURL"] = article.officialSourceURL ?? FieldValue.delete()
        data["sourceName"] = article.sourceName ?? FieldValue.delete()

        return data
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
