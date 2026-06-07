import FirebaseFirestore
import Foundation

struct FirestoreSystemLogDTO: Codable, Equatable {
    let id: String
    let createdAt: Date
    let category: String
    let severity: String
    let severityRank: Int
    let eventType: String
    let actorUserId: String?
    let actorDisplayName: String?
    let actorRole: String
    let targetType: String
    let targetId: String?
    let targetTitle: String?
    let organizationId: String?
    let organizationName: String?
    let outcome: String?
    let summary: String
    let technicalMessage: String?
    let errorCode: String?
    let moduleName: String?
    let screenName: String?
    let operationName: String?
    let appVersion: String?
    let osVersion: String?
    let deviceModel: String?
    let isReviewed: Bool
    let reviewedAt: Date?
    let reviewedByUserId: String?
    let metadata: [String: String]
    let retentionPolicy: String?
    let correlationId: String?

    nonisolated init(entry: SystemLogEntry) {
        id = entry.id
        createdAt = entry.createdAt
        category = entry.category.rawValue
        severity = entry.severity.rawValue
        severityRank = Self.rank(for: entry.severity)
        eventType = entry.eventType.rawValue
        actorUserId = entry.actorUserId
        actorDisplayName = entry.actorDisplayName
        actorRole = entry.actorRole.rawValue
        targetType = entry.targetType.rawValue
        targetId = entry.targetId
        targetTitle = entry.targetTitle
        organizationId = entry.organizationId
        organizationName = entry.organizationName
        outcome = entry.outcome?.rawValue
        summary = entry.summary
        technicalMessage = entry.technicalMessage
        errorCode = entry.errorCode
        moduleName = entry.moduleName
        screenName = entry.screenName
        operationName = entry.operationName
        appVersion = entry.appVersion
        osVersion = entry.osVersion
        deviceModel = entry.deviceModel
        isReviewed = entry.isReviewed
        reviewedAt = entry.reviewedAt
        reviewedByUserId = entry.reviewedByUserId
        metadata = entry.metadata
        retentionPolicy = entry.retentionPolicy?.rawValue
        correlationId = entry.correlationId
    }

    nonisolated init(
        id: String,
        createdAt: Date,
        draft: SystemLogDraft,
        redactionPolicy: SystemLogRedactionPolicy = .default
    ) {
        let redactedDraft = redactionPolicy.redactedDraft(from: draft)
        self.init(entry: SystemLogEntry(id: id, createdAt: createdAt, draft: redactedDraft))
    }

    nonisolated var entry: SystemLogEntry {
        SystemLogEntry(
            id: id,
            createdAt: createdAt,
            category: SystemLogCategory(rawValue: category) ?? .unknown,
            severity: SystemLogSeverity(rawValue: severity) ?? .info,
            eventType: SystemLogEventType(rawValue: eventType) ?? .unknown,
            actorUserId: actorUserId,
            actorDisplayName: actorDisplayName,
            actorRole: SystemLogActorRole(rawValue: actorRole) ?? .unknown,
            targetType: SystemLogTargetType(rawValue: targetType) ?? .unknown,
            targetId: targetId,
            targetTitle: targetTitle,
            organizationId: organizationId,
            organizationName: organizationName,
            outcome: outcome.flatMap(SystemLogOutcome.init(rawValue:)),
            summary: summary,
            technicalMessage: technicalMessage,
            errorCode: errorCode,
            moduleName: moduleName,
            screenName: screenName,
            operationName: operationName,
            appVersion: appVersion,
            osVersion: osVersion,
            deviceModel: deviceModel,
            isReviewed: isReviewed,
            reviewedAt: reviewedAt,
            reviewedByUserId: reviewedByUserId,
            metadata: metadata,
            retentionPolicy: retentionPolicy.flatMap(SystemLogRetentionPolicy.init(rawValue:)),
            correlationId: correlationId
        )
    }

    nonisolated static func rank(for severity: SystemLogSeverity) -> Int {
        switch severity {
        case .debug: 0
        case .info: 1
        case .notice: 2
        case .warning: 3
        case .error: 4
        case .critical: 5
        }
    }
}
