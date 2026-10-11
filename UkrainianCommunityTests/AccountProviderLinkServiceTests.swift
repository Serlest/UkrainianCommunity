import FirebaseAuth
import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
@Suite("Account provider linking")
struct AccountProviderLinkServiceTests {
    private let credential = GoogleAuthProvider.credential(
        withIDToken: "test-token",
        accessToken: "test-token"
    )
    private let signInDate = Date(timeIntervalSince1970: 1_700_000_000)

    @Test
    func ownerCanLinkProviderWithoutChangingTheAccountID() async throws {
        let state = ownerState()
        let backend = FakeProviderLinkBackend(snapshot: snapshot())
        let service = AccountProviderLinkService(
            authState: state,
            backend: backend,
            now: { signInDate.addingTimeInterval(60) }
        )

        let providers = try await service.link(credential)

        #expect(providers.contains("google.com"))
        #expect(backend.linkedUserIDs == ["owner-a"])
        #expect(state.user?.id == "owner-a")
    }

    @Test
    func ownerCannotLinkWithoutTOTPSession() async {
        let backend = FakeProviderLinkBackend(snapshot: snapshot(isTOTPAuthenticated: false))
        let service = AccountProviderLinkService(
            authState: ownerState(),
            backend: backend,
            now: { signInDate.addingTimeInterval(60) }
        )

        await #expect(throws: AccountProviderLinkError.protectedSessionRequired) {
            try await service.link(credential)
        }
        #expect(backend.linkedUserIDs.isEmpty)
    }

    @Test
    func ownerMustSignInRecentlyBeforeLinking() async {
        let backend = FakeProviderLinkBackend(snapshot: snapshot())
        let service = AccountProviderLinkService(
            authState: ownerState(),
            backend: backend,
            now: { signInDate.addingTimeInterval(11 * 60) }
        )

        await #expect(throws: AccountProviderLinkError.recentSignInRequired) {
            try await service.link(credential)
        }
        #expect(backend.linkedUserIDs.isEmpty)
    }

    @Test
    func anotherFirebaseUserCannotReceiveTheOwnerProvider() async {
        let backend = FakeProviderLinkBackend(snapshot: snapshot(userID: "another-user"))
        let service = AccountProviderLinkService(
            authState: ownerState(),
            backend: backend,
            now: { signInDate.addingTimeInterval(60) }
        )

        await #expect(throws: AccountProviderLinkError.sessionChanged) {
            try await service.link(credential)
        }
        #expect(backend.linkedUserIDs.isEmpty)
    }

    private func ownerState() -> AuthState {
        let state = AuthState()
        state.setAuthenticatedSession(user: AppUser(
            id: "owner-a",
            fullName: "Owner",
            displayName: "Owner",
            city: "Vienna",
            email: "owner@example.com",
            bio: "",
            role: .user,
            globalRole: .owner,
            requiresMultiFactorAuth: true,
            blockState: .active,
            createdAt: .now,
            updatedAt: .now
        ))
        return state
    }

    private func snapshot(
        userID: String = "owner-a",
        isTOTPAuthenticated: Bool = true
    ) -> AccountProviderLinkSnapshot {
        AccountProviderLinkSnapshot(
            userID: userID,
            providerIDs: ["password"],
            authenticatedAt: signInDate,
            isEmailVerified: true,
            isTOTPAuthenticated: isTOTPAuthenticated
        )
    }
}

private final class FakeProviderLinkBackend: AccountProviderLinkBackend {
    var current: AccountProviderLinkSnapshot
    private(set) var linkedUserIDs: [String] = []

    init(snapshot: AccountProviderLinkSnapshot) {
        current = snapshot
    }

    func snapshot() async throws -> AccountProviderLinkSnapshot {
        current
    }

    func link(
        credential: AuthCredential,
        expectedUserID: String
    ) async throws -> AccountProviderLinkSnapshot {
        linkedUserIDs.append(expectedUserID)
        current = AccountProviderLinkSnapshot(
            userID: expectedUserID,
            providerIDs: current.providerIDs.union([credential.provider]),
            authenticatedAt: current.authenticatedAt,
            isEmailVerified: current.isEmailVerified,
            isTOTPAuthenticated: current.isTOTPAuthenticated
        )
        return current
    }
}
