import Foundation

extension SystemLogDraft {
    nonisolated static func audit(
        eventType: SystemLogEventType,
        targetType: SystemLogTargetType = .none,
        summary: String,
        actorUserId: String? = nil,
        actorDisplayName: String? = nil,
        actorRole: SystemLogActorRole = .system,
        targetId: String? = nil,
        targetTitle: String? = nil,
        organizationId: String? = nil,
        organizationName: String? = nil,
        outcome: SystemLogOutcome? = nil,
        metadata: [String: String] = [:],
        correlationId: String? = nil
    ) -> SystemLogDraft {
        SystemLogDraft(
            category: .audit,
            severity: .info,
            eventType: eventType,
            actorUserId: actorUserId,
            actorDisplayName: actorDisplayName,
            actorRole: actorRole,
            targetType: targetType,
            targetId: targetId,
            targetTitle: targetTitle,
            organizationId: organizationId,
            organizationName: organizationName,
            summary: summary,
            outcome: outcome,
            metadata: metadata,
            correlationId: correlationId,
            retentionPolicy: .normalAudit
        )
    }

    nonisolated static func error(
        eventType: SystemLogEventType,
        summary: String,
        technicalMessage: String? = nil,
        errorCode: String? = nil,
        moduleName: String? = nil,
        operationName: String? = nil,
        targetType: SystemLogTargetType = .none,
        targetId: String? = nil,
        targetTitle: String? = nil,
        metadata: [String: String] = [:],
        correlationId: String? = nil
    ) -> SystemLogDraft {
        SystemLogDraft(
            category: .diagnostics,
            severity: .error,
            eventType: eventType,
            targetType: targetType,
            targetId: targetId,
            targetTitle: targetTitle,
            summary: summary,
            technicalMessage: technicalMessage,
            errorCode: errorCode,
            moduleName: moduleName,
            operationName: operationName,
            outcome: .failed,
            metadata: metadata,
            correlationId: correlationId,
            retentionPolicy: .technicalError
        )
    }

    nonisolated static func security(
        eventType: SystemLogEventType,
        summary: String,
        severity: SystemLogSeverity = .warning,
        actorUserId: String? = nil,
        actorDisplayName: String? = nil,
        actorRole: SystemLogActorRole = .system,
        targetType: SystemLogTargetType = .none,
        targetId: String? = nil,
        targetTitle: String? = nil,
        outcome: SystemLogOutcome? = .blocked,
        metadata: [String: String] = [:],
        correlationId: String? = nil
    ) -> SystemLogDraft {
        SystemLogDraft(
            category: .authorization,
            severity: severity,
            eventType: eventType,
            actorUserId: actorUserId,
            actorDisplayName: actorDisplayName,
            actorRole: actorRole,
            targetType: targetType,
            targetId: targetId,
            targetTitle: targetTitle,
            summary: summary,
            outcome: outcome,
            metadata: metadata,
            correlationId: correlationId,
            retentionPolicy: .security
        )
    }

    nonisolated static func moderation(
        eventType: SystemLogEventType,
        targetType: SystemLogTargetType,
        summary: String,
        actorUserId: String? = nil,
        actorDisplayName: String? = nil,
        actorRole: SystemLogActorRole = .moderator,
        targetId: String? = nil,
        targetTitle: String? = nil,
        organizationId: String? = nil,
        organizationName: String? = nil,
        outcome: SystemLogOutcome? = nil,
        metadata: [String: String] = [:],
        correlationId: String? = nil
    ) -> SystemLogDraft {
        SystemLogDraft(
            category: .moderation,
            severity: .notice,
            eventType: eventType,
            actorUserId: actorUserId,
            actorDisplayName: actorDisplayName,
            actorRole: actorRole,
            targetType: targetType,
            targetId: targetId,
            targetTitle: targetTitle,
            organizationId: organizationId,
            organizationName: organizationName,
            summary: summary,
            outcome: outcome,
            metadata: metadata,
            correlationId: correlationId,
            retentionPolicy: .moderationDispute
        )
    }
}
