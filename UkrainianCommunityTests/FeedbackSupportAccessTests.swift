import Testing
@testable import UkrainianCommunity

@MainActor struct FeedbackSupportAccessTests {
    @Test func repeatedNotificationRoutesCreateFreshPresentationForSameFeedback() {
        // Returning from a conversation leaves its parent route on the stack.
        // A later push for the same thread must reopen it, rather than reuse
        // that parent's already-handled initialFeedbackID state.
        #expect(ProfileNavigationRoute.feedbackDetail(feedbackID: "case") != .feedbackDetail(feedbackID: "case"))
        #expect(ProfileNavigationRoute.myFeedbackDetail(userID: "member", feedbackID: "case") != .myFeedbackDetail(userID: "member", feedbackID: "case"))
        #expect(ProfileNavigationRoute.notifications.hidesRootTabBar)
    }

    @Test func everyRoleHasExpectedSupportRoutesAndOwnHistoryScope() {
        for (name, globalRole, state) in [("owner", "owner", "active"), ("admin", "admin", "active"),
            ("org-owner", "user", "active"), ("org-admin", "user", "active"), ("org-editor", "user", "active"),
            ("member", "user", "active"), ("warned", "user", "warned"), ("restricted", "user", "bannedPermanent")] {
            let user = UserManagementViewModel.makeUser(id: name, data: ["globalRole": globalRole, "accountStatus": state, "blockState": state])
            let policy = ProfileAccessPolicy(user: user)
            let management = ["owner", "admin"].contains(globalRole) && state == "active"
            #expect(policy.allows(.feedbackInbox) == management)
            #expect(policy.allows(.feedbackDetail(feedbackID: "case")) == management)
            #expect(policy.allows(.feedbackComposer) == (globalRole != "owner" && state != "bannedPermanent"))
            #expect(policy.allows(.myFeedback(userID: name)) == (globalRole != "owner"))
            #expect(!policy.allows(.myFeedback(userID: "another")))
            #expect(!policy.allows(.myFeedbackDetail(userID: "another", feedbackID: "case")))
        }
        let guest = ProfileAccessPolicy(user: nil)
        #expect(!guest.allows(.feedbackInbox))
        #expect(!guest.allows(.feedbackComposer))
        #expect(!guest.allows(.myFeedback(userID: "member")))
    }
}
