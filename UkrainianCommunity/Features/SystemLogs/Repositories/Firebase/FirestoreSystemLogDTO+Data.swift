import FirebaseFirestore
import Foundation

extension FirestoreSystemLogDTO {
    init(id documentID: String, data: [String: Any]) {
        let field = SystemLogFirestoreContract.Field.self
        let severityValue = data[field.severity.rawValue] as? String ?? SystemLogSeverity.info.rawValue

        id = data[field.id.rawValue] as? String ?? documentID
        createdAt = (data[field.createdAt.rawValue] as? Timestamp)?.dateValue() ?? Date()
        category = data[field.category.rawValue] as? String ?? SystemLogCategory.unknown.rawValue
        severity = severityValue
        severityRank = data[field.severityRank.rawValue] as? Int
            ?? Self.rank(for: SystemLogSeverity(rawValue: severityValue) ?? .info)
        eventType = data[field.eventType.rawValue] as? String ?? SystemLogEventType.unknown.rawValue
        actorUserId = data[field.actorUserId.rawValue] as? String
        actorDisplayName = data[field.actorDisplayName.rawValue] as? String
        actorRole = data[field.actorRole.rawValue] as? String ?? SystemLogActorRole.unknown.rawValue
        targetType = data[field.targetType.rawValue] as? String ?? SystemLogTargetType.unknown.rawValue
        targetId = data[field.targetId.rawValue] as? String
        targetTitle = data[field.targetTitle.rawValue] as? String
        organizationId = data[field.organizationId.rawValue] as? String
        organizationName = data[field.organizationName.rawValue] as? String
        outcome = data[field.outcome.rawValue] as? String
        summary = data[field.summary.rawValue] as? String ?? ""
        technicalMessage = data[field.technicalMessage.rawValue] as? String
        errorCode = data[field.errorCode.rawValue] as? String
        moduleName = data[field.moduleName.rawValue] as? String
        screenName = data[field.screenName.rawValue] as? String
        operationName = data[field.operationName.rawValue] as? String
        appVersion = data[field.appVersion.rawValue] as? String
        osVersion = data[field.osVersion.rawValue] as? String
        deviceModel = data[field.deviceModel.rawValue] as? String
        isReviewed = data[field.isReviewed.rawValue] as? Bool ?? false
        reviewedAt = (data[field.reviewedAt.rawValue] as? Timestamp)?.dateValue()
        reviewedByUserId = data[field.reviewedByUserId.rawValue] as? String
        metadata = Self.stringDictionary(from: data[field.metadata.rawValue])
        retentionPolicy = data[field.retentionPolicy.rawValue] as? String
        correlationId = data[field.correlationId.rawValue] as? String
    }

    nonisolated var data: [String: Any] {
        let field = SystemLogFirestoreContract.Field.self
        var data: [String: Any] = [
            field.id.rawValue: id,
            field.createdAt.rawValue: Timestamp(date: createdAt),
            field.category.rawValue: category,
            field.severity.rawValue: severity,
            field.severityRank.rawValue: severityRank,
            field.eventType.rawValue: eventType,
            field.actorRole.rawValue: actorRole,
            field.targetType.rawValue: targetType,
            field.summary.rawValue: summary,
            field.isReviewed.rawValue: isReviewed,
            field.metadata.rawValue: metadata
        ]

        set(actorUserId, for: field.actorUserId, in: &data)
        set(actorDisplayName, for: field.actorDisplayName, in: &data)
        set(targetId, for: field.targetId, in: &data)
        set(targetTitle, for: field.targetTitle, in: &data)
        set(organizationId, for: field.organizationId, in: &data)
        set(organizationName, for: field.organizationName, in: &data)
        set(outcome, for: field.outcome, in: &data)
        set(technicalMessage, for: field.technicalMessage, in: &data)
        set(errorCode, for: field.errorCode, in: &data)
        set(moduleName, for: field.moduleName, in: &data)
        set(screenName, for: field.screenName, in: &data)
        set(operationName, for: field.operationName, in: &data)
        set(appVersion, for: field.appVersion, in: &data)
        set(osVersion, for: field.osVersion, in: &data)
        set(deviceModel, for: field.deviceModel, in: &data)
        set(reviewedAt.map(Timestamp.init(date:)), for: field.reviewedAt, in: &data)
        set(reviewedByUserId, for: field.reviewedByUserId, in: &data)
        set(retentionPolicy, for: field.retentionPolicy, in: &data)
        set(correlationId, for: field.correlationId, in: &data)

        return data
    }

    private nonisolated func set(_ value: Any?, for field: SystemLogFirestoreContract.Field, in data: inout [String: Any]) {
        guard let value else { return }
        data[field.rawValue] = value
    }

    private static func stringDictionary(from value: Any?) -> [String: String] {
        guard let dictionary = value as? [String: Any] else { return [:] }

        return dictionary.reduce(into: [String: String]()) { result, item in
            switch item.value {
            case let string as String:
                result[item.key] = string
            case let value as CustomStringConvertible:
                result[item.key] = value.description
            default:
                break
            }
        }
    }
}
