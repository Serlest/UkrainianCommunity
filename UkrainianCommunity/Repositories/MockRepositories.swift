import Foundation

private actor MockRepositoryStore {
    static let shared = MockRepositoryStore()

    var user = MockContentBuilder.currentUser()
    var news = MockContentBuilder.newsPosts()
    var events = MockContentBuilder.events()
    var organizations = MockContentBuilder.organizations()
    var marketplaceItems = MockContentBuilder.marketplaceItems()
    var infoItems = MockContentBuilder.infoItems()

    func toggleNewsLike(id: String, isLiked: Bool) throws {
        guard let index = news.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
        news[index].likeState = isLiked ? .liked : .notLiked
        news[index].likeCount += isLiked ? 1 : -1
    }

    func createNews(_ item: NewsPost) {
        news.insert(item, at: 0)
    }

    func toggleEventLike(id: String, isLiked: Bool) throws {
        guard let index = events.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
        events[index].likeState = isLiked ? .liked : .notLiked
        events[index].likeCount += isLiked ? 1 : -1
    }

    func setEventRegistration(id: String, isRegistered: Bool) throws {
        guard let index = events.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
        events[index].registrationState = isRegistered ? .registered : .notRegistered
    }

    func toggleOrganizationLike(id: String, isLiked: Bool) throws {
        guard let index = organizations.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
        organizations[index].likeState = isLiked ? .liked : .notLiked
        organizations[index].likeCount += isLiked ? 1 : -1
    }

    func toggleMarketplaceLike(id: String, isLiked: Bool) throws {
        guard let index = marketplaceItems.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
        marketplaceItems[index].likeState = isLiked ? .liked : .notLiked
        marketplaceItems[index].likeCount += isLiked ? 1 : -1
    }
}

struct MockUserRepository: UserRepository {
    private let store = MockRepositoryStore.shared

    func fetchCurrentUser() async throws -> AppUser {
        await store.user
    }

    func fetchSettings() async throws -> UserSettings {
        .stored
    }
}

struct MockNewsRepository: NewsRepository {
    private let store = MockRepositoryStore.shared

    func fetchNews() async throws -> [NewsPost] {
        await store.news
    }

    func createNews(_ news: NewsPost) async throws {
        await store.createNews(news)
    }

    func likeNews(id: String) async throws {
        try await store.toggleNewsLike(id: id, isLiked: true)
    }

    func unlikeNews(id: String) async throws {
        try await store.toggleNewsLike(id: id, isLiked: false)
    }
}

struct MockEventRepository: EventRepository {
    private let store = MockRepositoryStore.shared

    func fetchEvents() async throws -> [Event] {
        await store.events
    }

    func likeEvent(id: String) async throws {
        try await store.toggleEventLike(id: id, isLiked: true)
    }

    func unlikeEvent(id: String) async throws {
        try await store.toggleEventLike(id: id, isLiked: false)
    }

    func registerForEvent(id: String) async throws {
        try await store.setEventRegistration(id: id, isRegistered: true)
    }

    func cancelEventRegistration(id: String) async throws {
        try await store.setEventRegistration(id: id, isRegistered: false)
    }
}

struct MockOrganizationRepository: OrganizationRepository {
    private let store = MockRepositoryStore.shared

    func fetchOrganizations() async throws -> [Organization] {
        await store.organizations
    }

    func likeOrganization(id: String) async throws {
        try await store.toggleOrganizationLike(id: id, isLiked: true)
    }

    func unlikeOrganization(id: String) async throws {
        try await store.toggleOrganizationLike(id: id, isLiked: false)
    }
}

struct MockMarketplaceRepository: MarketplaceRepository {
    private let store = MockRepositoryStore.shared

    func fetchMarketplaceItems() async throws -> [MarketplaceItem] {
        await store.marketplaceItems
    }

    func likeMarketplaceItem(id: String) async throws {
        try await store.toggleMarketplaceLike(id: id, isLiked: true)
    }

    func unlikeMarketplaceItem(id: String) async throws {
        try await store.toggleMarketplaceLike(id: id, isLiked: false)
    }
}

struct MockInfoRepository: InfoRepository {
    private let store = MockRepositoryStore.shared

    func fetchInfoItems() async throws -> [InfoItem] {
        await store.infoItems
    }
}
