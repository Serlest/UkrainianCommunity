import Foundation

struct AppContainer {
    let userRepository: UserRepository
    let newsRepository: NewsRepository
    let eventRepository: EventRepository
    let organizationRepository: OrganizationRepository
    let marketplaceRepository: MarketplaceRepository
    let infoRepository: InfoRepository

    static let mock = AppContainer(
        userRepository: MockUserRepository(),
        newsRepository: FirestoreNewsRepository(),
        eventRepository: MockEventRepository(),
        organizationRepository: MockOrganizationRepository(),
        marketplaceRepository: MockMarketplaceRepository(),
        infoRepository: MockInfoRepository()
    )
}
