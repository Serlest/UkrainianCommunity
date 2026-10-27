import Foundation
import Testing
@testable import UkrainianCommunity

/// Regression coverage for exact failed-cursor retry and retained pages.
@MainActor struct PublicationControlPagingTests {
    private func overview(_ day: String) -> PublicationControlOverview { .init(day: day, serverTime: 1, news: 3, events: 0, regions: [], sources: [], syncedAt: nil) }
    private func item(_ id: String) -> PublicationControlItem { .init(id: id, kind: "news", contentId: id, titleUK: id, titleDE: id, region: "tirol", firstPublicAt: 1, sourceState: "approved", timingSource: "creation") }
    private func run(_ id: String) -> PublicationControlRun { .init(id: id, kind: "news", region: "tirol", runId: id, status: "complete", endedAt: 1, timestampBasis: "reportCompletedAt", published: 0, candidates: 0, rejected: 0, sourcesExpected: 0, sourcesChecked: 0, issues: [], issueCount: 0, publicationOnly: false) }
    @Test func itemRetryMustContinueFailedThirdPageAndKeepFirstTwo() async {
        var calls: [String] = []; var failed = false
        let store = PublicationControlStore(api: .init(overview: { _,day in overview(day) }, items: { _,_,_,cursor in
            calls.append(cursor ?? "first")
            if cursor == "third", !failed { failed = true; throw AppError.network }
            return .init(items: [item(cursor ?? "first")], cursor: cursor == nil ? "second" : cursor == "second" ? "third" : nil, total: 3)
        }, runs: { _,_,_ in .init(runs: [], cursor: nil) }))
        await store.load(actor: "owner", day: "2026-10-26")
        await store.loadItems(region: "tirol"); await store.loadItems(region: "tirol", more: true); await store.loadItems(region: "tirol", more: true)
        #expect(store.items.map(\.id) == ["first", "second"])
        await store.loadItems(region: "tirol") // The actual error button's action.
        #expect(calls.last == "third", "Retry must use the failed cursor; observed calls: \(calls)")
        #expect(store.items.map(\.id) == ["first", "second", "third"])
    }
    @Test func historyRetryMustContinueFailedThirdPageAndKeepFirstTwo() async {
        var calls: [String] = []; var failed = false
        let store = PublicationControlStore(api: .init(overview: { _,day in overview(day) }, items: { _,_,_,_ in .init(items: [], cursor: nil, total: 0) }, runs: { _,_,cursor in
            calls.append(cursor ?? "first")
            if cursor == "third", !failed { failed = true; throw AppError.network }
            return .init(runs: [run(cursor ?? "first")], cursor: cursor == nil ? "second" : cursor == "second" ? "third" : nil)
        }))
        await store.load(actor: "owner", day: "2026-10-26")
        await store.loadRuns(); await store.loadRuns(more: true); await store.loadRuns(more: true)
        #expect(store.runs.map(\.id) == ["first", "second"])
        await store.loadRuns() // The actual error button's action.
        #expect(calls.last == "third", "Retry must use the failed cursor; observed calls: \(calls)")
        #expect(store.runs.map(\.id) == ["first", "second", "third"])
    }
}

extension PublicationControlPagingTests {
    @Test func regionalHistoryRejectsLateResponseAfterReturningToSameRegion() async {
        var pause: CheckedContinuation<PublicationControlRunsPage, Never>?
        var first = true
        let store = PublicationControlStore(api: .init(overview: { _,day in overview(day) }, items: { _,_,_,_ in .init(items: [], cursor: nil, total: 0) }, runs: { _,region,_ in
            if region == "tirol", first { first = false; return await withCheckedContinuation { pause = $0 } }
            return .init(runs: [run(region ?? "all")], cursor: nil)
        }))
        await store.load(actor: "owner", day: "2026-10-27")
        let old = Task { await store.loadRuns(region: "tirol") }; while pause == nil { await Task.yield() }
        await store.loadRuns(region: "wien"); await store.loadRuns(region: "tirol")
        pause?.resume(returning: .init(runs: [run("obsolete")], cursor: nil)); await old.value
        #expect(store.runs.map(\.id) == ["tirol"])
    }
    @Test func nextScheduledPassUsesViennaCalendarAcrossDSTAndOvernight() {
        let base = ISO8601DateFormatter().date(from: "2026-10-24T17:05:00Z")!
        var row = run("schedule")
        row.scheduledAt = base.timeIntervalSince1970 * 1000
        row.schedule = .init(hours: [9,14,19], minutes: [0], timeZone: "Europe/Vienna", graceMinutes: 90)
        #expect(PublicationControlText.nextExpected(row) == ISO8601DateFormatter().date(from: "2026-10-25T08:00:00Z"))
        row.schedule = .init(hours: [99], minutes: [0], timeZone: "Europe/Vienna", graceMinutes: 90)
        #expect(PublicationControlText.nextExpected(row) == nil)
        #expect(!PublicationControlText.date(.infinity).isEmpty)
    }
}
