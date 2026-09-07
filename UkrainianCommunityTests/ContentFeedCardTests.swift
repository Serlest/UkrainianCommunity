import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct ContentFeedCardTests {
    @Test func categoryAndDestinationSurviveAllAdapters() throws {
        let news = try #require(MockContentBuilder.newsPosts().first)
        let event = try #require(MockContentBuilder.events().first)
        let organization = try #require(MockContentBuilder.organizations().first)
        let newsItem = HomeFeedItem(post: news)
        let eventItem = HomeFeedItem(event: event)
        let organizationItem = HomeFeedItem(organization: organization)
        #expect(newsItem.cardCategoryTitle == NewsBrowseStrings.topic(news.category))
        #expect(eventItem.cardCategoryTitle == event.category.title)
        #expect(organizationItem.cardCategoryTitle == organization.organizationType.flatMap(OrganizationEditorCategory.init(rawValue:))?.title)
        #expect(newsItem.destination == .news(id: news.id))
        #expect(eventItem.destination == .event(id: event.id))
        #expect(organizationItem.destination == .organization(id: organization.id))
        #expect(OrganizationActivityItem(post: news).feedItem == newsItem)
        #expect(OrganizationActivityItem(event: event).feedItem == eventItem)
        #expect(OrganizationActivityItem(profile: organization).feedItem == organizationItem)
    }

    @Test func missingRegionNeverClaimsNationwideCoverage() {
        let date = Date()
        func item(scope: RegionScope?, region: AustrianFederalState?) -> HomeFeedItem {
            HomeFeedItem(post: NewsPost(id: "region", title: "Title", subtitle: "Subtitle", regionScope: scope,
                federalState: region, body: "Body", authorName: "UAC", publishedAt: date,
                createdAt: date, updatedAt: date, comments: [], moderationStatus: .approved, likeCount: 0, likeState: .notLiked))
        }
        #expect(item(scope: .austria, region: .tirol).cardRegionTitle == NewsBrowseStrings.text("austria"))
        #expect(item(scope: .federalState, region: .tirol).cardRegionTitle == AustrianFederalState.tirol.displayName)
        #expect(item(scope: nil, region: nil).cardRegionTitle == nil)
    }

    @Test func eventScheduleAndRegistrationSurviveUnification() throws {
        for event in MockContentBuilder.events() {
            let item = HomeFeedItem(event: event)
            let occurrence = event.nextOccurrence() ?? event.occurrences.first
            #expect(item.eventStartDate == occurrence?.startDate ?? event.startDate)
            #expect(item.eventEndDate == occurrence?.endDate ?? event.endDate)
            #expect(item.eventIsAllDay == occurrence?.isAllDay ?? event.isAllDay)
            #expect(item.eventRegistrationTitle == event.registrationState.title)
        }
    }
}
