import Combine
import FirebaseAuth
import Foundation

enum AuthMultiFactorFlowError: Error, Equatable {
    case secondFactorRequired
    case challengeUnavailable
    case invalidCode
    case unsupportedFactor
    case noCurrentUser
    case emailNotVerified
    case alreadyEnrolled
    case sessionChanged
    case enrollmentNotReleased
}

enum AuthSecurityRollout {
    // Flip only after Identity Platform and TOTP are enabled in production.
    static let allowsTOTPEnrollment = false
}

struct AuthMultiFactorFactor: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String?
    let enrollmentDate: Date
}

protocol AuthMultiFactorSignInChallengeProviding: AnyObject {
    var factors: [AuthMultiFactorFactor] { get }

    func resolve(
        factorID: String,
        oneTimeCode: String
    ) async throws -> any AuthSessionUserProviding
}

extension AuthBackendProviding {
    func multiFactorSignInChallenge(
        from error: Error
    ) -> (any AuthMultiFactorSignInChallengeProviding)? {
        nil
    }
}

private final class FirebaseMultiFactorSignInChallenge: AuthMultiFactorSignInChallengeProviding {
    private let resolver: MultiFactorResolver
    private let factorInfoByID: [String: MultiFactorInfo]

    let factors: [AuthMultiFactorFactor]

    init?(resolver: MultiFactorResolver) {
        let supportedFactors = resolver.hints.filter {
            $0.factorID == PhoneMultiFactorInfo.TOTPMultiFactorID
        }

        guard !supportedFactors.isEmpty else { return nil }

        self.resolver = resolver
        factorInfoByID = Dictionary(uniqueKeysWithValues: supportedFactors.map { ($0.uid, $0) })
        factors = supportedFactors.map {
            AuthMultiFactorFactor(
                id: $0.uid,
                displayName: $0.displayName,
                enrollmentDate: $0.enrollmentDate
            )
        }
    }

    func resolve(
        factorID: String,
        oneTimeCode: String
    ) async throws -> any AuthSessionUserProviding {
        guard factorInfoByID[factorID] != nil else {
            throw AuthMultiFactorFlowError.unsupportedFactor
        }

        let assertion = TOTPMultiFactorGenerator.assertionForSignIn(
            withEnrollmentID: factorID,
            oneTimePassword: oneTimeCode
        )
        return try await resolver.resolveSignIn(with: assertion).user
    }
}

extension FirebaseAuthBackend {
    func multiFactorSignInChallenge(
        from error: Error
    ) -> (any AuthMultiFactorSignInChallengeProviding)? {
        let nsError = error as NSError
        guard AuthErrorCode(rawValue: nsError.code) == .secondFactorRequired,
              let resolver = nsError.userInfo[AuthErrors.userInfoMultiFactorResolverKey]
                as? MultiFactorResolver else {
            return nil
        }

        return FirebaseMultiFactorSignInChallenge(resolver: resolver)
    }
}

final class AuthMultiFactorSignInCoordinator: ObservableObject {
    enum Phase: Equatable {
        case idle
        case awaitingCode
        case resolving
        case failed
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var factors: [AuthMultiFactorFactor] = []
    @Published var selectedFactorID: String?
    @Published private(set) var errorMessage: String?

    var isResolving: Bool { phase == .resolving }

    func begin(factors: [AuthMultiFactorFactor]) {
        self.factors = factors
        selectedFactorID = factors.first?.id
        errorMessage = nil
        phase = .awaitingCode
    }

    func beginResolving() {
        errorMessage = nil
        phase = .resolving
    }

    func fail(message: String) {
        errorMessage = message
        phase = .failed
    }

    func reset() {
        factors = []
        selectedFactorID = nil
        errorMessage = nil
        phase = .idle
    }
}

final class AuthTOTPEnrollmentSession: Identifiable {
    let id = UUID()
    let userID: String
    let sharedSecret: String
    let qrCodeURL: String

