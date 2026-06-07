import Foundation

extension SystemLogEntry {
    func markedReviewed(at reviewedAt: Date, reviewedByUserId: String) -> SystemLogEntry {
        SystemLogEntry(
            id: id,
            createdAt: createdAt,
            category: category,
            severity: severity,
            eventType: eventType,
            actorUserId: actorUserId,
            actorDisplayName: actorDisplayName,
            actorRole: actorRole,
            targetType: targetType,
            targetId: targetId,
            targetTitle: targetTitle,
            organizationId: organizationId,
            organizationName: organizationName,
            outcome: outcome,
            summary: summary,
            technicalMessage: technicalMessage,
            errorCode: errorCode,
            moduleName: moduleName,
            screenName: screenName,
            operationName: operationName,
            appVersion: appVersion,
            osVersion: osVersion,
            deviceModel: deviceModel,
            isReviewed: true,
            reviewedAt: reviewedAt,
            reviewedByUserId: reviewedByUserId,
            metadata: metadata,
            retentionPolicy: retentionPolicy,
            correlationId: correlationId
        )
    }
}
