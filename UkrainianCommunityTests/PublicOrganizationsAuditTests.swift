import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct PublicOrganizationsAuditTests {
    @Test func rapidNewsToEventsSwitchLoadsBothSections() async throws {
        let organization = MockContentBuilder.organizations()[0]
        var release: CheckedContinuation<[OrganizationActivityItem], Error>?
        var requests: [OrganizationActivityItemType] = []
        let model = OrganizationActivityViewModel(organizationID: organization.id, organizationName: organization.name,
            newsRepository: MockNewsRepository(), eventRepository: MockEventRepository(), activityLoader: { type in
                requests.append(type)
                if type == .news { return try await withCheckedThrowingContinuation { release = $0 } }
                return []
            })
        let news = Task { await model.loadIfNeeded(for: organization, section: .news) }
        while release == nil { await Task.yield() }
        let events = Task { await model.loadIfNeeded(for: organization, section: .events) }
        for _ in 0..<20 { await Task.yield() }
        release?.resume(returning: [])
        await news.value; await events.value
        #expect(requests.contains(.news))
        #expect(requests.contains(.event))
    }
    private func item(_ index: Int, organizationID: String) -> OrganizationActivityItem {
        let date = Date(timeIntervalSince1970: 1_790_000_000 - Double(index))
        return OrganizationActivityItem(post: NewsPost(id: "item-\(index)",
            localizations: ["uk": NewsLocalizedContent(title: "Localized", subtitle: "Summary", body: "Body"),
                            "de": NewsLocalizedContent(title: "Localized", subtitle: "Summary", body: "Body")],
            title: "Raw", subtitle: "Raw summary",
            source: ContentSourceMetadata(sourceType: .organization, organizationId: organizationID),
            body: "Body", authorName: "Author", publishedAt: date, createdAt: date, updatedAt: date,
            comments: [], moderationStatus: .approved, likeCount: 0, likeState: .notLiked))
    }
    @Test func activityUsesLocalizedContent() {
        #expect(item(0, organizationID: "org").title == "Localized")
    }
    @Test func publicationPagesExposeAllItemsWithoutDuplicates() async {
        let organization = MockContentBuilder.organizations()[0]
        let items = (0..<26).map { item($0, organizationID: organization.id) }
        var reads = 0
        let model = OrganizationActivityViewModel(organizationID: organization.id, organizationName: organization.name,
            newsRepository: MockNewsRepository(), eventRepository: MockEventRepository(), pageLoader: { _, cursor in
                reads += 1
                return .mock(items: items, limit: 12, after: cursor)
            })
        await model.loadIfNeeded(for: organization, section: .news)
        #expect(model.items.filter { $0.itemType == .news }.count == 12)
        await model.loadMore(for: organization, section: .news)
        await model.loadMore(for: organization, section: .news)
        #expect(model.items.filter { $0.itemType == .news }.count == 26)
        #expect(Set(model.items.map(\.id)).count == model.items.count)
        #expect(!model.hasMore(section: .news) && reads == 3)
    }
    @Test func failedPageRetainsRowsAndRetriesSameCursor() async {
        let organization = MockContentBuilder.organizations()[0]
        let items = (0..<26).map { item($0, organizationID: organization.id) }
        var cursors: [OrganizationActivityCursor?] = []
        let model = OrganizationActivityViewModel(organizationID: organization.id, organizationName: organization.name,
            newsRepository: MockNewsRepository(), eventRepository: MockEventRepository(), pageLoader: { _, cursor in
                cursors.append(cursor)
                if cursors.count == 2 { throw AppError.network }
                return .mock(items: items, limit: 12, after: cursor)
            })
        await model.loadIfNeeded(for: organization, section: .news)
        await model.loadMore(for: organization, section: .news)
        #expect(model.items.filter { $0.itemType == .news }.count == 12)
        #expect(model.error(section: .news) == .network)
        #expect(model.error(section: .events) == nil)
        await model.loadMore(for: organization, section: .news)
        #expect(cursors[1] == cursors[2])
        #expect(model.items.filter { $0.itemType == .news }.count == 24)
    }
    @Test func accountResetRejectsLateActivityResponse() async {
        let organization = MockContentBuilder.organizations()[0]
        var release: CheckedContinuation<[OrganizationActivityItem], Error>?
        let oldItem = item(0, organizationID: organization.id)
        let model = OrganizationActivityViewModel(organizationID: organization.id, organizationName: organization.name,
            newsRepository: MockNewsRepository(), eventRepository: MockEventRepository(), activityLoader: { _ in
                try await withCheckedThrowingContinuation { release = $0 }
            })
        let old = Task { await model.loadIfNeeded(for: organization, section: .news) }
        while release == nil { await Task.yield() }
        model.reset()
        release?.resume(returning: [oldItem])
        await old.value
        #expect(model.items.isEmpty && !model.hasLoaded(section: .news))
    }
    @Test func ongoingEventsRemainVisibleAndFinishedEventsDoNot() {
        let start = Date().addingTimeInterval(-86400)
        let event = Event(id: "ongoing", title: "Event", summary: "Summary", details: "Details", city: "Wien", venue: "Hall",
            startDate: start, endDate: start.addingTimeInterval(2 * 86400), createdAt: start, updatedAt: start,
            capacity: nil, registeredCount: 0, comments: [], moderationStatus: .approved, registrationState: .notRegistered,
            likeCount: 0, likeState: .notLiked)
        let item = OrganizationActivityItem(event: event)
        #expect(item.isUpcomingEvent())
        #expect(!item.isUpcomingEvent(at: event.endDate.addingTimeInterval(1)))
    }
    @Test func activityFailurePreservesConfirmedProfileInsteadOfPretendingAnEmptySuccess() async {
        let organization = MockContentBuilder.organizations()[0]
        let model = OrganizationActivityViewModel(organizationID: organization.id, organizationName: organization.name,
            newsRepository: MockNewsRepository(), eventRepository: MockEventRepository(), activityLoader: { _ in throw AppError.network })
        await model.loadIfNeeded(for: organization, section: .about)
        await model.loadIfNeeded(for: organization, section: .news)
        #expect(model.error == .network)
        #expect(!model.items.isEmpty)
        // The UI must inspect the selected section's load state, not items.isEmpty:
        // this array still contains the organization profile after a failed news read.
        #expect(model.items.allSatisfy { $0.itemType == .organizationProfile })
    }
}
