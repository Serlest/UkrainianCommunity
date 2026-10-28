import Foundation
import Testing
@testable import UkrainianCommunity

private final class LegalManagementRepositoryStub: LegalDocumentRepository {
    var states: [LegalDocumentType: LegalDocumentManagementState] = [:]
    var error: AppError?
    var failedType: LegalDocumentType?

    func fetchActiveDocument(type: LegalDocumentType) async throws -> LegalDocument {
        states[type]?.activeDocument ?? .hardcodedFallback(type: type)
    }

    func fetchManagementState(type: LegalDocumentType) async throws -> LegalDocumentManagementState {
        if let error, failedType == nil || failedType == type { throw error }
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
    @Test func historicalPublishedIdentifierCompatibilityDoesNotPermitLegacyWrites() {
        for number in [202602, 202603, 202604] {
            let legacy = "2026.\(number)"
            #expect(FirestoreLegalDocumentRepository.hasReadableVersionIdentifier(legacy, versionNumber: number))
            #expect(!LegalDocumentDraft.hasConsistentVersionIdentifier(legacy, versionNumber: number))
        }
        #expect(FirestoreLegalDocumentRepository.hasReadableVersionIdentifier("2026.15", versionNumber: 202615))
        for (identifier, number) in [("2025.202604", 202604), ("2026.202603", 202604),
                                     ("2026.202600", 202600), ("2026.0202604", 202604),
                                     ("2026.202604/other", 202604), ("0.4", 4)] {
            #expect(!FirestoreLegalDocumentRepository.hasReadableVersionIdentifier(identifier, versionNumber: number))
        }
    }

    @Test func changeSummaryKeepsLanguagesSeparateAndReadsOlderSummaries() {
        var summary = LegalChangeSummary(raw: nil)
        summary.german = "Neue Frist"
        summary.ukrainian = "Новий строк"
        let saved = LegalChangeSummary(raw: summary.encoded)
        #expect(saved.localized("de") == "Neue Frist")
        #expect(saved.localized("uk") == "Новий строк")
        #expect(saved.hasBothLanguages)

        let older = LegalChangeSummary(raw: "Previous update")
        #expect(older.localized("uk") == "Previous update")
        #expect(!older.hasBothLanguages)
        let partial = LegalChangeSummary(raw: "DE:Only German\nUK:")
        #expect(!partial.hasBothLanguages)
        #expect(partial.hasSeparateTranslations)
        #expect(partial.german == "Only German")
        #expect(partial.ukrainian.isEmpty)
        #expect(LegalChangeSummary(raw: partial.encoded).german == "Only German")
        #expect(!older.hasSeparateTranslations)
    }

    @Test func offlineDocumentsContainFullDistinctTranslationsAndCorrectAcceptance() throws {
        let url = try #require(Bundle.main.url(forResource: "LegalDocuments", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let bundled = try JSONDecoder().decode([String: LegalDocument].self, from: data)
        for kind in LegalDocumentType.allCases {
            let document = LegalDocument.hardcodedFallback(type: kind)
            #expect(document == bundled[kind.rawValue])
            #expect(document.version == kind.legacyVersion)
            #expect(document.requiresAcceptance)
            let german = try #require(document.content(preferredLocale: "de"))
            let ukrainian = try #require(document.content(preferredLocale: "uk"))
            #expect(german.contentMarkdown != ukrainian.contentMarkdown)
            #expect(german.contentHash != ukrainian.contentHash)
            #expect(german.contentMarkdown.contains("ukrainian.community@outlook.com") || kind == .organizationRules)
            #expect(german.contentMarkdown.components(separatedBy: "\n## ").count == ukrainian.contentMarkdown.components(separatedBy: "\n## ").count)
        }
        let privacy = LegalDocument.hardcodedFallback(type: .privacy)
        #expect(privacy.content(preferredLocale: "de")?.contentMarkdown.contains("## 18.") == true)
        #expect(privacy.content(preferredLocale: "uk")?.contentMarkdown.contains("## 18.") == true)
    }

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

@MainActor
struct LegalEditorRecoveryTests {
    @Test func aBrokenDocumentDoesNotHideOtherCards() async {
        let repo = LegalManagementRepositoryStub()
        repo.error = .network; repo.failedType = .privacy
        let model = LegalDocumentManagementViewModel(repository: repo)
        await model.load()
        #expect(model.states.count == 2)
        #expect(model.failedTypes == [.privacy])
        #expect(model.errorMessage == nil)
    }
    @Test func incompleteDraftKeepsIntegrityWithoutBeingPublishable() throws {
        var draft = LegalDocumentDraft.from(activeDocument: .hardcodedFallback(type: .terms))
        draft.locales["uk"] = LegalDocumentLocaleContent(title: "", contentMarkdown: "", contentText: nil,
            contentHash: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        let document = LegalDocument(id: draft.type.rawValue, type: draft.type, version: draft.version,
            versionNumber: draft.versionNumber, locales: draft.locales, defaultLocale: "de", canonicalLocale: "de",
            contentHash: draft.normalizedContentHash, changeSummary: nil, requiresAcceptance: true, status: .draft,
            updatedAt: nil, updatedBy: nil, publishedAt: nil, publishedBy: nil)
        #expect(FirestoreLegalDocumentRepository.hasValidContentHashes(document, allowIncomplete: true))
        #expect(!FirestoreLegalDocumentRepository.hasValidContentHashes(document))
    }
    @Test func comparisonKeepsAddedAndRemovedParagraphsSeparate() {
        let changes = LegalTextChange.compare(old: "# Title\nOld paragraph", new: "# Title\nNew paragraph")
        #expect(changes.count == 2)
        #expect(changes.contains { !$0.added && $0.text == "Old paragraph" })
        #expect(changes.contains { $0.added && $0.text == "New paragraph" })
        #expect(LegalTextChange.compare(old: "unchanged", new: "unchanged").isEmpty)
    }
}
