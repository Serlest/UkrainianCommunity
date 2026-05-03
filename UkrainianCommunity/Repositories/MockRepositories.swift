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

    func pendingNews() -> [NewsPost] {
        news
            .filter { $0.moderationStatus == .pendingReview }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func deleteNews(id: String) throws {
        guard let index = news.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
        news.remove(at: index)
    }

    func updateNewsModerationStatus(id: String, newStatus: ModerationStatus) throws {
        guard let index = news.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
        news[index].moderationStatus = newStatus
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

    func createEvent(_ item: Event) {
        events.append(item)
        events.sort { $0.startDate < $1.startDate }
    }

    func pendingEvents() -> [Event] {
        events
            .filter { $0.moderationStatus == .pendingReview }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func deleteEvent(id: String) throws {
        guard let index = events.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
        events.remove(at: index)
    }

    func updateEventModerationStatus(id: String, newStatus: ModerationStatus) throws {
        guard let index = events.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
        events[index].moderationStatus = newStatus
    }

    func toggleOrganizationLike(id: String, isLiked: Bool) throws {
        guard let index = organizations.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
        organizations[index].likeState = isLiked ? .liked : .notLiked
        organizations[index].likeCount += isLiked ? 1 : -1
    }

    func pendingOrganizations() -> [Organization] {
        organizations
            .filter { $0.moderationStatus == .pendingReview }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func updateOrganizationModerationStatus(id: String, newStatus: ModerationStatus) throws {
        guard let index = organizations.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
        organizations[index].moderationStatus = newStatus
    }

    func toggleMarketplaceLike(id: String, isLiked: Bool) throws {
        guard let index = marketplaceItems.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
        marketplaceItems[index].likeState = isLiked ? .liked : .notLiked
        marketplaceItems[index].likeCount += isLiked ? 1 : -1
    }

    func pendingMarketplaceItems() -> [MarketplaceItem] {
        marketplaceItems
            .filter { $0.moderationStatus == .pendingReview }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func updateMarketplaceModerationStatus(id: String, newStatus: ModerationStatus) throws {
        guard let index = marketplaceItems.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
        marketplaceItems[index].moderationStatus = newStatus
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
            .filter { $0.moderationStatus == .approved }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func fetchPendingNews() async throws -> [NewsPost] {
        await store.pendingNews()
    }

    func createNews(_ news: NewsPost) async throws {
        await store.createNews(news)
    }

    func deleteNews(id: String) async throws {
        try await store.deleteNews(id: id)
    }

    func likeNews(id: String) async throws {
        try await store.toggleNewsLike(id: id, isLiked: true)
    }

    func unlikeNews(id: String) async throws {
        try await store.toggleNewsLike(id: id, isLiked: false)
    }

    func updateModerationStatus(id: String, newStatus: ModerationStatus) async throws {
        try await store.updateNewsModerationStatus(id: id, newStatus: newStatus)
    }
}

struct MockEventRepository: EventRepository {
    private let store = MockRepositoryStore.shared

    func fetchEvents() async throws -> [Event] {
        await store.events
            .filter { $0.moderationStatus == .approved }
            .sorted { $0.startDate < $1.startDate }
    }

    func fetchPendingEvents() async throws -> [Event] {
        await store.pendingEvents()
    }

    func createEvent(_ event: Event) async throws {
        await store.createEvent(event)
    }

    func deleteEvent(id: String) async throws {
        try await store.deleteEvent(id: id)
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

    func updateModerationStatus(id: String, newStatus: ModerationStatus) async throws {
        try await store.updateEventModerationStatus(id: id, newStatus: newStatus)
    }
}

struct MockOrganizationRepository: OrganizationRepository {
    private let store = MockRepositoryStore.shared

    func fetchOrganizations() async throws -> [Organization] {
        await store.organizations
            .filter { $0.moderationStatus == .approved }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func fetchPendingOrganizations() async throws -> [Organization] {
        await store.pendingOrganizations()
    }

    func likeOrganization(id: String) async throws {
        try await store.toggleOrganizationLike(id: id, isLiked: true)
    }

    func unlikeOrganization(id: String) async throws {
        try await store.toggleOrganizationLike(id: id, isLiked: false)
    }

    func updateModerationStatus(id: String, newStatus: ModerationStatus) async throws {
        try await store.updateOrganizationModerationStatus(id: id, newStatus: newStatus)
    }
}

struct MockMarketplaceRepository: MarketplaceRepository {
    private let store = MockRepositoryStore.shared

    func fetchMarketplaceItems() async throws -> [MarketplaceItem] {
        await store.marketplaceItems
            .filter { $0.moderationStatus == .approved }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func fetchPendingMarketplaceItems() async throws -> [MarketplaceItem] {
        await store.pendingMarketplaceItems()
    }

    func likeMarketplaceItem(id: String) async throws {
        try await store.toggleMarketplaceLike(id: id, isLiked: true)
    }

    func unlikeMarketplaceItem(id: String) async throws {
        try await store.toggleMarketplaceLike(id: id, isLiked: false)
    }

    func updateModerationStatus(id: String, newStatus: ModerationStatus) async throws {
        try await store.updateMarketplaceModerationStatus(id: id, newStatus: newStatus)
    }
}

struct MockInfoRepository: InfoRepository {
    private let store = MockRepositoryStore.shared

    func fetchInfoItems() async throws -> [InfoItem] {
        await store.infoItems
    }
}
