import Foundation

struct AppContainer {
    let userRepository: UserRepository
    let newsRepository: NewsRepository
    let eventRepository: EventRepository
    let organizationRepository: OrganizationRepository
    let marketplaceRepository: MarketplaceRepository
    let infoRepository: InfoRepository

    static var development: AppContainer {
        #if DEBUG
        print("AppContainer development created")
        #endif
        return AppContainer(
            userRepository: FirestoreUserRepository(),
            newsRepository: FirestoreNewsRepository(),
            eventRepository: FirestoreEventRepository(),
            organizationRepository: FirestoreOrganizationRepository(),
            marketplaceRepository: FirestoreMarketplaceRepository(),
            infoRepository: MockInfoRepository()
        )
    }
}
