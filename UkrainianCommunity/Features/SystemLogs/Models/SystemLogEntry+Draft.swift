import Foundation

extension SystemLogEntry {
    nonisolated init(
        id: String,
        createdAt: Date,
        draft: SystemLogDraft,
        isReviewed: Bool = false,
        reviewedAt: Date? = nil,
        reviewedByUserId: String? = nil
    ) {
        self.init(
            id: id,
            createdAt: createdAt,
            category: draft.category,
            severity: draft.severity,
            eventType: draft.eventType,
            actorUserId: draft.actorUserId,
            actorDisplayName: draft.actorDisplayName,
            actorRole: draft.actorRole,
            targetType: draft.targetType,
            targetId: draft.targetId,
            targetTitle: draft.targetTitle,
            organizationId: draft.organizationId,
            organizationName: draft.organizationName,
            outcome: draft.outcome,
            summary: draft.summary,
            technicalMessage: draft.technicalMessage,
            errorCode: draft.errorCode,
            moduleName: draft.moduleName,
            screenName: draft.screenName,
            operationName: draft.operationName,
            appVersion: draft.appVersion,
            osVersion: draft.osVersion,
            deviceModel: draft.deviceModel,
            isReviewed: isReviewed,
            reviewedAt: reviewedAt,
            reviewedByUserId: reviewedByUserId,
            metadata: draft.metadata,
            retentionPolicy: draft.retentionPolicy,
            correlationId: draft.correlationId
        )
    }
}