    fileprivate let secret: TOTPSecret

    fileprivate init(userID: String, accountName: String, secret: TOTPSecret) {
        self.userID = userID
        self.secret = secret
        sharedSecret = secret.sharedSecretKey()
        qrCodeURL = secret.generateQRCodeURL(
            withAccountName: accountName,
            issuer: "UAC"
        )
    }

    func openInAuthenticator() {
        secret.openInOTPApp(withQRCodeURL: qrCodeURL)
    }
}

@MainActor
final class AuthMultiFactorService {
    static let shared = AuthMultiFactorService()

    private init() {}

    func enrolledTOTPFactors() async throws -> [AuthMultiFactorFactor] {
        let user = try currentVerifiedUser()
        try await user.reload()
        return user.multiFactor.enrolledFactors
            .filter { $0.factorID == PhoneMultiFactorInfo.TOTPMultiFactorID }
            .map {
                AuthMultiFactorFactor(
                    id: $0.uid,
                    displayName: $0.displayName,
                    enrollmentDate: $0.enrollmentDate
                )
            }
    }

    func beginTOTPEnrollment() async throws -> AuthTOTPEnrollmentSession {
        guard AuthSecurityRollout.allowsTOTPEnrollment else {
            throw AuthMultiFactorFlowError.enrollmentNotReleased
        }

        let user = try currentVerifiedUser()
        try await user.reload()
        guard !user.multiFactor.enrolledFactors.contains(where: {
            $0.factorID == PhoneMultiFactorInfo.TOTPMultiFactorID
        }) else {
            throw AuthMultiFactorFlowError.alreadyEnrolled
        }

        let session = try await user.multiFactor.session()
        let secret = try await TOTPMultiFactorGenerator.generateSecret(with: session)
        return AuthTOTPEnrollmentSession(
            userID: user.uid,
            accountName: user.email ?? user.uid,
            secret: secret
        )
    }

    func completeTOTPEnrollment(
        session: AuthTOTPEnrollmentSession,
        oneTimeCode: String
    ) async throws {
        let user = try currentVerifiedUser()
        guard user.uid == session.userID else {
            throw AuthMultiFactorFlowError.sessionChanged
        }

        let code = Self.normalizedCode(oneTimeCode)
        guard Self.isValidCode(code) else {
            throw AuthMultiFactorFlowError.invalidCode
        }

        let assertion = TOTPMultiFactorGenerator.assertionForEnrollment(
            with: session.secret,
            oneTimePassword: code
        )
        try await user.multiFactor.enroll(with: assertion, displayName: "UAC Authenticator")
        _ = try await user.getIDTokenResult(forcingRefresh: true)
    }

    func removeTOTPFactor(id: String) async throws {
        guard AuthSecurityRollout.allowsTOTPEnrollment else {
            throw AuthMultiFactorFlowError.enrollmentNotReleased
        }

        let user = try currentVerifiedUser()
        guard user.multiFactor.enrolledFactors.contains(where: {
            $0.uid == id && $0.factorID == PhoneMultiFactorInfo.TOTPMultiFactorID
        }) else {
            throw AuthMultiFactorFlowError.unsupportedFactor
        }

        try await user.multiFactor.unenroll(withFactorUID: id)
        _ = try await user.getIDTokenResult(forcingRefresh: true)
    }

    static func normalizedCode(_ code: String) -> String {
        code.filter(\.isNumber)
    }

    static func isValidCode(_ code: String) -> Bool {
        code.count == 6 && code.allSatisfy(\.isNumber)
    }

    private func currentVerifiedUser() throws -> User {
        guard let user = Auth.auth().currentUser else {
            throw AuthMultiFactorFlowError.noCurrentUser
        }
        guard user.isEmailVerified else {
            throw AuthMultiFactorFlowError.emailNotVerified
        }
        return user
    }
}
