import Foundation
import FirebaseFirestore
import Testing
@testable import UkrainianCommunity

private final class SupportListenerToken: AppRealtimeListener { func cancel() {} }
@MainActor private final class SupportRecoveryRepository: DonationConfigRepository {
    var config: DonationConfig? = .defaults
    var error: Error?
    var saveError: Error?
    var listenerCount = 0
    var saveCount = 0
    var change: (@MainActor (DonationConfig)->Void)?
    var failure: (@MainActor (AppError)->Void)?
    var holdSave = false
    var pending: CheckedContinuation<DonationConfig, Error>?
    var holdRead = false
    var readCount = 0
    var pendingRead: CheckedContinuation<DonationConfig?, Error>?
    func fetchDonationConfig() async throws -> DonationConfig? {
        readCount += 1
        if holdRead { return try await withCheckedThrowingContinuation { pendingRead = $0 } }
        if let error { throw error }; return config
    }
    func saveDonationConfig(_ config: DonationConfig, updatedBy userID: String) async throws -> DonationConfig {
        saveCount += 1
        if holdSave { return try await withCheckedThrowingContinuation { pending = $0 } }
        if let saveError { throw saveError }; return config
    }
    func listenDonationConfig(onChange: @escaping @MainActor (DonationConfig)->Void, onError: @escaping @MainActor (AppError)->Void) -> AppRealtimeListener? {
        listenerCount += 1; change=onChange; failure=onError; return SupportListenerToken()
    }
}
@MainActor struct ProjectSupportRecoveryTests {
    @Test func retryReattachesTerminalListenerAndRejectsOldCallbacks() async {
        let repo=SupportRecoveryRepository()
        let subject=DonationConfigViewModel(repository:repo)
        await subject.loadIfNeeded();let oldChange=repo.change,oldFailure=repo.failure
        repo.failure?(.permissionDenied);await subject.load()
        #expect(repo.listenerCount == 2)
        var newer=DonationConfig.defaults;newer.titleUK="Нові дані"
        repo.change?(newer);oldChange?(.defaults);oldFailure?(.network)
        #expect(subject.config.titleUK == "Нові дані");#expect(subject.statusMessage == nil)
    }
    @Test func authoritativeRecoveryClearsReadErrorButNotMutationWarning() async {
        let repo=SupportRecoveryRepository()
        let subject=DonationConfigViewModel(repository:repo);await subject.loadIfNeeded()
        repo.failure?(.network);#expect(subject.statusMessage != nil)
        repo.change?(.defaults);#expect(subject.statusMessage == nil)
        repo.saveError=DonationConfigSaveError.conflict
        var draft=subject.config;draft.titleUK="Локальна правка"
        #expect(await subject.save(draft,updatedBy:"owner")==false)
        repo.change?(.defaults)
        #expect(subject.needsReload);#expect(subject.statusMessage == DonationEditorText.conflict)
        repo.saveError=nil;await subject.load();#expect(!subject.needsReload);#expect(subject.statusMessage == nil)
    }
    @Test func sameUIDReauthenticationInvalidatesHeldSaveCompletion() async throws {
        let repo=SupportRecoveryRepository()
        let model=DonationConfigViewModel(repository:repo);await model.load()
        var draft=model.config;draft.titleUK="Saved by previous session";repo.holdSave=true
        var authRevision=1
        let operation=Task { await model.save(draft,updatedBy:"same-owner",isCurrent:{ authRevision == 1 }) }
        for _ in 0..<200 where repo.pending == nil { await Task.yield() }
        let pending=try #require(repo.pending);authRevision=2;model.invalidateEditor()
        pending.resume(returning:draft)
        #expect(await operation.value == false);#expect(model.statusMessage == nil);#expect(!model.isSaving)
    }
    @Test func deniedAuthorityNeverStartsWriteAndInitialStateIsNotFailure() async {
        let repo=SupportRecoveryRepository()
        let subject=DonationConfigViewModel(repository:repo)
        #expect(!subject.hasAttemptedLoad);#expect(subject.statusMessage == nil)
        #expect(await subject.save(.defaults,updatedBy:"owner",isCurrent:{false}) == false)
        #expect(repo.saveCount == 0)
    }
    @Test func readbackRequiresNewRevisionSameAuthorAndExactNormalizedContent() {
        var input=DonationConfig.defaults;input.sourceRevision="old"
        var saved=input;saved.updatedBy="owner"
        #expect(!FirestoreDonationConfigRepository.confirmsWrite(saved,input:input,userID:"owner"))
        saved.sourceRevision="new";#expect(FirestoreDonationConfigRepository.confirmsWrite(saved,input:input,userID:"owner"))
        saved.updatedBy="other";#expect(!FirestoreDonationConfigRepository.confirmsWrite(saved,input:input,userID:"owner"))
        saved.updatedBy="owner";saved.titleUK="different";#expect(!FirestoreDonationConfigRepository.confirmsWrite(saved,input:input,userID:"owner"))
        #expect(!FirestoreDonationConfigRepository.mayHaveCommitted(NSError(domain:FirestoreErrorDomain,code:FirestoreErrorCode.Code.permissionDenied.rawValue)))
        #expect(FirestoreDonationConfigRepository.mayHaveCommitted(NSError(domain:FirestoreErrorDomain,code:FirestoreErrorCode.Code.unavailable.rawValue)))
    }
    @Test func conflictAndUnconfirmedDiagnosticsExplainDistinctOutcomes() {
        let context=SystemTechnicalErrorContext(moduleName:"ProjectSupport",operationName:"saveDonationConfig",targetType:.donationConfig,metadata:["expectedRevision":"old"])
        for (failure,code) in [(DonationConfigSaveError.conflict,"configuration.conflict"),(.unconfirmed,"configuration.unconfirmed")] {
            let classified=SystemTechnicalErrorClassifier.classify(failure,context:context)
            #expect(classified.errorCode == code);#expect(classified.metadata["expectedRevision"] == "old")
            let draft=SystemLogDraft.error(eventType:.technicalError,summary:"Failure",errorCode:code,operationName:"saveDonationConfig",targetType:.donationConfig)
            let entry=SystemLogEntry(id:"test",createdAt:Date(),draft:draft)
            #expect(SystemLogExplanation.action(entry) == ProjectSupportText.journalAction)
            #expect(SystemLogExplanation.title(entry) != SystemLogExplanation.text("unknown.title"))
            #expect(SystemLogExplanation.nextStep(entry) == ProjectSupportText.journalNext)
        }
    }
}

