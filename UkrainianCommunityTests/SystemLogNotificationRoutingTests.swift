import Testing
@testable import UkrainianCommunity

@MainActor
struct SystemLogNotificationRoutingTests {
    @Test func pushKeepsExactJournalDestinationAndLegacyProfileAction() throws {
        let route = try #require(RemoteNotificationRoute(notificationId: "systemLog_test", type: .systemAnnouncement,
            sourceType: .system, sourceId: "log-123", actionType: .openProfile, actionTargetId: "log-123",
            route: "openSystemLog", routeTargetId: "log-123"))
        #expect(route.destination == .openSystemLog(logID: "log-123"))
        #expect(route.actionType == .openProfile)
    }
    @Test func onlyApplicationOwnerCanOpenJournalPushDestination() {
        let owner = MockContentBuilder.ownerUser()
        let user = MockContentBuilder.currentUser()
        #expect(ProfileAccessPolicy(user: owner).allows(.systemLogDetail("log-123")))
        #expect(!ProfileAccessPolicy(user: user).allows(.systemLogDetail("log-123")))
        #expect(!ProfileAccessPolicy(user: nil).allows(.systemLogDetail("log-123")))
    }
}
