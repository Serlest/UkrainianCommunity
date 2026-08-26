import Foundation
import SwiftUI
import UIKit
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

    @Test(arguments: [
        "Wed, 26 Aug 2026 07:39:07 GMT",
        "2026-08-26T07:39:07Z",
        "2026-08-26T07:39:07.000Z",
        "2026-08-26T09:39:07+02:00"
    ])
    func managedUserMetadataDecodesServerDateFormats(_ lastSignIn: String) throws {
        // UTC-string fixture matches the installed Firebase Admin SDK and the
        // read-only production date sample; no account identifiers are retained.
        let payload: [String: Any] = [
            "targetUserId": "date-format-test", "emailVerified": true, "authDisabled": false,
            "creationTime": "Tue, 26 May 2026 20:59:31 GMT",
            "lastSignInTime": lastSignIn, "providerIds": ["password"]
        ]
        let response = try JSONDecoder().decode(
            ManagedUserSecurityMetadataFunctionResponse.self,
            from: JSONSerialization.data(withJSONObject: payload)
        )
        let metadata = ManagedUserSecurityMetadata(response: response)
        #expect(metadata.lastSignInTime == Date(timeIntervalSince1970: 1_787_729_947))
        #expect(metadata.creationTime == Date(timeIntervalSince1970: 1_779_829_171))
        #expect(metadata.emailVerified)
        #expect(!metadata.authDisabled)
        #expect(metadata.providerIDs == ["password"])
    }

    @Test(arguments: [nil, "", "not a date"] as [String?])
    func managedUserMetadataDoesNotInventMissingOrInvalidDates(_ value: String?) {
        let response = ManagedUserSecurityMetadataFunctionResponse(
            targetUserId: "date-format-test", emailVerified: false, authDisabled: false,
            creationTime: value, lastSignInTime: value, providerIds: []
        )
        let metadata = ManagedUserSecurityMetadata(response: response)
        #expect(metadata.creationTime == nil)
        #expect(metadata.lastSignInTime == nil)
    }

    @Test(arguments: [320.0, 390.0, 768.0], [false, true])
    func managedUserCardsRenderWithConsistentStructure(width: Double, accessibilityText: Bool) throws {
        let createdAt = Date(timeIntervalSince1970: 1_787_729_947)
        let users = [
            ("Short Name", "short@example.org", "", [CommunityRole]()),
            ("Organization Admin", "admin@example.org", "", [.communityAdmin]),
            ("A Long Display Name With Several Organization Roles", "long.address.for.layout@example.org", "Innsbruck", [.communityOwner, .communityAdmin, .communityModerator]),
            ("Member", "member@example.org", "Wien", [CommunityRole]())
        ].enumerated().map { index, item in
            let user = AppUser(
                id: "layout-user-\(index)", fullName: item.0, displayName: item.0,
                city: item.2, email: item.1, bio: "", role: .user,
                globalRole: .user, blockState: .active, createdAt: createdAt, updatedAt: createdAt
            )
            let roles = item.3.enumerated().map { roleIndex, role in
                UserOrganizationRole(
                    organization: ManagedOrganization(
                        id: "layout-org-\(roleIndex)", name: "Organization \(roleIndex)",
                        city: "Innsbruck", logoURL: nil, ownerId: nil, adminIds: [], moderatorIds: []
                    ), role: role
                )
            }
            return (user: user, roles: roles)
        }
        let content = VStack(spacing: 16) {
            ForEach(users, id: \.user.id) { item in
                ManagedUserRow(user: item.user, organizationRoles: item.roles)
            }
        }
        .padding(16)
        .frame(width: width)
        .background(Color(uiColor: .systemGroupedBackground))
        .environment(\.colorScheme, .light)
        .environment(\.dynamicTypeSize, accessibilityText ? .accessibility3 : .large)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        let image = try #require(renderer.uiImage)
        #expect(image.cgImage?.width == Int(width))
        Attachment.record(image, named: "managed-users-\(Int(width))-\(accessibilityText ? "large-text" : "standard").png")
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
