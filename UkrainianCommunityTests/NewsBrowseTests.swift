import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct NewsBrowseTests {
    let now = Date(timeIntervalSince1970: 1_788_800_000)
    func post(_ id: String, category: NewsCategory = .housing, additional: [NewsCategory] = [],
              offset: Double = 0, region: AustrianFederalState? = .wien) -> NewsPost {
        let date = now.addingTimeInterval(offset)
        return NewsPost(id: id, title: id, subtitle: "Subtitle",
                        regionScope: region == nil ? .austria : .federalState, federalState: region,
                        category: category, additionalCategories: additional, body: "Body", authorName: "UAC",
                        publishedAt: date, createdAt: date, updatedAt: date, comments: [],
                        moderationStatus: .approved, likeCount: 0, likeState: .notLiked)
    }
    @Test func topicIncludesAdditionalCategoryAndNationalNewsBeforePagination() async throws {
        let repository = MockNewsRepository(seededNews: (0..<35).map { post("other-\($0)", category: .transport) }
            + [post("national", category: .work, additional: [.housing], region: nil),
               post("vienna"), post("tirol", region: .tirol)])
        var filter = NewsBrowseFilter(); filter.topic = .housing
        let query = NewsBrowseQuery(filter: filter, region: .wien, referenceDate: now)
        let page = try await repository.fetchNewsBrowsePage(query: query, limit: 1, after: nil)
        #expect(page.items.map(\.id) == ["vienna"])
        let second = try await repository.fetchNewsBrowsePage(query: query, limit: 1, after: page.nextCursor)
        #expect(second.items.map(\.id) == ["national"])
        #expect(!second.hasMore)
    }
    @Test func bothSortDirectionsHaveStableTiesAcrossPages() async throws {
        let repository = MockNewsRepository(seededNews: [post("a"),post("b"),post("old",offset: -100)])
        for oldest in [false,true] {
            var filter = NewsBrowseFilter(); filter.oldestFirst = oldest
            let query = NewsBrowseQuery(filter: filter, region: nil, referenceDate: now)
            var cursor: NewsPageCursor?
            var ids: [String] = []
            for _ in 0..<3 {
                let page = try await repository.fetchNewsBrowsePage(query: query, limit: 1, after: cursor)
                ids += page.items.map(\.id); cursor = page.nextCursor
            }
            #expect(ids == (oldest ? ["old","a","b"] : ["b","a","old"]))
        }
    }
    @Test func customDateIncludesWholeLastDayAndHandlesDST() {
        let calendar = NewsBrowseFilter.calendar
        let date = calendar.date(from: DateComponents(year: 2026, month: 3, day: 29))!
        var filter = NewsBrowseFilter(); filter.period = .custom; filter.startDate = date; filter.endDate = date
        let bounds = filter.bounds(at: now)
        #expect(bounds.end!.timeIntervalSince(bounds.start!) == 23 * 3600)
        let query = NewsBrowseQuery(filter: filter, region: nil, referenceDate: now)
        #expect(query.matches(post("end", offset: bounds.end!.timeIntervalSince(now) - 1)))
        #expect(!query.matches(post("next", offset: bounds.end!.timeIntervalSince(now))))
    }
    @Test func delayedOldQueryCannotReplaceNewSelection() async {
        var release: CheckedContinuation<NewsPage, Never>?
        let model = NewsBrowseViewModel { query, _, _ in
            if query.filter.topic == .housing {
                return await withCheckedContinuation { release = $0 }
            }
            return NewsPage(items: [post("new")], nextCursor: nil, hasMore: false)
        }
        var first = NewsBrowseFilter(); first.topic = .housing
        let old = Task { await model.reload(NewsBrowseQuery(filter: first, region: nil, referenceDate: now), visibility: .init()) }
        while release == nil { await Task.yield() }
        await model.reload(NewsBrowseQuery(filter: .init(), region: nil, referenceDate: now), visibility: .init())
        release?.resume(returning: NewsPage(items: [post("stale")], nextCursor: nil, hasMore: false))
        await old.value
        #expect(model.posts.map(\.id) == ["new"])
        #expect(!model.loading)
    }
    @Test func emptyScannedPagesDoNotClaimEndOfResults() async {
        var calls = 0
        let model = NewsBrowseViewModel { _, _, _ in
            calls += 1
            return NewsPage(items: [], nextCursor: NewsPageCursor(publishedAt: now, documentID: "\(calls)"), hasMore: true)
        }
        await model.reload(NewsBrowseQuery(filter: .init(), region: nil, referenceDate: now), visibility: .init())
        #expect(calls == 4)
        #expect(model.hasMore && model.posts.isEmpty)
        #expect(model.error == nil)
    }
    @Test func refreshPreservesVisibleRowsUntilResponseButAccountSwitchClearsThem() async {
        var release: CheckedContinuation<NewsPage, Never>?
        var first = true
        let model = NewsBrowseViewModel { _, _, _ in
            if first {
                first = false
                return NewsPage(items: [post("current")], nextCursor: nil, hasMore: false)
            }
            return await withCheckedContinuation { release = $0 }
        }
        let query = NewsBrowseQuery(filter: .init(), region: nil, referenceDate: now)
        await model.reload(query, visibility: .init())
        let refresh = Task { await model.reload(query, visibility: .init()) }
        while release == nil { await Task.yield() }
        #expect(model.posts.map(\.id) == ["current"])
        model.clear()
        #expect(model.posts.isEmpty)
        release?.resume(returning: NewsPage(items: [post("old-account")], nextCursor: nil, hasMore: false))
        await refresh.value
        #expect(model.posts.isEmpty)
    }

    @Test func errorsAndAccountClearDoNotBecomeEmptySuccess() async {
        let model = NewsBrowseViewModel { _, _, _ in throw AppError.network }
        await model.reload(NewsBrowseQuery(filter: .init(), region: nil, referenceDate: now), visibility: .init())
        #expect(model.error != nil)
        model.clear()
        #expect(model.error == nil && model.posts.isEmpty && !model.hasMore)
    }
}
