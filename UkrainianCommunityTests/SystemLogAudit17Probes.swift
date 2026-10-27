import Foundation
import FirebaseFunctions
import Testing
@testable import UkrainianCommunity

@MainActor private final class JournalAudit17Repository: SystemLogRepositoryProtocol {
    var usesServerFiltering: Bool { true }
    var page = SystemLogPage(entries: [], cursor: nil)
    var cursors: [String?] = []
    var pageError: Error?
    var suspended: CheckedContinuation<SystemLogPage, Error>?
    var suspend = false
    var detailContinuation: CheckedContinuation<SystemLogEntry?, Error>?
    var reviewContinuation: CheckedContinuation<Void, Error>?
    var suspendDetail = false
    var suspendReview = false
    var detailResult: SystemLogEntry?
    var detailError: Error?
    func queryPage(filter: SystemLogFilter, sortOption: SystemLogSortOption, limit: Int, cursor: String?) async throws -> SystemLogPage {
        cursors.append(cursor)
        if suspend { return try await withCheckedThrowingContinuation { suspended = $0 } }
        if let pageError { throw pageError }
        return page
    }
    func fetchLogs(filter: SystemLogFilter, sortOption: SystemLogSortOption, limit: Int) async throws -> [SystemLogEntry] { [] }
    func fetchLog(id: String) async throws -> SystemLogEntry? {
        if suspendDetail { return try await withCheckedThrowingContinuation { detailContinuation = $0 } }
        if let detailError { throw detailError }
        return detailResult
    }
    func markReviewed(logID: String, reviewedByUserId: String) async throws {
        if suspendReview { try await withCheckedThrowingContinuation { reviewContinuation = $0 } }
    }
    func deleteLog(id: String) async throws {}
}

