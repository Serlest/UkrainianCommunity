import Foundation

protocol UserRepository {
    func fetchCurrentUser() async throws -> AppUser
    func fetchSettings() async throws -> UserSettings
}

protocol NewsRepository {
    func fetchNews() async throws -> [NewsPost]
    func createNews(_ news: NewsPost) async throws
    func likeNews(id: String) async throws
    func unlikeNews(id: String) async throws
}

protocol EventRepository {
    func fetchEvents() async throws -> [Event]
    func likeEvent(id: String) async throws
    func unlikeEvent(id: String) async throws
    func registerForEvent(id: String) async throws
    func cancelEventRegistration(id: String) async throws
}

protocol OrganizationRepository {
    func fetchOrganizations() async throws -> [Organization]
    func likeOrganization(id: String) async throws
    func unlikeOrganization(id: String) async throws
}

protocol MarketplaceRepository {
    func fetchMarketplaceItems() async throws -> [MarketplaceItem]
    func likeMarketplaceItem(id: String) async throws
    func unlikeMarketplaceItem(id: String) async throws
}

protocol InfoRepository {
    func fetchInfoItems() async throws -> [InfoItem]
}
