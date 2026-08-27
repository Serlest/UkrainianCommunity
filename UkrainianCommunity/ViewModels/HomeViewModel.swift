import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var feedItems: [HomeFeedItem]
    @Published private(set) var isLoading: Bool
    @Published private(set) var error: AppError?

    init(
        newsRepository _: NewsRepository,
        eventRepository _: EventRepository,
        organizationRepository _: OrganizationRepository
    ) {
        feedItems = []
        isLoading = false
    }

    func updateFeed(
        posts: [NewsPost],
        events: [Event],
        organizations: [Organization],
        isLoading: Bool,
        error: AppError?
    ) {
        let postItems = posts.map(HomeFeedItem.init(post:))
        let eventItems = events.map(HomeFeedItem.init(event:))
        let organizationItems = organizations.map(HomeFeedItem.init(organization:))
        let unsortedItems = postItems + eventItems + organizationItems
        var seenItemIDs = Set<String>()
        let updatedFeedItems = unsortedItems.filter {
            seenItemIDs.insert($0.id).inserted
        }.sorted {
            $0.publishedAt == $1.publishedAt ? $0.id < $1.id : $0.publishedAt > $1.publishedAt
        }

        if feedItems != updatedFeedItems {
            feedItems = updatedFeedItems
        }
        if self.isLoading != isLoading {
            self.isLoading = isLoading
        }
        if self.error != error {
            self.error = error
        }
    }

    func resetForAuthChange() {
        feedItems = []
        isLoading = false
        error = nil
    }
}
