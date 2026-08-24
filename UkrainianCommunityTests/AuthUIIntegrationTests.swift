import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct AuthUIIntegrationTests {
    @Test func authLifecycleUsesPhaseRichTaskKeysButStableIdentityResetKeys() {
        let authenticatingKey = ContentAuthLifecyclePolicy.taskKey(
            sessionState: .authenticating,
            authenticatedUserID: nil,
            pendingSessionUserID: "user-a",
            pendingVerificationEmail: "member@example.com"
        )
        let verificationKey = ContentAuthLifecyclePolicy.taskKey(
            sessionState: .verificationPending,
            authenticatedUserID: nil,
            pendingSessionUserID: "user-a",
            pendingVerificationEmail: "member@example.com"
        )
        let unavailableKey = ContentAuthLifecyclePolicy.taskKey(
            sessionState: .sessionUnavailable,
            authenticatedUserID: nil,
            pendingSessionUserID: "user-a",
            pendingVerificationEmail: "member@example.com"
        )

        #expect(authenticatingKey != verificationKey)
        #expect(verificationKey != unavailableKey)
        let transientStates: [AuthSessionState] = [
            .restoring,
            .authenticating,
            .verificationPending,
            .sessionUnavailable,
            .guest
        ]
        for state in transientStates {
            #expect(ContentAuthLifecyclePolicy.identityResetKey(
                sessionState: state,
                authenticatedUserID: nil
            ) == "guest")
        }
        #expect(ContentAuthLifecyclePolicy.identityResetKey(
            sessionState: .authenticated,
            authenticatedUserID: "user-a"
        ) == "authenticated:user-a")
    }

    @Test func pendingNotificationRoutesWaitForStableAuthPhases() {
        #expect(ContentAuthLifecyclePolicy.canHandlePendingRoute(in: .guest))
        #expect(ContentAuthLifecyclePolicy.canHandlePendingRoute(in: .authenticated))
        #expect(!ContentAuthLifecyclePolicy.canHandlePendingRoute(in: .restoring))
        #expect(!ContentAuthLifecyclePolicy.canHandlePendingRoute(in: .authenticating))
        #expect(!ContentAuthLifecyclePolicy.canHandlePendingRoute(in: .verificationPending))
        #expect(!ContentAuthLifecyclePolicy.canHandlePendingRoute(in: .sessionUnavailable))
    }

    @Test func accountStatusUpdatePreservesAuthoritativeProfileFields() {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let updatedAt = Date(timeIntervalSince1970: 1_700_100_000)
        let acceptedTermsAt = Date(timeIntervalSince1970: 1_700_010_000)
        let acceptedPrivacyAt = Date(timeIntervalSince1970: 1_700_020_000)
        let memberships = [
            CommunityMembership(organizationId: "org-a", role: .communityAdmin),
            CommunityMembership(organizationId: "org-b", role: .member)
        ]
        let user = AppUser(
            id: "user-a",
            fullName: "Full Name",
            displayName: "Display Name",
            city: "Vienna",
            email: "member@example.com",
            avatarURL: URL(string: "https://example.com/avatar.png"),
            bio: "Biography",
            telegramUsername: "member",
            role: .admin,
            globalRole: .owner,
            moderatorSections: [.news, .events],
            blockState: .active,
            accountStatus: .active,
            communityMemberships: memberships,
            selectedFederalState: .wien,
            acceptedTermsAt: acceptedTermsAt,
            acceptedPrivacyAt: acceptedPrivacyAt,
            acceptedTermsVersion: "terms-v2",
            acceptedPrivacyVersion: "privacy-v3",
            termsVersion: "legacy-terms-v1",
            privacyVersion: "legacy-privacy-v1",
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        let statusUpdatedAt = Date(timeIntervalSince1970: 1_700_200_000)
        let update = AccountStatusSnapshotUpdate(
            blockState: .suspendedUntil,
            accountStatus: .suspendedUntil,
            banExpiresAt: Date(timeIntervalSince1970: 1_700_300_000),
            warningCount: 2,
            statusReason: "Policy violation",
            statusMessage: "Review the community rules",
            statusUpdatedAt: statusUpdatedAt,
            statusUpdatedBy: "moderator-a",
            statusAcknowledgedAt: nil
        )

        let merged = update.applying(to: user)

        #expect(merged.blockState == .suspendedUntil)
        #expect(merged.accountStatus == .suspendedUntil)
        #expect(merged.statusUpdatedAt == statusUpdatedAt)
        #expect(merged.communityMemberships == memberships)
        #expect(merged.fullName == user.fullName)
        #expect(merged.displayName == user.displayName)
        #expect(merged.globalRole == user.globalRole)
        #expect(merged.moderatorSections == user.moderatorSections)
        #expect(merged.selectedFederalState == user.selectedFederalState)
        #expect(merged.acceptedTermsAt == acceptedTermsAt)
        #expect(merged.acceptedPrivacyAt == acceptedPrivacyAt)
        #expect(merged.acceptedTermsVersion == "terms-v2")
        #expect(merged.acceptedPrivacyVersion == "privacy-v3")
        #expect(merged.createdAt == createdAt)
        #expect(merged.updatedAt == updatedAt)
    }
}
