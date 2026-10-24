#if DEBUG && targetEnvironment(simulator)
import Foundation

/// A synthetic auth dependency paired with the existing mock UI-test repositories.
/// Not compiled into device/Release builds; it never authenticates against Firebase.
final class UITestOwnerAuthBackend: AuthBackendProviding {
    private var session: UITestOwnerSession?
    private let hasSecondFactor: Bool
    private let delayedFailure: Bool
    var currentSessionUser: (any AuthSessionUserProviding)? { session }

    private init(hasSecondFactor: Bool, uid: String, connectionFailure: Bool, delayedFailure: Bool = false) {
        self.hasSecondFactor = hasSecondFactor
        self.delayedFailure = delayedFailure
        session = delayedFailure ? nil : UITestOwnerSession(uid: uid, connectionFailure: connectionFailure)
    }

    static func makeIfRequested(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> UITestOwnerAuthBackend? {
        guard arguments.contains("-ui-testing") else { return nil }
        if environment["UITestForceSignedOutSession"] == "1", environment["UITestAuthDelayedFailure"] == "1" {
            return UITestOwnerAuthBackend(hasSecondFactor: false, uid: "", connectionFailure: false, delayedFailure: true)
        }
        let fixtureRole = environment["UITestProfileRole"] ?? ""
        let isAdmin = ["admin", "mixed"].contains(fixtureRole)
        guard isAdmin || environment["UITestForceOwnerSession"] == "1" else { return nil }
        return UITestOwnerAuthBackend(hasSecondFactor: environment["UITestOwnerSecondFactor"] != "missing", uid: isAdmin ? fixtureRole + "-1" : "owner-1", connectionFailure: environment["UITestColdStartConnectionFailure"] == "1")
    }

    func isCurrentSessionTOTPAuthenticated() async throws -> Bool {
        if ProcessInfo.processInfo.environment["UITestStartupSecurityDelay"] == "1" {
            try await Task.sleep(for: .seconds(3))
        }
        guard session != nil, session?.isEmailVerified == true else { return false }
        return AuthMultiFactorService.claimsContainTOTPSignIn([
            "firebase": ["sign_in_second_factor": hasSecondFactor ? "totp" : "password"]
        ])
    }

    func signIn(email: String, password: String) async throws -> any AuthSessionUserProviding {
        if delayedFailure {
            try await Task.sleep(for: .seconds(8))
            throw URLError(.notConnectedToInternet)
        }
        throw AppError.permissionDenied
    }
    func createUser(email: String, password: String) async throws -> any AuthSessionUserProviding { throw AppError.permissionDenied }
    func signInAnonymously() async throws -> any AuthSessionUserProviding { throw AppError.permissionDenied }
    func sendPasswordReset(email: String) async throws { throw AppError.permissionDenied }
    func signOut() throws { session = nil }
}

private final class UITestOwnerSession: AuthSessionUserProviding {
    let uid: String
    let connectionFailure: Bool
    init(uid: String, connectionFailure: Bool) {
        self.uid = uid
        self.connectionFailure = connectionFailure
    }
    let email: String? = "owner@example.test"
    let isAnonymous = false
    let isEmailVerified = true
    func reload() async throws {
        if connectionFailure { throw URLError(.notConnectedToInternet) }
    }
    func refreshIDToken() async throws {}
    func sendVerificationEmail() async throws { throw AppError.permissionDenied }
    func updateDisplayName(_ displayName: String) async throws { throw AppError.permissionDenied }
    func deleteAccount() async throws { throw AppError.permissionDenied }
}
#endif
