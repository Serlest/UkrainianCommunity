import Foundation

struct AppContainer {
    let userRepository: UserRepository
    let newsRepository: NewsRepository
    let eventRepository: EventRepository
    let organizationRepository: OrganizationRepository
    let marketplaceRepository: MarketplaceRepository
    let infoRepository: InfoRepository

    static let development = AppContainer(
        userRepository: MockUserRepository(),
        newsRepository: FirestoreNewsRepository(),
        eventRepository: FirestoreEventRepository(),
        organizationRepository: FirestoreOrganizationRepository(),
        marketplaceRepository: MockMarketplaceRepository(),
        infoRepository: MockInfoRepository()
    )
}
