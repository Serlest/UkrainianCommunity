import Foundation
import Testing
@testable import UkrainianCommunity

private final class Audit18EvidenceRepository: LegalEvidenceRepository {
    var error: Error?
    var hold = false
    var pending: CheckedContinuation<Void, Never>?
    var holdEvidence = false
    var pendingEvidence: CheckedContinuation<Void, Never>?
    let account = LegalEvidenceAccount(userID: "audit18-disposable", displayName: "Fixture", email: nil, createdAt: nil)
    func fetchAccounts(query: String?, limit: Int, cursor: LegalEvidenceAccountCursor?) async throws -> LegalEvidenceAccountPage {
        if hold { await withCheckedContinuation { pending = $0 } }
        if let error { throw error }
        return LegalEvidenceAccountPage(accounts: [account], nextCursor: nil, totalMatches: 1)
    }
    func fetchEvidence(userID: String) async throws -> LegalEvidenceHistory {
        if holdEvidence { await withCheckedContinuation { pendingEvidence = $0 } }
        if let error { throw error }
        return LegalEvidenceHistory(account: account, events: [], generatedAt: .now,
            summary: [LegalEvidenceStatus(kind: "terms", version: "2026.15", confirmedAt: "2026-10-27T11:00:00.000Z", currentVersion: "2026.15", state: "current")])
    }
}
@MainActor
struct LegalAudit18Probes {
    @Test func deniedRefreshWithdrawsPreviouslyLoadedAccountIdentities() async {
        let repo = Audit18EvidenceRepository(); let model = LegalEvidenceViewModel(repository: repo)
        await model.load(); #expect(model.accounts.count == 1)
        repo.error = NSError(domain: "FirebaseFunctions", code: 7)
        await model.load()
        #expect(model.accounts.isEmpty, "Explicit permission denial must withdraw private account identities")
        #expect(model.totalMatches == nil)
    }
    @Test func deniedHistoryWithdrawsPreparedPrivateExportAndSummary() async {
        let repo = Audit18EvidenceRepository(); let model = LegalEvidenceUserViewModel(account: repo.account, repository: repo)
        await model.load(); await model.prepareExport(); #expect(model.exportText != nil)
        repo.error = NSError(domain: "FirebaseFunctions", code: 7)
        await model.load()
        #expect(model.exportText == nil, "Previously exported legal history must not remain shareable after explicit denial")
        #expect(model.summary.isEmpty)
    }
    @Test func oldAccountQueryCannotAppearUnderNewSearchDuringDebounce() async {
        let repo = Audit18EvidenceRepository(); repo.hold = true
        let model = LegalEvidenceViewModel(repository: repo); model.searchText = "old"
        let task = Task { await model.load() }
        for _ in 0..<100 where repo.pending == nil { await Task.yield() }
        #expect(repo.pending != nil)
        model.searchText = "different"
        repo.pending?.resume(); await task.value
        #expect(model.accounts.isEmpty, "Changing query must invalidate the earlier response before next debounced load")
    }
}

private final class Audit18DocumentRepository: LegalDocumentRepository {
    var readError: Error?
    var count: [LegalDocumentType: Int] = [:]
    var active: LegalDocument = .hardcodedFallback(type: .terms)
    var history: [LegalVersionPage] = []
    var hold = false
    var pending: [LegalDocumentType: CheckedContinuation<Void, Never>] = [:]
    func fetchActiveDocument(type: LegalDocumentType) async throws -> LegalDocument {
        if let readError { throw readError }
        return type == .terms ? active : .hardcodedFallback(type: type)
    }
    func fetchManagementState(type: LegalDocumentType) async throws -> LegalDocumentManagementState {
        count[type, default: 0] += 1
        if hold { await withCheckedContinuation { pending[type] = $0 } }
        if let readError { throw readError }
        return LegalDocumentManagementState(type: type, activeDocument: .hardcodedFallback(type: type), draftDocument: nil)
    }
    func fetchVersionHistory(type: LegalDocumentType, before: Int?) async throws -> LegalVersionPage {
        if let readError { throw readError }
        return history.isEmpty ? LegalVersionPage(documents: [], nextBefore: nil) : history.removeFirst()
    }
    func saveDraft(_ draft: LegalDocumentDraft, updatedBy userID: String) async throws {}
    func publishDraft(_ draft: LegalDocumentDraft, publishedBy userID: String) async throws {}
    func acceptDocument(type: LegalDocumentType, version: String, appVersion: String?, locale: String?, acceptedFromPlatform: String) async throws -> LegalAcceptanceReceipt {
        LegalAcceptanceReceipt(documentType: type, version: version, acceptedAt: .now)
    }
}

