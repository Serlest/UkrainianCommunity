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
    func totpEnrollmentStaysClosedUntilServerRollout() {
        #expect(!AuthSecurityRollout.allowsTOTPEnrollment)
    }
}
