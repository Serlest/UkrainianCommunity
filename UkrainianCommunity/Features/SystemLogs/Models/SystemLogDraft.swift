import Foundation

struct SystemLogDraft: Codable, Equatable {
    var category: SystemLogCategory
    var severity: SystemLogSeverity
    var eventType: SystemLogEventType
    var actorUserId: String?
    var actorDisplayName: String?
    var actorRole: SystemLogActorRole
    var targetType: SystemLogTargetType
    var targetId: String?
    var targetTitle: String?
    var organizationId: String?
    var organizationName: String?
    var summary: String
    var technicalMessage: String?
    var errorCode: String?
    var moduleName: String?
    var screenName: String?
    var operationName: String?
    var appVersion: String?
    var osVersion: String?
    var deviceModel: String?
    var outcome: SystemLogOutcome?
    var metadata: [String: String]
    var correlationId: String?
    var retentionPolicy: SystemLogRetentionPolicy?

    nonisolated init(
        category: SystemLogCategory,
        severity: SystemLogSeverity = .info,
        eventType: SystemLogEventType,
        actorUserId: String? = nil,
        actorDisplayName: String? = nil,
        actorRole: SystemLogActorRole = .system,
        targetType: SystemLogTargetType = .none,
        targetId: String? = nil,
        targetTitle: String? = nil,
        organizationId: String? = nil,
        organizationName: String? = nil,
        summary: String,
        technicalMessage: String? = nil,
        errorCode: String? = nil,
        moduleName: String? = nil,
        screenName: String? = nil,
        operationName: String? = nil,
        appVersion: String? = nil,
        osVersion: String? = nil,
        deviceModel: String? = nil,
        outcome: SystemLogOutcome? = nil,
        metadata: [String: String] = [:],
        correlationId: String? = nil,
        retentionPolicy: SystemLogRetentionPolicy? = nil
    ) {
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
        self.summary = summary
        self.technicalMessage = technicalMessage
        self.errorCode = errorCode
        self.moduleName = moduleName
        self.screenName = screenName
        self.operationName = operationName
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.outcome = outcome
        self.metadata = metadata
        self.correlationId = correlationId
        self.retentionPolicy = retentionPolicy
    }
}