@MainActor private final class SupportJournalRecorder: SystemLoggingServiceProtocol {
    private var drafts: [SystemLogDraft] = []
    func log(_ draft: SystemLogDraft) async throws { drafts.append(draft) }
    func recorded() -> [SystemLogDraft] { drafts }
}
private struct SupportJournalActorResolver: SystemAuditActorResolving {
    let userID: String
    func resolveOwnerOrAdminActor() async -> SystemAuditActor? { .init(userId:userID,displayName:"Test owner",role:.owner) }
}
extension ProjectSupportRecoveryTests {
    @Test func simultaneousParentAndEditorReadsAwaitSameConfirmedConfiguration() async throws {
        let repo = SupportRecoveryRepository(); repo.holdRead = true
        let model = DonationConfigViewModel(repository: repo)
        let parent = Task { await model.loadIfNeeded() }
        for _ in 0..<200 where repo.pendingRead == nil { await Task.yield() }
        let read = try #require(repo.pendingRead)
        let editor = Task { await model.load() }
        for _ in 0..<20 { await Task.yield() }
        #expect(repo.readCount == 1); #expect(!model.hasLoadedData)
        var confirmed = DonationConfig.defaults; confirmed.titleUK = "Confirmed configuration"
        read.resume(returning: confirmed)
        await parent.value; await editor.value
        #expect(model.hasLoadedData); #expect(model.config.titleUK == confirmed.titleUK)
        #expect(!model.isLoading); #expect(model.statusMessage == nil)
    }

    @Test func checksumSurvivesJournalRedactionWithoutOpeningCredentialBypass() {
        let hash = String(repeating: "a1b2c3d4", count: 8)
        let fingerprint = DonationConfigDiagnostics.fingerprint(hash)
        #expect(fingerprint.split(separator: " ").count == 8)
        #expect(DonationConfigDiagnostics.fingerprint("Bearer " + hash) == "missing")
        #expect(DonationConfigDiagnostics.fingerprint(nil) == "missing")
        let draft = SystemLogDraft.error(eventType: .technicalError, summary: "Test",
            metadata: ["expectedRevision": fingerprint, "token": hash, "other": hash])
        let redacted = SystemLogRedactionPolicy.default.redactedDraft(from: draft)
        #expect(redacted.metadata["expectedRevision"] == fingerprint)
        #expect(redacted.metadata["token"] == SystemLogRedactionPolicy.redactedValue)
        #expect(redacted.metadata["other"] == SystemLogRedactionPolicy.redactedValue)
        #expect(ProfileNavigationRoute.donationSettings.hidesRootTabBar)
        // Both destinations own their navigation stack; the inbox must not
        // inherit the root tabs over its bottom content on the actual phone.
        #expect(ProfileNavigationRoute.notifications.hidesRootTabBar)
    }

    @Test func auditRecordsArePrincipalBoundAndDistinctRevisionsAreNotCollapsed() async {
        let recorder=SupportJournalRecorder()
        let service=SystemAuditLoggingService(loggingService:recorder,actorResolver:SupportJournalActorResolver(userID:"new-owner"))
        func context(_ expected: String,_ revision: String) -> SystemAuditLogContext {
            .init(moduleName:"ProjectSupport",operationName:"saveDonationConfig",eventType:.configurationUpdated,
                  targetType:.donationConfig,targetId:"donation",summary:"Project support configuration updated",
                  expectedPrincipalID:expected,metadata:["resultRevision":revision])
        }
        await service.logSuccess(context("old-owner","a"))
        #expect(recorder.recorded().isEmpty)
        await service.logSuccess(context("new-owner","a"))
        await service.logSuccess(context("new-owner","a"))
        await service.logSuccess(context("new-owner","b"))
        let events=recorder.recorded()
        #expect(events.count == 2)
        #expect(events.allSatisfy { $0.actorUserId == "new-owner" && $0.targetType == .donationConfig && $0.outcome == .success })
        #expect(events.map { $0.metadata["resultRevision"] } == ["a","b"])
    }
}
