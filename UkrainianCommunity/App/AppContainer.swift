import Foundation

struct AppContainer {
    let userRepository: UserRepository
    let feedbackRepository: FeedbackRepository
    let newsRepository: NewsRepository
    let eventRepository: EventRepository
    let organizationRepository: OrganizationRepository
    let infoRepository: InfoRepository
    let homeBannerService: HomeBannerServiceProtocol

    static var development: AppContainer {
        return AppContainer(
            userRepository: FirestoreUserRepository(),
            feedbackRepository: FirestoreFeedbackRepository(),
            newsRepository: FirestoreNewsRepository(),
            eventRepository: FirestoreEventRepository(),
            organizationRepository: FirestoreOrganizationRepository(),
            infoRepository: FirestoreGuideRepository(),
            homeBannerService: FirestoreHomeBannerService()
        )
    }

    static var uiTesting: AppContainer {
        AppContainer(
            userRepository: MockUserRepository(),
            feedbackRepository: MockFeedbackRepository(),
            newsRepository: MockNewsRepository(),
            eventRepository: MockEventRepository(),
            organizationRepository: MockOrganizationRepository(),
            infoRepository: MockInfoRepository(),
            homeBannerService: MockHomeBannerService()
        )
    }
}
