import Foundation

struct MockLegalDocumentRepository: LegalDocumentRepository {
    private let storage = MockLegalDocumentStorage.shared

    func fetchActiveDocument(type: LegalDocumentType) async throws -> LegalDocument {
        await storage.activeDocument(type: type)
    }

    func fetchManagementState(type: LegalDocumentType) async throws -> LegalDocumentManagementState {
        await storage.managementState(type: type)
    }

    func saveDraft(_ draft: LegalDocumentDraft, updatedBy userID: String) async throws {
        await storage.saveDraft(draft)
    }

    func publishDraft(_ draft: LegalDocumentDraft, publishedBy userID: String) async throws {
        await storage.publishDraft(draft, publishedBy: userID)
    }

    func acceptDocument(
        type: LegalDocumentType,
        version: String,
        appVersion: String?,
        locale: String?,
        acceptedFromPlatform: String
    ) async throws -> LegalAcceptanceReceipt {
        LegalAcceptanceReceipt(
            documentType: type,
            version: version,
            acceptedAt: .now
        )
    }
}

private actor MockLegalDocumentStorage {
    static let shared = MockLegalDocumentStorage()

    private var activeDocuments: [LegalDocumentType: LegalDocument] = [:]
    private var drafts: [LegalDocumentType: LegalDocumentDraft] = [:]

    func activeDocument(type: LegalDocumentType) async -> LegalDocument {
        if let activeDocument = activeDocuments[type] {
            return activeDocument
        }

        let fallback = await MainActor.run {
            LegalDocument.hardcodedFallback(type: type)
        }
        activeDocuments[type] = fallback
        return fallback
    }

    func managementState(type: LegalDocumentType) async -> LegalDocumentManagementState {
        let activeDocument = await activeDocument(type: type)
        return LegalDocumentManagementState(
            type: type,
            activeDocument: activeDocument,
            draftDocument: drafts[type].map { draftDocument(from: $0, status: .draft) }
        )
    }

    func saveDraft(_ draft: LegalDocumentDraft) {
        drafts[draft.type] = draft
    }

    func publishDraft(_ draft: LegalDocumentDraft, publishedBy userID: String) {
        activeDocuments[draft.type] = draftDocument(from: draft, status: .published)
        drafts[draft.type] = nil
    }

    private func draftDocument(
        from draft: LegalDocumentDraft,
        status: LegalDocumentStatus
    ) -> LegalDocument {
        LegalDocument(
            id: draft.type.rawValue,
            type: draft.type,
            version: draft.version,
            versionNumber: draft.versionNumber,
            locales: draft.locales,
            defaultLocale: draft.defaultLocale,
            canonicalLocale: draft.canonicalLocale,
            contentHash: nil,
            changeSummary: draft.changeSummary,
            requiresAcceptance: draft.requiresAcceptance,
            status: status,
            updatedAt: .now,
            updatedBy: "mock-owner",
            publishedAt: status == .published ? .now : nil,
            publishedBy: status == .published ? "mock-owner" : nil
        )
    }
}
