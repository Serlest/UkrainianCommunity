import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
@Suite("Auth security")
struct AuthSecurityTests {
    @Test
    func loginAcceptsAnyNonEmptyExistingPassword() {
        let service = AuthValidationService()

        #expect(service.validateLogin(email: "member@example.org", password: "x").isEmpty)
        #expect(
            service.validateLogin(email: "member@example.org", password: "")
                == [AppStrings.Validation.authPasswordRequired]
        )
    }

    @Test
    func newPasswordPolicyUsesLengthWithoutCompositionRules() {
        let policy = AuthPasswordPolicy.current

        #expect(policy.validationError(for: "123456789") == AppStrings.Validation.authPasswordTooShort)
        #expect(policy.validationError(for: "long phrase") == nil)
        #expect(
            policy.validationError(for: String(repeating: "a", count: 129))
                == AppStrings.Validation.authPasswordTooLong
        )
    }

    @Test
    func totpCodesAreNormalizedAndRequireExactlySixDigits() {
        #expect(AuthMultiFactorService.normalizedCode("12 34-56") == "123456")
        #expect(AuthMultiFactorService.isValidCode("123456"))
        #expect(!AuthMultiFactorService.isValidCode("12345"))
        #expect(!AuthMultiFactorService.isValidCode("12345a"))
    }

    @Test
    func totpEnrollmentIsOpenForStagedPrivilegedRollout() {
        #expect(AuthSecurityRollout.allowsTOTPEnrollment)
    }

    @Test
    func stagedRolloutGuidesEveryPrivilegedAccountThroughPerAccountActivation() {
        let unprotectedOwner = makeUser(globalRole: .owner)
        let protectedOwner = makeUser(globalRole: .owner, requiresMultiFactorAuth: true)
        let protectedAdmin = makeUser(globalRole: .admin, requiresMultiFactorAuth: true)

        #expect(AuthSecurityPolicy.requiresProtectedSession(unprotectedOwner))
        #expect(AuthSecurityPolicy.requiresProtectedSession(protectedOwner))
        #expect(AuthSecurityPolicy.requiresProtectedSession(protectedAdmin))
        #expect(
            !AuthSecurityPolicy.protectedSessionIsReady(
                user: unprotectedOwner,
                isTOTPAuthenticated: true
            )
        )
    }

    @Test
    func staleProtectionFieldDoesNotRestrictOrdinaryUsers() {
        let ordinaryUser = makeUser(globalRole: .user, requiresMultiFactorAuth: true)

        #expect(!AuthSecurityPolicy.requiresProtectedSession(ordinaryUser))
        #expect(
            AuthSecurityPolicy.protectedSessionIsReady(
                user: ordinaryUser,
                isTOTPAuthenticated: false
            )
        )
    }

    @Test
    func protectedPrivilegedSessionRequiresTOTPSignIn() {
        let protectedOwner = makeUser(globalRole: .owner, requiresMultiFactorAuth: true)

        #expect(
            !AuthSecurityPolicy.protectedSessionIsReady(
                user: protectedOwner,
                isTOTPAuthenticated: false
            )
        )
        #expect(
            AuthSecurityPolicy.protectedSessionIsReady(
                user: protectedOwner,
                isTOTPAuthenticated: true
            )
        )
        #expect(!AuthSecurityPolicy.canRemoveLastTOTPFactor(for: protectedOwner))
    }

    @Test
    func totpSessionClaimUsesFirebaseSecondFactorMarker() {
        #expect(
            AuthMultiFactorService.claimsContainTOTPSignIn([
                "firebase": ["sign_in_second_factor": "totp"]
            ])
        )
        #expect(
            !AuthMultiFactorService.claimsContainTOTPSignIn([
                "firebase": ["sign_in_second_factor": "phone"]
            ])
        )
        #expect(!AuthMultiFactorService.claimsContainTOTPSignIn([:]))
    }

    private func makeUser(
        globalRole: GlobalRole,
        requiresMultiFactorAuth: Bool = false
    ) -> AppUser {
        AppUser(
            id: "security-user",
            fullName: "Security User",
            displayName: "Security User",
            city: "Vienna",
            email: "security@example.com",
            bio: "",
            role: .user,
            globalRole: globalRole,
            requiresMultiFactorAuth: requiresMultiFactorAuth,
            blockState: .active,
            createdAt: .now,
            updatedAt: .now
        )
    }
}
