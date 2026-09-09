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
        #expect(SystemLogExplanation.action(log) == SystemLogExplanation.text("action.unknown"))
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
