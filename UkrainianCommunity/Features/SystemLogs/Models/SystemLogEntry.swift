import Foundation

struct SystemLogEntry: Identifiable, Codable, Equatable {
    let id: String
    let createdAt: Date
    let category: SystemLogCategory
    let severity: SystemLogSeverity
    let eventType: SystemLogEventType
    let actorUserId: String?
    let actorDisplayName: String?
    let actorRole: SystemLogActorRole
    let targetType: SystemLogTargetType
    let targetId: String?
    let targetTitle: String?
    let organizationId: String?
    let organizationName: String?
    let outcome: SystemLogOutcome?
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
    let retentionPolicy: SystemLogRetentionPolicy?
    let correlationId: String?

    nonisolated init(
        id: String,
        createdAt: Date,
        category: SystemLogCategory,
        severity: SystemLogSeverity,
        eventType: SystemLogEventType,
        actorUserId: String? = nil,
        actorDisplayName: String? = nil,
        actorRole: SystemLogActorRole,
        targetType: SystemLogTargetType,
        targetId: String? = nil,
        targetTitle: String? = nil,
        organizationId: String? = nil,
        organizationName: String? = nil,
        outcome: SystemLogOutcome? = nil,
        summary: String,
        technicalMessage: String? = nil,
        errorCode: String? = nil,
        moduleName: String? = nil,
        screenName: String? = nil,
        operationName: String? = nil,
        appVersion: String? = nil,
        osVersion: String? = nil,
        deviceModel: String? = nil,
        isReviewed: Bool = false,
        reviewedAt: Date? = nil,
        reviewedByUserId: String? = nil,
        metadata: [String: String] = [:],
        retentionPolicy: SystemLogRetentionPolicy? = nil,
        correlationId: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.category = category
        self.severity = severity
        self.eventType = eventType
        self.actorUserId = actorUserId
        self.actorDisplayName = actorDisplayName
        self.actorRole = actorRole
        self.targetType = targetType
        self.targetId = targetId
        self.targetTitle = targetTitle
        self.organizationId = organizationId
        self.organizationName = organizationName
        self.outcome = outcome
        self.summary = summary
        self.technicalMessage = technicalMessage
        self.errorCode = errorCode
        self.moduleName = moduleName
        self.screenName = screenName
        self.operationName = operationName
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.isReviewed = isReviewed
        self.reviewedAt = reviewedAt
        self.reviewedByUserId = reviewedByUserId
        self.metadata = metadata
        self.retentionPolicy = retentionPolicy
        self.correlationId = correlationId
    }
}
