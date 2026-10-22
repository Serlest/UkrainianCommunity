import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor struct PublicationControlTests {
    private func overview(_ day: String, news: Int = 1) -> PublicationControlOverview { .init(day: day, serverTime: 1000, news: news, events: 0, regions: [], sources: [], syncedAt: nil) }
    @Test func staleAccountResponseCannotReplaceNewAccountOverview() async {
        var resume: CheckedContinuation<PublicationControlOverview, any Error>?
        let store = PublicationControlStore(api: .init(overview: { actor, day in
            if actor == "old" { return try await withCheckedThrowingContinuation { resume = $0 } }
            return overview(day, news: 9)
        }, items: { _,_,_,_ in .init(items: [], cursor: nil, total: 0) }, runs: { _,_ in .init(runs: [], cursor: nil) }))
        let old = Task { await store.load(actor: "old", day: "2026-10-22") }
        while resume == nil { await Task.yield() }
        await store.load(actor: "new", day: "2026-10-22")
        resume?.resume(returning: overview("2026-10-22", news: 2)); await old.value
        #expect(store.overview?.news == 9 && !store.loading)
        #expect(store.reportNow(at: store.receivedAt.addingTimeInterval(4 * 3600)) == 1000 + 4 * 3600000)
        store.reset(); #expect(store.overview == nil && store.items.isEmpty && store.runs.isEmpty)
    }
    @Test func regionChangeIgnoresLateItemsAndPaginationDeduplicates() async {
        var resume: CheckedContinuation<PublicationControlItemsPage, any Error>?
        func row(_ id: String, _ region: String) -> PublicationControlItem { .init(id: id, kind: "news", contentId: id, titleUK: "Тест", titleDE: "Test", region: region, firstPublicAt: 1000, sourceState: "approved", timingSource: "creation") }
        let store = PublicationControlStore(api: .init(overview: { _,day in overview(day) }, items: { _,_,region,cursor in
            if region == "wien" { return try await withCheckedThrowingContinuation { resume = $0 } }
            return .init(items: cursor == nil ? [row("1", "tirol")] : [row("1", "tirol"), row("2", "tirol")], cursor: cursor == nil ? "next" : nil, total: 2)
        }, runs: { _,_ in .init(runs: [], cursor: nil) }))
        await store.load(actor: "owner", day: "2026-10-22")
        let old = Task { await store.loadItems(region: "wien") }; while resume == nil { await Task.yield() }
        await store.loadItems(region: "tirol")
        resume?.resume(returning: .init(items: [row("old", "wien")], cursor: nil, total: 1)); await old.value
        #expect(store.items.map(\.id) == ["1"])
        await store.loadItems(region: "tirol", more: true); #expect(store.items.map(\.id) == ["1", "2"] && store.itemCursor == nil)
    }
    @Test func failureKeepsKnownOverviewAndHasExplicitRetryState() async {
        var fail = false
        let store = PublicationControlStore(api: .init(overview: { _,day in if fail { throw AppError.network }; return overview(day) }, items: { _,_,_,_ in throw AppError.network }, runs: { _,_ in throw AppError.network }))
        await store.load(actor: "owner", day: "2026-10-22"); fail = true
        await store.load(actor: "owner", day: "2026-10-22"); #expect(store.overview != nil && store.error != nil && !store.loading)
        await store.loadItems(region: nil); await store.loadRuns(); #expect(store.itemsError != nil && store.runsError != nil && !store.loadingItems && !store.loadingRuns)
    }
}
