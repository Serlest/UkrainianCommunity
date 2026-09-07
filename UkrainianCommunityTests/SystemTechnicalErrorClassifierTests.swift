import FirebaseFunctions
import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct SystemTechnicalErrorClassifierTests {
    private let context = SystemTechnicalErrorContext(moduleName: "CloudFunctions", operationName: "getBlockedOrganizations")

    @Test func distinguishesMFAFromOtherPreconditions() {
        let mfa = NSError(domain: FunctionsErrorDomain, code: 9, userInfo: [NSLocalizedDescriptionKey: "A TOTP-authenticated session is required for this privileged account."])
        #expect(SystemTechnicalErrorClassifier.classify(mfa, context: context).errorCode == "cloudFunctions.mfaRequired")
        #expect(OrganizationBlockingCoordinator.failureMessage(mfa) == AppStrings.Safety.organizationBlockMFARequired)
        let other = NSError(domain: FunctionsErrorDomain, code: 9, userInfo: [NSLocalizedDescriptionKey: "Unrelated precondition"])
        #expect(SystemTechnicalErrorClassifier.classify(other, context: context).errorCode == "cloudFunctions.failedPrecondition")
        #expect(!SystemTechnicalErrorClassifier.isPrivilegedMFAFailure(other))
    }

    @Test func preservesTLSCauseWithoutPrivatePayload() {
        let cause = NSError(domain: "kCFErrorDomainCFNetwork", code: -1200, userInfo: ["_kCFStreamErrorCodeKey": -9824, "_kCFStreamErrorDomainKey": 3, NSLocalizedDescriptionKey: "private@example.com bearer secret", NSURLErrorFailingURLErrorKey: URL(string: "https://example.com/private?token=secret")!])
        let error = NSError(domain: NSURLErrorDomain, code: -1200, userInfo: [NSUnderlyingErrorKey: cause])
        let result = SystemTechnicalErrorClassifier.classify(error, context: context)
        #expect(result.errorCode == "network.secureConnectionFailed")
        #expect(result.metadata["underlying1Code"] == "-1200")
        #expect(result.metadata["underlying1_kCFStreamErrorCodeKey"] == "-9824")
        #expect(!String(describing: result).contains("secret"))
        #expect(!String(describing: result).contains("example.com"))
        #expect(OrganizationBlockingCoordinator.failureMessage(error) == AppStrings.Safety.organizationBlockTLSFailed)
    }

    @Test func limitsUnderlyingChain() {
        var error = NSError(domain: NSURLErrorDomain, code: -1001)
        for _ in 0..<20 { error = NSError(domain: NSURLErrorDomain, code: -1001, userInfo: [NSUnderlyingErrorKey: error]) }
        let result = SystemTechnicalErrorClassifier.classify(error, context: context)
        #expect(result.metadata["underlying4Code"] == "-1001")
        #expect(result.metadata["underlying5Code"] == nil)
    }

    @Test func timeoutAndCertificateFailuresRemainDistinct() {
        let timeout = NSError(domain: FunctionsErrorDomain, code: 4)
        #expect(SystemTechnicalErrorClassifier.classify(timeout, context: context).errorCode == "cloudFunctions.deadlineExceeded")
        #expect(OrganizationBlockingCoordinator.failureMessage(timeout) == AppStrings.Safety.organizationBlockTimedOut)
        let certificate = NSError(domain: NSURLErrorDomain, code: NSURLErrorServerCertificateUntrusted)
        #expect(SystemTechnicalErrorClassifier.classify(certificate, context: context).errorCode == "network.certificateUntrusted")
    }
}