@MainActor
struct LegalAudit18RecoveryTests {
    @Test func metadataChangesAlterDraftRevisionWithoutChangingPublishedContentHash() {
        var first = LegalDocumentDraft.from(activeDocument: .hardcodedFallback(type: .privacy))
        first.changeSummary = "DE:First\nUK:Перший"
        var second = first; second.changeSummary = "DE:Second\nUK:Другий"
        #expect(first.normalizedContentHash == second.normalizedContentHash)
        #expect(first.stateHash != second.stateHash)
        second = first; second.requiresAcceptance.toggle(); #expect(first.stateHash != second.stateHash)
        second = first; second.defaultLocale = "uk"; #expect(first.stateHash != second.stateHash)
        second = first; second.supersedesVersion = "2026.1"; #expect(first.stateHash != second.stateHash)
    }
    @Test func targetedDocumentRefreshRetainsOtherStatesAndReadsOnlyChangedType() async {
        let repo = Audit18DocumentRepository()
        let scoped = LegalDocumentManagementViewModel(repository: repo)
        #expect(!scoped.hasLoaded && scoped.states.isEmpty)
        await scoped.load(); #expect(scoped.states.count == 3)
        let previous = repo.count
        await scoped.load(types: [.privacy], force: true)
        #expect(repo.count[.terms] == previous[.terms]); #expect(repo.count[.organizationRules] == previous[.organizationRules])
        #expect(repo.count[.privacy] == (previous[.privacy] ?? 0) + 1)
    }
    @Test func failedDocumentRefreshKeepsConfirmedCardsButRecordsFailure() async {
        let repo = Audit18DocumentRepository()
        let scoped = LegalDocumentManagementViewModel(repository: repo)
        await scoped.load(); let confirmed = scoped.states
        repo.readError = AppError.network
        await scoped.load(types: [.privacy])
        #expect(scoped.states == confirmed); #expect(scoped.failedTypes == [.privacy]); #expect(!scoped.isLoading)
    }
    @Test func managementDenialClearsAllConfirmedDocuments() async {
        let repo = Audit18DocumentRepository()
        let scoped = LegalDocumentManagementViewModel(repository: repo)
        await scoped.load(); repo.readError = AppError.permissionDenied; await scoped.load(types: [.privacy])
        #expect(scoped.states.isEmpty); #expect(scoped.accessDenied)
    }
    @Test func publicReaderKeepsLastConfirmedServerDocumentAfterNetworkFailure() async {
        let repo = Audit18DocumentRepository()
        var draft = LegalDocumentDraft.from(activeDocument: repo.active)
        draft.changeSummary = "A future server-only version"
        repo.active = LegalDocument(id: "terms", type: .terms, version: draft.version, versionNumber: draft.versionNumber,
            locales: draft.locales, defaultLocale: "de", canonicalLocale: "de", contentHash: draft.normalizedContentHash,
            changeSummary: draft.changeSummary, requiresAcceptance: true, status: .published,
            updatedAt: nil, updatedBy: nil, publishedAt: nil, publishedBy: nil)
        let model = LegalDocumentReaderViewModel(kind: .terms, repository: repo)
        await model.load(); let confirmed = model.document
        repo.readError = AppError.network; await model.load()
        #expect(model.document == confirmed); #expect(!model.isUsingBundle)
        #expect(model.errorMessage == LegalFlowText.readerRefreshFailed)
    }
    @Test func firstOfflineReadLabelsBundleAndRetryReplacesIt() async {
        let repo = Audit18DocumentRepository(); repo.readError = AppError.network
        let model = LegalDocumentReaderViewModel(kind: .terms, repository: repo)
        #expect(model.document == nil && !model.hasLoaded)
        await model.load(); #expect(model.isUsingBundle && model.errorMessage == LegalFlowText.offlineBundle)
        repo.readError = nil; await model.load(); #expect(!model.isUsingBundle && model.errorMessage == nil)
    }
    @Test func historyKeepsPageOnNetworkFailureAndRetriesSameCursor() async {
        let repo = Audit18DocumentRepository(), active = LegalDocument.hardcodedFallback(type: .terms)
        repo.history = [LegalVersionPage(documents: [active], nextBefore: active.versionNumber)]
        let model = LegalHistoryViewModel(type: .terms, active: active, repository: repo)
        await model.load(); #expect(model.canLoadMore)
        repo.readError = AppError.network; await model.load(reset: false)
        #expect(model.documents == [active]); #expect(model.canLoadMore)
        repo.readError = nil; await model.retry(); #expect(!model.canLoadMore); #expect(model.documents == [active])
    }
    @Test func historyDenialWithdrawsAllPreviouslyLoadedVersions() async {
        let repo = Audit18DocumentRepository(), active = LegalDocument.hardcodedFallback(type: .terms)
        repo.history = [LegalVersionPage(documents: [active], nextBefore: nil)]
        let model = LegalHistoryViewModel(type: .terms, active: active, repository: repo)
        await model.load(); repo.readError = AppError.permissionDenied; await model.load()
        #expect(model.documents.isEmpty && model.accessDenied)
    }
    @Test func sameUIDReauthenticationHasDifferentScopeButProfileRefreshDoesNot() {
        let auth = AuthState()
        let user = AppUser(id:"legal-owner",fullName:"Owner",city:"Vienna",email:"fixture@example.com",bio:"",role:.user,globalRole:.owner,blockState:.active,createdAt:.now,updatedAt:.now)
        auth.setAuthenticatedSession(user: user); let first = LegalAccessScope(auth)
        _ = auth.updateAuthenticatedUser(user); #expect(first == LegalAccessScope(auth))
        auth.setGuestSession(); auth.setAuthenticatedSession(user: user)
        #expect(first != LegalAccessScope(auth))
    }
    @Test func latePrivateAccountResponseCannotCrossSameUIDReauthentication() async {
        let auth = AuthState()
        let user = AppUser(id:"legal-owner",fullName:"Owner",city:"Vienna",email:"fixture@example.com",bio:"",role:.user,globalRole:.owner,blockState:.active,createdAt:.now,updatedAt:.now)
        auth.setAuthenticatedSession(user: user)
        let repo = Audit18EvidenceRepository(); repo.hold = true
        let model = LegalEvidenceViewModel(repository: repo); model.accessScope = { LegalAccessScope(auth) }
        let work = Task { await model.load() }
        for _ in 0..<100 where repo.pending == nil { await Task.yield() }
        auth.setGuestSession(); auth.setAuthenticatedSession(user: user)
        repo.pending?.resume(); await work.value
        #expect(model.accounts.isEmpty && !model.hasLoaded)
    }
    @Test func cancelledHistoryExportCannotLeaveBusyStateOrReappearAfterClear() async {
        let repo = Audit18EvidenceRepository(); repo.holdEvidence = true
        let model = LegalEvidenceUserViewModel(account: repo.account, repository: repo)
        let task = Task { await model.prepareExport() }
        for _ in 0..<100 where repo.pendingEvidence == nil { await Task.yield() }
        #expect(repo.pendingEvidence != nil && model.isExporting)
        model.clear(); repo.pendingEvidence?.resume(); await task.value
        #expect(model.exportText == nil && !model.isExporting && model.summary.isEmpty)
    }
}

