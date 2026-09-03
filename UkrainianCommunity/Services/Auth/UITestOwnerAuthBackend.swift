#if DEBUG && targetEnvironment(simulator)
import Foundation

/// A synthetic auth dependency paired with the existing mock UI-test repositories.
/// Not compiled into device/Release builds; it never authenticates against Firebase.
final class UITestOwnerAuthBackend: AuthBackendProviding {
    private var session: UITestOwnerSession? = UITestOwnerSession()
    private let hasSecondFactor: Bool
    var currentSessionUser: (any AuthSessionUserProviding)? { session }

    private init(hasSecondFactor: Bool) { self.hasSecondFactor = hasSecondFactor }

    static func makeIfRequested(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> UITestOwnerAuthBackend? {
        guard arguments.contains("-ui-testing"), environment["UITestForceOwnerSession"] == "1" else { return nil }
        return UITestOwnerAuthBackend(hasSecondFactor: environment["UITestOwnerSecondFactor"] != "missing")
    }

    func isCurrentSessionTOTPAuthenticated() async throws -> Bool {
        guard session?.uid == "owner-1", session?.isEmailVerified == true else { return false }
        return AuthMultiFactorService.claimsContainTOTPSignIn([
            "firebase": ["sign_in_second_factor": hasSecondFactor ? "totp" : "password"]
        ])
    }

    func signIn(email: String, password: String) async throws -> any AuthSessionUserProviding { throw AppError.permissionDenied }
    func createUser(email: String, password: String) async throws -> any AuthSessionUserProviding { throw AppError.permissionDenied }
    func signInAnonymously() async throws -> any AuthSessionUserProviding { throw AppError.permissionDenied }
    func sendPasswordReset(email: String) async throws { throw AppError.permissionDenied }
    func signOut() throws { session = nil }
}

private final class UITestOwnerSession: AuthSessionUserProviding {
    let uid = "owner-1"
    let email: String? = "owner@example.test"
    let isAnonymous = false
    let isEmailVerified = true
    func reload() async throws {}
    func refreshIDToken() async throws {}
    func sendVerificationEmail() async throws { throw AppError.permissionDenied }
    func updateDisplayName(_ displayName: String) async throws { throw AppError.permissionDenied }
    func deleteAccount() async throws { throw AppError.permissionDenied }
}
#endif
