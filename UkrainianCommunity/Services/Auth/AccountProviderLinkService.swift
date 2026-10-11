import FirebaseAuth
import Foundation

enum AccountProviderLinkError: Error, Equatable {
    case unavailable
    case sessionChanged
    case emailNotVerified
    case protectedSessionRequired
    case recentSignInRequired
    case alreadyLinked
    case unsupportedProvider
    case linkNotConfirmed
}

struct AccountProviderLinkSnapshot: Equatable {
    let userID: String
    let providerIDs: Set<String>
    let authenticatedAt: Date
    let isEmailVerified: Bool
    let isTOTPAuthenticated: Bool
}

protocol AccountProviderLinkBackend {
    func snapshot() async throws -> AccountProviderLinkSnapshot
    func link(
        credential: AuthCredential,
        expectedUserID: String
    ) async throws -> AccountProviderLinkSnapshot
}

final class FirebaseAccountProviderLinkBackend: AccountProviderLinkBackend {
    func snapshot() async throws -> AccountProviderLinkSnapshot {
        guard let user = Auth.auth().currentUser else {
            throw AccountProviderLinkError.unavailable
        }
        let token = try await user.getIDTokenResult(forcingRefresh: true)
        guard Auth.auth().currentUser?.uid == user.uid else {
            throw AccountProviderLinkError.sessionChanged
        }
        return AccountProviderLinkSnapshot(
            userID: user.uid,
            providerIDs: Set(user.providerData.map(\.providerID)),
            authenticatedAt: token.authDate,
            isEmailVerified: user.isEmailVerified,
            isTOTPAuthenticated: AuthMultiFactorService.claimsContainTOTPSignIn(token.claims)
        )
    }

    func link(
        credential: AuthCredential,
        expectedUserID: String
    ) async throws -> AccountProviderLinkSnapshot {
        guard let user = Auth.auth().currentUser, user.uid == expectedUserID else {
            throw AccountProviderLinkError.sessionChanged
        }
        let result = try await user.link(with: credential)
        guard result.user.uid == expectedUserID,
              Auth.auth().currentUser?.uid == expectedUserID else {
            throw AccountProviderLinkError.sessionChanged
        }
        try await result.user.reload()
        return try await snapshot()
    }
}

@MainActor
final class AccountProviderLinkService {
    static let shared = AccountProviderLinkService(
        authState: AuthService.shared.authState,
        backend: FirebaseAccountProviderLinkBackend()
    )

    private let authState: AuthState
    private let backend: any AccountProviderLinkBackend
    private let now: () -> Date
    private let recentSignInWindow: TimeInterval = 10 * 60

    init(
        authState: AuthState,
        backend: any AccountProviderLinkBackend,
        now: @escaping () -> Date = Date.init
    ) {
        self.authState = authState
        self.backend = backend
        self.now = now
    }

    func linkedProviderIDs() async throws -> Set<String> {
        let account = try currentAccount()
        let snapshot = try await backend.snapshot()
        guard snapshot.userID == account.id,
              authState.user?.id == account.id else {
            throw AccountProviderLinkError.sessionChanged
        }
        return snapshot.providerIDs
    }

    func link(_ credential: AuthCredential) async throws -> Set<String> {
        guard ["apple.com", "google.com"].contains(credential.provider) else {
            throw AccountProviderLinkError.unsupportedProvider
        }
        let account = try currentAccount()
        let before = try await backend.snapshot()
        guard before.userID == account.id,
              authState.user?.id == account.id else {
            throw AccountProviderLinkError.sessionChanged
        }
        guard before.isEmailVerified else {
            throw AccountProviderLinkError.emailNotVerified
        }
        guard !before.providerIDs.contains(credential.provider) else {
            throw AccountProviderLinkError.alreadyLinked
        }

        if AuthSecurityPolicy.isPrivilegedAccount(account) {
            guard AuthSecurityPolicy.protectedSessionIsReady(
                user: account,
                isTOTPAuthenticated: before.isTOTPAuthenticated
            ) else {
                throw AccountProviderLinkError.protectedSessionRequired
            }
            let elapsed = now().timeIntervalSince(before.authenticatedAt)
            guard (0...recentSignInWindow).contains(elapsed) else {
                throw AccountProviderLinkError.recentSignInRequired
            }
        }

        let after = try await backend.link(
            credential: credential,
            expectedUserID: account.id
        )
        guard after.userID == account.id,
              authState.user?.id == account.id else {
            throw AccountProviderLinkError.sessionChanged
        }
        guard after.providerIDs.contains(credential.provider) else {
            throw AccountProviderLinkError.linkNotConfirmed
        }
        return after.providerIDs
    }

    private func currentAccount() throws -> AppUser {
        guard authState.isAuthenticated, let account = authState.user else {
            throw AccountProviderLinkError.unavailable
        }
        return account
    }
}
