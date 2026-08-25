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
        feedItems = (
            posts.map(HomeFeedItem.init(post:))
                + events.map(HomeFeedItem.init(event:))
                + organizations.map(HomeFeedItem.init(organization:))
        )
        .sorted {
            $0.publishedAt == $1.publishedAt ? $0.id < $1.id : $0.publishedAt > $1.publishedAt
        }
        self.isLoading = isLoading
        self.error = error
    }

    func resetForAuthChange() {
        feedItems = []
        isLoading = false
        error = nil
    }
}