@MainActor struct SystemLogAudit17Probes {
    @Test func sevenDaysContainsExactlySevenCalendarDates() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/Vienna")!
        let now = Date(timeIntervalSince1970: 1793095200)
        let model = SystemLogsViewModel(repository: JournalAudit17Repository(), calendar: calendar, nowProvider: { now })
        model.datePreset = .sevenDays
        #expect(model.queryFilter.startDate == calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)))
    }
    @Test func deletedExactDetailCannotRetainCachedRecord() async throws {
        let repo = JournalAudit17Repository(); let row = try #require(MockSystemLogRepository.sampleEntries.first)
        repo.page = .init(entries: [row], cursor: nil)
        let model = SystemLogsViewModel(repository: repo); await model.refresh(); await model.refreshLogDetail(id: row.id)
        #expect(model.log(id: row.id) == nil)
    }
    @Test func expiredCursorRetryCanRecoverFromFirstPage() async {
        let repo = JournalAudit17Repository(); repo.page = .init(entries: [], cursor: "expired")
        let model = SystemLogsViewModel(repository: repo); await model.refresh()
        repo.pageError = NSError(domain: FunctionsErrorDomain, code: FunctionsErrorCode.aborted.rawValue)
        await model.loadNextPage(); await model.loadNextPage()
        #expect(repo.cursors.last! == nil)
    }
    @Test func completedDeleteCannotBeUndoneByOldListResponse() async throws {
        let repo = JournalAudit17Repository(); let row = try #require(MockSystemLogRepository.sampleEntries.first)
        repo.page = .init(entries: [row], cursor: nil)
        let model = SystemLogsViewModel(repository: repo); await model.refresh(); repo.suspend = true
        let refresh = Task { await model.refresh() }
        while repo.suspended == nil { await Task.yield() }
        await model.deleteLog(id: row.id)
        repo.suspended!.resume(returning: .init(entries: [row], cursor: nil)); await refresh.value
        #expect(model.logs.isEmpty)
    }
    @Test func callablePermissionCodeProducesPermissionExplanation() async {
        let repo = JournalAudit17Repository(); repo.pageError = NSError(domain: FunctionsErrorDomain, code: FunctionsErrorCode.permissionDenied.rawValue)
        let model = SystemLogsViewModel(repository: repo); await model.refresh()
        #expect(model.errorMessage == AppStrings.SystemLogs.ownerLoadPermissionError)
    }
    @Test func initialDebouncedQueryMustShowLoadingInsteadOfEmpty() async {
        let repo = JournalAudit17Repository(); repo.suspend = true
        let model = SystemLogsViewModel(repository: repo)
        let task = Task { await model.queryChanged() }
        for _ in 0..<10 { await Task.yield() }
        #expect(model.isLoading)
        while repo.suspended == nil { await Task.yield() }
        repo.suspended!.resume(returning: .init(entries: [], cursor: nil))
        await task.value
        #expect(model.hasLoadedInitialPage && !model.isLoading)
    }
    @Test func explicitPermissionDenialWithdrawsPreviouslyLoadedRecords() async throws {
        let repo = JournalAudit17Repository(); let row = try #require(MockSystemLogRepository.sampleEntries.first)
        repo.page = .init(entries: [row], cursor: nil)
        let model = SystemLogsViewModel(repository: repo); await model.refresh()
        repo.pageError = NSError(domain: FunctionsErrorDomain, code: FunctionsErrorCode.permissionDenied.rawValue)
        await model.refresh()
        #expect(model.logs.isEmpty)
    }

    @Test func lateRefreshCannotCrossAccountABA() async throws {
        let row = try #require(MockSystemLogRepository.sampleEntries.first)
        var session = "A-first"; let repo = JournalAudit17Repository();repo.suspend = true
        let model = SystemLogsViewModel(repository: repo, sessionKeyProvider: {session})
        let load = Task { await model.refresh() };while repo.suspended == nil {await Task.yield()}
        session = "B";model.synchronizeSession();session = "A-second";model.synchronizeSession()
        repo.suspended!.resume(returning:.init(entries:[row],cursor:"old"));await load.value
        #expect(model.logs.isEmpty && !model.canLoadMore && !model.isLoading)
    }
    @Test func lateExactReadCannotRestoreDeletedLog() async throws {
        let row = try #require(MockSystemLogRepository.sampleEntries.first)
        let repo = JournalAudit17Repository();repo.page = .init(entries:[row],cursor:nil);repo.suspendDetail=true
        let model = SystemLogsViewModel(repository:repo);await model.refresh()
        let detail = Task{await model.refreshLogDetail(id:row.id)};while repo.detailContinuation == nil {await Task.yield()}
        await model.deleteLog(id:row.id);repo.detailContinuation!.resume(returning:row);await detail.value
        #expect(model.log(id:row.id)==nil)
    }
    @Test func lateReviewCannotMarkAnotherSession() async throws {
        let row = try #require(MockSystemLogRepository.sampleEntries.first)
        var session="A";let repo=JournalAudit17Repository();repo.suspendReview=true;repo.page = .init(entries:[row],cursor:nil)
        let model=SystemLogsViewModel(repository:repo,reviewerUserIdProvider:{"reviewer"},sessionKeyProvider:{session});await model.refresh()
        let review=Task{await model.markReviewed(logID:row.id)};while repo.reviewContinuation == nil {await Task.yield()}
        session="B";model.synchronizeSession();await model.refresh()
        repo.reviewContinuation!.resume();await review.value
        #expect(model.logs.first?.isReviewed == row.isReviewed)
    }
    @Test func transientPaginationFailureRetriesSamePageAndKeepsRows() async throws {
        let row = try #require(MockSystemLogRepository.sampleEntries.first)
        let repo=JournalAudit17Repository();repo.page = .init(entries:[row],cursor:"page-two")
        let model=SystemLogsViewModel(repository:repo);await model.refresh()
        repo.pageError=NSError(domain:NSURLErrorDomain,code:NSURLErrorNotConnectedToInternet)
        await model.loadNextPage();#expect(model.logs == [row]);#expect(!model.cursorRequiresRefresh)
        await model.loadNextPage();#expect(repo.cursors.suffix(2).allSatisfy{$0=="page-two"})
    }
    @Test func exactReadCanRecoverAfterPermissionRestored() async throws {
        let row = try #require(MockSystemLogRepository.sampleEntries.first)
        let repo=JournalAudit17Repository();repo.detailError=NSError(domain:FunctionsErrorDomain,code:FunctionsErrorCode.permissionDenied.rawValue)
        let model=SystemLogsViewModel(repository:repo);await model.refreshLogDetail(id:row.id)
        #expect(model.accessDenied && model.log(id:row.id)==nil)
        repo.detailError=nil;repo.detailResult=row;await model.refreshLogDetail(id:row.id)
        #expect(!model.accessDenied && model.log(id:row.id)==row)
    }
    @Test func calendarPeriodsRemainInclusiveAcrossDST() {
        var cal=Calendar(identifier:.gregorian);cal.timeZone=TimeZone(identifier:"Europe/Vienna")!
        let now=ISO8601DateFormatter().date(from:"2026-10-26T12:00:00Z")!
        let model=SystemLogsViewModel(repository:JournalAudit17Repository(),calendar:cal,nowProvider:{now})
        model.datePreset = .thirtyDays
        #expect(model.queryFilter.startDate==cal.date(byAdding:.day,value:-29,to:cal.startOfDay(for:now)))
        model.toggleFilter(.today)
        #expect(model.queryFilter.startDate==cal.startOfDay(for:now))
        #expect(model.queryFilter.endDate==cal.date(byAdding:.day,value:1,to:cal.startOfDay(for:now))?.addingTimeInterval(-0.001))
    }

    @Test func mfaPreconditionIsNotAnIndexFailure() {
        let mfa=NSError(domain:FunctionsErrorDomain,code:FunctionsErrorCode.failedPrecondition.rawValue,
            userInfo:[NSLocalizedDescriptionKey:"A passkey or authenticator-verified session is required for this privileged account."])
        #expect(SystemLogFailureKind(mfa) == .session)
        let unknown=NSError(domain:FunctionsErrorDomain,code:FunctionsErrorCode.failedPrecondition.rawValue)
        #expect(SystemLogFailureKind(unknown) == .requirements)
    }

    @Test func journalRoutesRequireAnActiveGlobalApplicationRole() {
        for role: GlobalRole in [.owner,.admin,.user] {
            let user=AppUser(id:"role-fixture",fullName:"Role Fixture",city:"Vienna",email:"fixture@example.com",bio:"",role:.user,globalRole:role,blockState:.active,createdAt:.now,updatedAt:.now)
            let policy=ProfileAccessPolicy(user:user)
            #expect(policy.allows(.systemLogs(.owner)) == (role == .owner))
            #expect(policy.allows(.systemLogs(.appAdmin)) == (role == .admin))
            #expect(policy.allows(.systemLogDetail("fixture")) == (role == .owner))
        }
        let blocked=AppUser(id:"blocked",fullName:"Blocked",city:"Vienna",email:"fixture@example.com",bio:"",role:.user,globalRole:.owner,blockState:.bannedPermanent,createdAt:.now,updatedAt:.now)
        #expect(!ProfileAccessPolicy(user:blocked).allows(.systemLogs(.owner)))
        #expect(!ProfileAccessPolicy(user:nil).allows(.systemLogs(.owner)))
        #expect(!ProfileAccessPolicy(user:nil).allows(.systemLogs(.appAdmin)))
    }

    @Test func returningToOriginalQueryDuringDebounceReloadsDiscardedRows() async throws {
        let row=try #require(MockSystemLogRepository.sampleEntries.first)
        let repo=JournalAudit17Repository();repo.page = .init(entries:[row],cursor:nil)
        let model=SystemLogsViewModel(repository:repo);await model.refresh()
        model.searchText="different"
        let changed=Task{await model.queryChanged()};while !model.logs.isEmpty {await Task.yield()}
        changed.cancel();await changed.value
        model.searchText="";await model.queryChanged()
        #expect(model.logs==[row]);#expect(model.hasLoadedInitialPage && !model.isLoading)
    }
    @Test func deniedListInvalidatesAlreadyPendingExactRead() async throws {
        let row=try #require(MockSystemLogRepository.sampleEntries.first)
        let repo=JournalAudit17Repository();repo.page = .init(entries:[row],cursor:nil);repo.suspendDetail=true
        let model=SystemLogsViewModel(repository:repo);await model.refresh()
        let read=Task{await model.refreshLogDetail(id:row.id)};while repo.detailContinuation==nil {await Task.yield()}
        repo.pageError=NSError(domain:FunctionsErrorDomain,code:FunctionsErrorCode.permissionDenied.rawValue)
        await model.refresh();repo.detailContinuation!.resume(returning:row);await read.value
        #expect(model.log(id:row.id)==nil && model.accessDenied)
        #expect(model.refreshingDetailLogIDs.isEmpty)
    }

    @Test func dateFilterUsesIntegerMillisecondsAcceptedByCallable() throws {
        var cal=Calendar(identifier:.gregorian);cal.timeZone=TimeZone(identifier:"Europe/Vienna")!
        let now=ISO8601DateFormatter().date(from:"2026-10-26T12:00:00Z")!
        let model=SystemLogsViewModel(repository:JournalAudit17Repository(),calendar:cal,nowProvider:{now})
        model.datePreset = .sevenDays
        let encoded=try FirestoreSystemLogRepository.requestFilter(model.queryFilter)
        let start=try #require(encoded["startDate"] as? NSNumber),end=try #require(encoded["endDate"] as? NSNumber)
        #expect(start.doubleValue == Double(start.int64Value))
        #expect(end.doubleValue == Double(end.int64Value))
        #expect(end.int64Value == Int64((cal.date(byAdding:.day,value:1,to:cal.startOfDay(for:now))!.timeIntervalSince1970 * 1000).rounded()) - 1)
    }

}
