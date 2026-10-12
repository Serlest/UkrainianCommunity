import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
@Suite("Legal notification routing")
struct LegalNotificationRoutingTests {
    @Test
    func requiredReviewSuppressesOnlyThePendingLegalUpdateRoute() throws {
        let coordinator = RemoteNotificationRouteCoordinator()
        let legalRoute = try #require(RemoteNotificationRoute(userInfo: [
            "type": "legalDocumentsUpdated",
            "notificationId": "legal-terms-2026.14",
            "sourceType": "legal",
            "sourceId": "terms",
            "actionType": "openLegalDocuments",
            "actionTargetId": "terms"
        ]))
        let otherRoute = try #require(RemoteNotificationRoute(userInfo: [
            "type": "eventUpdated",
            "notificationId": "event-1",
            "sourceType": "event",
            "sourceId": "event-1",
            "actionType": "openEvent",
            "actionTargetId": "event-1"
        ]))

        coordinator.receive(legalRoute)
        #expect(!coordinator.shouldSkipNavigation(for: legalRoute))
        coordinator.markLegalRouteHandledByRequiredReview(reviewedDocumentTypes: [.terms])
        #expect(coordinator.shouldSkipNavigation(for: legalRoute))
        #expect(coordinator.shouldMarkRead(for: legalRoute))
        // Cold launch can deliver the same push through two app-delegate callbacks.
        coordinator.receive(legalRoute)
        #expect(coordinator.shouldSkipNavigation(for: legalRoute))
        coordinator.consume(legalRoute)
        #expect(coordinator.pendingRoute == nil)
        #expect(!coordinator.shouldSkipNavigation(for: legalRoute))

        coordinator.receive(otherRoute)
        coordinator.markLegalRouteHandledByRequiredReview(reviewedDocumentTypes: [.terms])
        #expect(!coordinator.shouldSkipNavigation(for: otherRoute))
        #expect(coordinator.shouldMarkRead(for: otherRoute))
        #expect(coordinator.pendingRoute == otherRoute)
    }

    @Test
    func laterLegalNotificationCanStillOpenNormally() throws {
        let coordinator = RemoteNotificationRouteCoordinator()
        let olderRoute = try #require(RemoteNotificationRoute(userInfo: [
            "type": "legalDocumentsUpdated",
            "notificationId": "legal-terms-2026.14",
            "sourceType": "legal",
            "sourceId": "terms",
            "actionType": "openLegalDocuments",
            "actionTargetId": "terms"
        ]))
        let laterRoute = try #require(RemoteNotificationRoute(userInfo: [
            "type": "legalDocumentsUpdated",
            "notificationId": "legal-privacy-2026.20",
            "sourceType": "legal",
            "sourceId": "privacy",
            "actionType": "openLegalDocuments",
            "actionTargetId": "privacy"
        ]))

        coordinator.receive(olderRoute)
        coordinator.markLegalRouteHandledByRequiredReview(reviewedDocumentTypes: [.terms])
        coordinator.receive(laterRoute)

        #expect(!coordinator.shouldSkipNavigation(for: laterRoute))
        #expect(coordinator.pendingRoute == laterRoute)
    }

    @Test
    func unrelatedLegalDocumentRemainsUnreadForLaterReview() throws {
        let coordinator = RemoteNotificationRouteCoordinator()
        let organizationRulesRoute = try #require(RemoteNotificationRoute(userInfo: [
            "type": "legalDocumentsUpdated",
            "notificationId": "legal-organization-rules-2026.11",
            "sourceType": "legal",
            "sourceId": "organizationRules",
            "actionType": "openLegalDocuments",
            "actionTargetId": "organizationRules"
        ]))

        coordinator.receive(organizationRulesRoute)
        coordinator.markLegalRouteHandledByRequiredReview(reviewedDocumentTypes: [.terms, .privacy])

        #expect(coordinator.shouldSkipNavigation(for: organizationRulesRoute))
        #expect(!coordinator.shouldMarkRead(for: organizationRulesRoute))
    }
}
