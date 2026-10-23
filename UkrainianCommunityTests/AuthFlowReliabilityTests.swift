import AuthenticationServices
import FirebaseAuth
import FirebaseFunctions
import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct AuthFlowReliabilityTests {
    @Test
    func sharedLeaseRejectsOverlappingMethodsAndLateRelease() throws {
        let flow = AuthInteractionCoordinator()
        let first = try #require(flow.begin())
        #expect(flow.begin() == nil)
        flow.finish(UUID())
        #expect(flow.isBusy)
        flow.finish(first)
        let next = try #require(flow.begin())
        flow.finish(first)
        #expect(flow.isBusy)
        flow.finish(next)
        #expect(!flow.isBusy)
    }

    @Test
    func failuresDistinguishTransportThrottleAndCancellation() {
        #expect(AuthFailureMessage.text(for: URLError(.notConnectedToInternet), fallback: "fallback") == AppStrings.Startup.connectionMessage)
        #expect(AuthFailureMessage.text(for: NSError(domain: AuthErrorDomain, code: AuthErrorCode.tooManyRequests.rawValue), fallback: "fallback") == AppStrings.Auth.emailVerificationTooManyRequests)
        #expect(AuthFailureMessage.text(for: NSError(domain: FunctionsErrorDomain, code: FunctionsErrorCode.failedPrecondition.rawValue), fallback: "fallback") == AppStrings.Auth.signInExpired)
        #expect(AuthFailureMessage.isCancellation(ASAuthorizationError(.canceled)))
        #expect(!AuthFailureMessage.isCancellation(URLError(.notConnectedToInternet)))
        #expect(AuthFailureMessage.text(for: NSError(domain: "another-domain", code: AuthErrorCode.tooManyRequests.rawValue), fallback: "fallback") == "fallback")
    }

    @Test
    func appleTitleUsesSelectedAppLanguage() {
        let previous = LocalizationStore.language
        defer { LocalizationStore.language = previous }
        LocalizationStore.language = .ukrainian
        #expect(AppStrings.Auth.continueWithApple == "Продовжити з Apple")
        LocalizationStore.language = .german
        #expect(AppStrings.Auth.continueWithApple == "Mit Apple fortfahren")
    }

    @Test
    func simultaneousDocumentLoadsShareOneRequestAndKeepAuthoritativePair() async throws {
        let repository = RegistrationLegalProbe()
        let model = RegistrationLegalDocumentsViewModel(repository: repository)
        let first = Task { await model.load() }
        for _ in 0..<1000 {
            if repository.pending.count == 2 { break }
            await Task.yield()
        }
        let second = Task { try await model.refreshForSubmission() }
        for _ in 0..<50 { await Task.yield() }
        #expect(repository.count == 2)
        repository.complete()
        await first.value
        let pair = try await second.value
        #expect(model.isReady)
        #expect(pair.terms.type == .terms && pair.privacy.type == .privacy)
        #expect(!model.isLoading)
    }

    @Test
    func failedSubmissionRefreshPreservesReviewedVersionsButRequiresRetry() async throws {
        let repository = RegistrationLegalProbe()
        let model = RegistrationLegalDocumentsViewModel(repository: repository)
        let loading = Task { await model.load() }
        for _ in 0..<1000 {
            if repository.pending.count == 2 { break }
            await Task.yield()
        }
        repository.complete()
        await loading.value
        let reviewed = model.versionKey
        repository.error = URLError(.notConnectedToInternet)
        do {
            _ = try await model.refreshForSubmission()
            Issue.record("Expected offline submission refresh to fail")
        } catch {}
        #expect(model.versionKey == reviewed)
        #expect(!model.isReady)
        #expect(model.errorMessage == AppStrings.Startup.connectionMessage)
        repository.error = nil
        let retry = Task { await model.load() }
        for _ in 0..<1000 {
            if repository.pending.count == 2 { break }
            await Task.yield()
        }
        repository.complete()
        await retry.value
        #expect(model.isReady)
        #expect(model.versionKey == reviewed)
    }

    @Test
    func documentTimeoutFailsClosedAndIgnoresLateData() async throws {
        let repository = RegistrationLegalProbe()
        let model = RegistrationLegalDocumentsViewModel(repository: repository, readTimeout: .milliseconds(20))
        await model.load()
        #expect(!model.isReady)
        #expect(!model.isLoading)
        #expect(model.errorMessage != nil)
        repository.complete()
        for _ in 0..<20 { await Task.yield() }
        #expect(!model.isReady)
    }
}

@MainActor
private final class RegistrationLegalProbe: LegalDocumentRepository {
    var error: Error?
    var count = 0
    var pending: [(LegalDocumentType, CheckedContinuation<LegalDocument, Error>)] = []
    func fetchActiveDocument(type: LegalDocumentType) async throws -> LegalDocument {
        count += 1
        if let error { throw error }
        return try await withCheckedThrowingContinuation { pending.append((type, $0)) }
    }
    func complete() {
        let reads = pending
        pending = []
        for (type, continuation) in reads {
            let document = LegalDocument(id: type.rawValue, type: type, version: "1", versionNumber: 1,
                locales: [:], defaultLocale: "de", canonicalLocale: "de", contentHash: "hash",
                changeSummary: nil, requiresAcceptance: true, status: .published,
                updatedAt: nil, updatedBy: nil, publishedAt: nil, publishedBy: nil)
            continuation.resume(returning: document)
        }
    }
    func fetchManagementState(type: LegalDocumentType) async throws -> LegalDocumentManagementState { throw AppError.notFound }
    func saveDraft(_ draft: LegalDocumentDraft, updatedBy userID: String) async throws { throw AppError.notFound }
    func publishDraft(_ draft: LegalDocumentDraft, publishedBy userID: String) async throws { throw AppError.notFound }
    func acceptDocument(type: LegalDocumentType, version: String, appVersion: String?, locale: String?, acceptedFromPlatform: String) async throws -> LegalAcceptanceReceipt { throw AppError.notFound }
}