extension LegalAudit18RecoveryTests {
    @Test func overlappingManagementReadsAreCoalescedAndWithdrawnOnSameUIDReauthentication() async {
        let repository = Audit18DocumentRepository(); repository.hold = true
        let auth = AuthState()
        let user = AppUser(id: "legal18-owner", fullName: "Fixture", city: "Vienna", email: "fixture@uac.test", bio: "", role: .user, globalRole: .owner, blockState: .active, createdAt: .now, updatedAt: .now)
        auth.setAuthenticatedSession(user: user)
        let model = LegalDocumentManagementViewModel(repository: repository)
        model.accessScope = { LegalAccessScope(auth) }
        let first = Task { await model.load() }, second = Task { await model.load() }
        for _ in 0..<100 where repository.pending.count < 3 { await Task.yield() }
        #expect(repository.count.values.reduce(0, +) == 3)
        auth.setGuestSession(); auth.setAuthenticatedSession(user: user)
        for continuation in repository.pending.values { continuation.resume() }
        await first.value; await second.value
        #expect(model.states.isEmpty)
        #expect(!model.isLoading)
    }
    @Test func acknowledgementRefreshKeyChangesWithoutClosingEditorScope() {
        let auth = AuthState()
        let user = AppUser(id: "legal18-owner", fullName: "Fixture", city: "Vienna", email: "fixture@uac.test", bio: "", role: .user, globalRole: .owner, blockState: .active, createdAt: .now, updatedAt: .now)
        auth.setAuthenticatedSession(user: user)
        let scope = LegalAccessScope(auth), key = LegalQueryScope(auth, query: "management")
        let updated = AppUser(id: user.id, fullName: user.fullName, city: user.city, email: user.email, bio: user.bio, role: user.role, globalRole: .owner, blockState: .active, acceptedTermsVersion: "2026.16", createdAt: user.createdAt, updatedAt: .now)
        _ = auth.updateAuthenticatedUser(updated)
        #expect(LegalAccessScope(auth) == scope)
        #expect(LegalQueryScope(auth, query: "management") != key)
    }
}
