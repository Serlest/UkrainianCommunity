import Foundation
import Testing
@testable import UkrainianCommunity

private final class LegalManagementRepositoryStub: LegalDocumentRepository {
    var states: [LegalDocumentType: LegalDocumentManagementState] = [:]
    var error: AppError?

    func fetchActiveDocument(type: LegalDocumentType) async throws -> LegalDocument {
        states[type]?.activeDocument ?? .hardcodedFallback(type: type)
    }

    func fetchManagementState(type: LegalDocumentType) async throws -> LegalDocumentManagementState {
        if let error { throw error }
        return states[type] ?? LegalDocumentManagementState(
            type: type,
            activeDocument: .hardcodedFallback(type: type),
            draftDocument: nil
        )
    }

    func saveDraft(_ draft: LegalDocumentDraft, updatedBy userID: String) async throws {}
    func publishDraft(_ draft: LegalDocumentDraft, publishedBy userID: String) async throws {}

    func acceptDocument(
        type: LegalDocumentType,
        version: String,
        appVersion: String?,
        locale: String?,
        acceptedFromPlatform: String
    ) async throws -> LegalAcceptanceReceipt {
        LegalAcceptanceReceipt(documentType: type, version: version, acceptedAt: .now)
    }
}

@MainActor
struct LegalDocumentManagementTests {
    @Test func firstLoadFailureDoesNotExposeFallbackDocumentsAsManagementState() async {
        let repository = LegalManagementRepositoryStub()
        repository.error = .network
        let viewModel = LegalDocumentManagementViewModel(repository: repository)

        await viewModel.load()

        #expect(viewModel.states.isEmpty)
        #expect(viewModel.errorMessage == AppStrings.LegalManagement.loadFailed)
    }

    @Test func retryLoadsBothDocumentTypes() async {
        let repository = LegalManagementRepositoryStub()
        repository.error = .network
        let viewModel = LegalDocumentManagementViewModel(repository: repository)

        await viewModel.load()
        repository.error = nil
        await viewModel.load()

        #expect(viewModel.states[.terms] != nil)
        #expect(viewModel.states[.privacy] != nil)
        #expect(viewModel.errorMessage == nil)
    }
}
