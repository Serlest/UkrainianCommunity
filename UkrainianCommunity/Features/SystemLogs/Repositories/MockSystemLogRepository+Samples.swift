import Foundation

extension MockSystemLogRepository {
    nonisolated static let sampleEntries: [SystemLogEntry] = {
        let baseDate = Date(timeIntervalSinceReferenceDate: 802_000_000)

        return [
            SystemLogEntry(
                id: "system-log-001",
                createdAt: baseDate.addingTimeInterval(-180),
                category: .diagnostics,
                severity: .critical,
                eventType: .dataValidationFailed,
                actorRole: .system,
                targetType: .event,
                targetId: "event-332",
                targetTitle: "Language Workshop",
                outcome: .failed,
                summary: "Event publishing failed because required scheduling data was missing.",
                technicalMessage: "Validation rejected event payload before persistence.",
                errorCode: "EVENT_VALIDATION_REQUIRED_FIELD",
                moduleName: "Events",
                screenName: "EventEditor",
                operationName: "publishEvent",
                appVersion: "1.0.0-mock",
                osVersion: "iOS 18.5",
                deviceModel: "iPhone Mock",
                metadata: [
                    "validationArea": "schedule",
                    "missingField": "startDate",
                    "source": "draftValidation"
                ],
                retentionPolicy: .technicalError,
                correlationId: "corr-event-332"
            ),
            SystemLogEntry(
                id: "system-log-002",
                createdAt: baseDate.addingTimeInterval(-900),
                category: .authorization,
                severity: .warning,
                eventType: .permissionDenied,
                actorUserId: "user-reviewer-1",
                actorDisplayName: "Community Reviewer",
                actorRole: .moderator,
                targetType: .organizationRequest,
                targetId: "org-request-204",
                targetTitle: "Volunteer Center Request",
                organizationId: "org-204",
                organizationName: "Volunteer Center",
                outcome: .blocked,
                summary: "Moderator attempted an owner-only organization approval action.",
                moduleName: "Organizations",
                screenName: "OrganizationModeration",
                operationName: "approveOrganizationRequest",
                isReviewed: true,
                reviewedAt: baseDate.addingTimeInterval(-600),
                reviewedByUserId: "user-owner-1",
                metadata: [
                    "requiredRole": "owner",
                    "requestStatus": "pendingReview",
                    "surface": "organizationModeration"
                ],
                retentionPolicy: .security,
                correlationId: "corr-org-204"
            ),
            SystemLogEntry(
                id: "system-log-003",
                createdAt: baseDate.addingTimeInterval(-1_800),
                category: .moderation,
                severity: .notice,
                eventType: .contentRejected,
                actorUserId: "user-owner-1",
                actorDisplayName: "Platform Owner",
                actorRole: .owner,
                targetType: .newsPost,
                targetId: "news-118",
                targetTitle: "Community Aid Update",
                outcome: .rejected,
                summary: "News post was rejected during moderation review.",
                moduleName: "News",
                screenName: "ModerationQueue",
                operationName: "rejectNewsPost",
                metadata: [
                    "previousStatus": "pending",
                    "newStatus": "rejected",
                    "reasonCode": "needsSourceReview"
                ],
                retentionPolicy: .moderationDispute,
                correlationId: "corr-news-118"
            ),
            SystemLogEntry(
                id: "system-log-004",
                createdAt: baseDate.addingTimeInterval(-3_600),
                category: .organization,
                severity: .info,
                eventType: .organizationRequestApproved,
                actorUserId: "user-owner-1",
                actorDisplayName: "Platform Owner",
                actorRole: .owner,
                targetType: .organizationRequest,
                targetId: "org-request-305",
                targetTitle: "Legal Aid Hub Request",
                organizationId: "org-305",
                organizationName: "Legal Aid Hub",
                outcome: .approved,
                summary: "Organization request was approved.",
                moduleName: "Organizations",
                screenName: "OrganizationRequests",
                operationName: "approveOrganizationRequest",
                metadata: [
                    "previousStatus": "pending",
                    "newStatus": "approved",
                    "organizationType": "communityService"
                ],
                retentionPolicy: .normalAudit,
                correlationId: "corr-org-305"
            ),
            SystemLogEntry(
                id: "system-log-005",
                createdAt: baseDate.addingTimeInterval(-5_400),
                category: .userAccount,
                severity: .info,
                eventType: .userProfileUpdated,
                actorUserId: "user-581",
                actorDisplayName: "Community Member",
                actorRole: .user,
                targetType: .userProfile,
                targetId: "user-581",
                targetTitle: "User Profile",
                outcome: .success,
                summary: "User profile public fields were updated.",
                moduleName: "Profile",
                screenName: "EditProfile",
                operationName: "saveProfile",
                metadata: [
                    "changedFieldCount": "2",
                    "changedFieldGroup": "publicProfile",
                    "source": "selfService"
                ],
                retentionPolicy: .normalAudit,
                correlationId: "corr-user-581-profile"
            ),
            SystemLogEntry(
                id: "system-log-006",
                createdAt: baseDate.addingTimeInterval(-7_200),
                category: .userAccount,
                severity: .critical,
                eventType: .accountBlocked,
                actorUserId: "user-owner-1",
                actorDisplayName: "Platform Owner",
                actorRole: .owner,
                targetType: .account,
                targetId: "user-581",
                targetTitle: "User Account",
                outcome: .blocked,
                summary: "Account access was blocked after policy review.",
                moduleName: "AccountStatus",
                operationName: "blockAccount",
                isReviewed: true,
                reviewedAt: baseDate.addingTimeInterval(-6_900),
                reviewedByUserId: "user-owner-1",
                metadata: [
                    "previousState": "active",
                    "newState": "blocked",
                    "reasonCode": "policyReview"
                ],
                retentionPolicy: .security,
                correlationId: "corr-user-581"
            )
        ]
    }()
}
