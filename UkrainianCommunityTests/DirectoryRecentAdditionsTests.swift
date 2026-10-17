import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct DirectoryRecentAdditionsTests {
    private func item(_ id: String) -> DirectoryRecentAddition {
        .init(id: id, kind: .topic, categoryID: "registration", topicID: "housing-types", sectionID: nil,
              federalState: nil, publishedAt: "2026-10-17T12:00:00.000Z", revision: 1,
              title: .init(ukrainian: "Назва", german: "Titel"),
              topicTitle: .init(ukrainian: "Тема", german: "Thema"),
              categoryTitle: .init(ukrainian: "Категорія", german: "Kategorie"))
    }

    @Test func paginationPreservesOrderDeduplicatesAndStopsNonAdvancingCursor() async {
        let cursor = DirectoryRecentCursor(seconds: 100, nanoseconds: 42, id: "b")
        var requests: [DirectoryRecentCursor?] = []
        let store = DirectoryRecentAdditionsStore { requested in
            requests.append(requested)
            return .init(items: requested == nil ? [item("c"), item("b")] : [item("b"), item("a")],
                         nextCursor: cursor, hasMore: true)
        }
        await store.loadIfNeeded()
        await store.loadIfNeeded()
        #expect(requests.count == 1)
        await store.load(reset: false)
        #expect(store.items.map(\.id) == ["c", "b", "a"])
        #expect(requests.last! == cursor)
        #expect(!store.hasMore)
    }

    @Test func failedRefreshKeepsContentAndRetryReplacesPage() async {
        var fail = false
        var newPage = false
        let store = DirectoryRecentAdditionsStore { _ in
            if fail { throw AppError.network }
            return .init(items: [item(newPage ? "new" : "old")], nextCursor: nil, hasMore: false)
        }
        await store.loadIfNeeded()
        fail = true
        await store.load(reset: true)
        #expect(store.failed && store.items.map(\.id) == ["old"])
        fail = false; newPage = true
        await store.retry()
        #expect(!store.failed && store.items.map(\.id) == ["new"])
    }

    @Test func failedFirstLoadRetriesAndEmptyHasNoFakeHistory() async {
        var fail = true
        let store = DirectoryRecentAdditionsStore { _ in
            if fail { throw AppError.network }
            return .init(items: [], nextCursor: nil, hasMore: false)
        }
        await store.loadIfNeeded()
        #expect(store.failed && store.items.isEmpty)
        fail = false
        await store.loadIfNeeded()
        #expect(!store.failed && store.items.isEmpty && !store.hasMore)
    }

    @Test func wireDecodingPreservesNanosecondCursorAndRegionalSection() throws {
        let data = Data("""
        {"items":[{"id":"new","kind":"section","categoryID":"cat","topicID":"topic","sectionID":"block","federalState":"wien","publishedAt":"2026-10-17T12:00:00.123Z","revision":2,"title":{"ukrainian":"Новий","german":"Neu"},"topicTitle":{"ukrainian":"Тема","german":"Thema"},"categoryTitle":{"ukrainian":"Кат","german":"Kat"}}],"nextCursor":{"seconds":100,"nanoseconds":123456789,"id":"new"},"hasMore":true}
        """.utf8)
        let page = try JSONDecoder().decode(DirectoryRecentPage.self, from: data)
        #expect(page.nextCursor?.nanoseconds == 123456789)
        #expect(page.items.first?.sectionID == "block")
        #expect(page.items.first?.date != nil)
        #expect(item("x").date != nil)
    }
    @Test func regionalDestinationUsesExactVisibleSectionAndRejectsStaleTargets() {
        let text = DirectoryText(ukrainian: "Текст", german: "Text")
        let section = DirectoryManagedSection(id: "block", order: 0, isHidden: false,
            title: text, body: text, symbol: "info.circle", contacts: [])
        var topic = DirectoryManagedTopic(id: "topic", groupID: "g", order: 0, isHidden: false,
            title: text, summary: text, sections: [], sources: [], regionalSections: ["wien": [section]])
        let regional = DirectoryRecentAddition(id: "r", kind: .section, categoryID: "cat", topicID: "topic",
            sectionID: "block", federalState: "wien", publishedAt: "", revision: 1,
            title: text, topicTitle: text, categoryTitle: text)
        #expect(regional.isAvailable(in: topic))
        topic.regionalSections["wien"]?[0].isHidden = true
        #expect(!regional.isAvailable(in: topic))
        topic.regionalSections = ["tirol": [section]]
        #expect(!regional.isAvailable(in: topic))
        topic.regionalSections = ["wien": [section]]
        topic.isHidden = true
        #expect(!regional.isAvailable(in: topic))
    }

}
