import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct SystemLogExplanationTests {
    @Test func knownFailureExplainsActionWithoutExposingRawCode() {
        let log = entry(code: "network.connectionLost", operation: "getBlockedOrganizations")
        #expect(SystemLogExplanation.title(log) != log.summary)
        #expect(!SystemLogExplanation.title(log).contains("network.connectionLost"))
        #expect(SystemLogExplanation.action(log) == SystemLogExplanation.text("action.getBlockedOrganizations"))
        #expect(SystemLogExplanation.cause(log) == SystemLogExplanation.text("connection.cause"))
    }

    @Test func permissionFailureDoesNotClaimDeletionAsProvenCause() {
        let log = entry(code: "firestore.permissionDenied", operation: "listenEventComments")
        #expect(SystemLogExplanation.kind(log) == "permission")
        #expect(SystemLogExplanation.cause(log) == SystemLogExplanation.text("permission.cause"))
        #expect(SystemLogExplanation.action(log) == SystemLogExplanation.text("action.listenEventComments"))
    }

    @Test func newUnknownCodeDoesNotInventAnExplanation() {
        let log = entry(code: "future.error.99", operation: "newOperation")
        #expect(SystemLogExplanation.kind(log) == "unknown")
        #expect(SystemLogExplanation.cause(log) == SystemLogExplanation.text("unknown.cause"))
        #expect(SystemLogExplanation.action(log).contains("newOperation"))
    }

    @Test func timeoutDoesNotAssertWriteFailedOrRecommendBlindRetry() {
        let log = entry(code: "cloudFunctions.deadlineExceeded", operation: "deleteOwnAccount")
        #expect(SystemLogExplanation.kind(log) == "timeout")
        #expect(SystemLogExplanation.nextStep(log) == SystemLogExplanation.text("network.next"))
    }

    @Test func successfulAuditKeepsItsEventTitle() {
        let log = SystemLogEntry(id: "audit", createdAt: Date(), category: .audit,
            severity: .info, eventType: .contentDeleted, actorRole: .owner,
            targetType: .organization, outcome: .success, summary: "Organization deleted")
        #expect(!SystemLogExplanation.isFailure(log))
        #expect(SystemLogExplanation.title(log) == SystemLogDisplayFormatting.summaryTitle(log.summary))
    }

    private func entry(code: String, operation: String) -> SystemLogEntry {
        SystemLogEntry(id: "error", createdAt: Date(), category: .diagnostics,
            severity: .warning, eventType: .technicalError, actorRole: .user,
            targetType: .userProfile, outcome: .failed,
            summary: "Technical failure in CloudFunctions.\(operation)", errorCode: code,
            moduleName: "CloudFunctions", operationName: operation)
    }
}

extension SystemLogExplanationTests {
    @Test func everyCallableHasAHumanActionInsteadOfAnUnknownPlaceholder() {
        for function in CloudFunctionName.allCases {
            let log = SystemLogEntry(id: "call", createdAt: Date(), category: .diagnostics,
                severity: .warning, eventType: .technicalError, actorRole: .user,
                targetType: .none, outcome: .failed, summary: "Technical failure",
                errorCode: "cloudFunctions.failedPrecondition", moduleName: "CloudFunctions", operationName: function.rawValue)
            #expect(SystemLogExplanation.action(log) != SystemLogExplanation.text("action.unknown"), "Callable: \(function.rawValue)")
            #expect(!SystemLogExplanation.action(log).hasPrefix(SystemLogExplanation.text("action.technical")), "Callable: \(function.rawValue)")
        }
    }

    @Test func historicalAnalyticsAndBannerFailuresExposeTheirActualPurpose() {
        let analytics = SystemLogEntry(id: "old", createdAt: Date(), category: .diagnostics,
            severity: .warning, eventType: .technicalError, actorRole: .user, targetType: .none,
            summary: "Technical failure", errorCode: "cloudFunctions.failedPrecondition", moduleName: "Analytics", operationName: "deliverAggregate")
        #expect(SystemLogExplanation.title(analytics) == SystemLogExplanation.text("background.title"))
        #expect(SystemLogExplanation.impact(analytics) == SystemLogExplanation.text("impact.analytics"))
        let banner = SystemLogEntry(id: "banner", createdAt: Date(), category: .diagnostics,
            severity: .error, eventType: .technicalError, actorRole: .owner, targetType: .systemConfiguration,
            summary: "Technical failure", errorCode: "UkrainianCommunity_AppError.2", moduleName: "FeaturedBanners", operationName: "decodeOwnerBanner")
        #expect(SystemLogExplanation.kind(banner) == "parsing")
        #expect(SystemLogExplanation.impact(banner) == SystemLogExplanation.text("impact.bannerDecode"))
    }

    @Test func knownReasonAndResponseStageExplainDifferentOutcomes() {
        let log = SystemLogEntry(id: "known", createdAt: Date(), category: .diagnostics,
            severity: .warning, eventType: .technicalError, actorRole: .user, targetType: .none,
            summary: "Technical failure", errorCode: "cloudFunctions.failedPrecondition", operationName: "registerForEvent",
            metadata: ["diagnosticReason": "analyticsConsentRequired", "failureStage": "decodeResponse"])
        #expect(SystemLogExplanation.cause(log) == SystemLogExplanation.text("reason.analyticsConsentRequired"))
        #expect(SystemLogExplanation.impact(log) == SystemLogExplanation.text("impact.decodeResponse"))
    }
}

extension SystemLogExplanationTests {
    @Test func notificationAndOrganizationReadFailuresExplainWhatWasNotLoaded() {
        for (module, operation, key) in [("Notifications", "listenNotifications", "impact.notificationInbox"), ("Notifications", "fetchUnreadCount", "impact.notificationBadge"), ("Organizations", "listenOrganizationRequests", "impact.organizationRequests")] {
            let log = SystemLogEntry(id: "read", createdAt: .now, category: .diagnostics, severity: .warning,
                eventType: .technicalError, actorRole: .user, targetType: .none, summary: "Read failed",
                errorCode: "firestore.permissionDenied", moduleName: module, operationName: operation)
            #expect(SystemLogExplanation.impact(log) == SystemLogExplanation.text(key))
            #expect(SystemLogExplanation.action(log) != SystemLogExplanation.text("action.unknown"))
        }
    }
}
