import Foundation

struct AppContainer {
    let userRepository: UserRepository
    let feedbackRepository: FeedbackRepository
    let contentSafetyRepository: ContentSafetyRepository
    let userBlockingRepository: UserBlockingRepository
    let notificationPreferencesRepository: NotificationPreferencesRepository
    let notificationInboxRepository: NotificationInboxRepository
    let notificationPushTokenRepository: NotificationPushTokenRepository
    let ownerContentDraftRepository: OwnerContentDraftRepository
    let notificationPermissionService: NotificationPermissionServiceProtocol
    let localEventReminderService: LocalEventReminderServiceProtocol
    let newsRepository: NewsRepository
    let eventRepository: EventRepository
    let organizationRepository: OrganizationRepository
    let featuredBannerRepository: FeaturedBannerRepository
    let featuredBannerCache: FeaturedBannerCache
    let legalDocumentRepository: LegalDocumentRepository
    let ownerAnalyticsRepository: OwnerAnalyticsRepository
    let analyticsService: AnalyticsTracking

    static var development: AppContainer {
        AppContainer(
            userRepository: FirestoreUserRepository(),
            feedbackRepository: FirestoreFeedbackRepository(),
            contentSafetyRepository: CloudContentSafetyRepository(),
            userBlockingRepository: CloudUserBlockingRepository(),
            notificationPreferencesRepository: FirestoreNotificationPreferencesRepository(),
            notificationInboxRepository: FirestoreNotificationInboxRepository(),
            notificationPushTokenRepository: FirestoreNotificationPushTokenRepository(),
            ownerContentDraftRepository: FirestoreOwnerContentDraftRepository(),
            notificationPermissionService: NotificationPermissionService(),
            localEventReminderService: LocalEventReminderService(),
            newsRepository: FirestoreNewsRepository(),
            eventRepository: FirestoreEventRepository(),
            organizationRepository: FirestoreOrganizationRepository(),
            featuredBannerRepository: FirestoreFeaturedBannerRepository(),
            featuredBannerCache: FeaturedBannerCache(),
            legalDocumentRepository: FirestoreLegalDocumentRepository(),
            ownerAnalyticsRepository: FirestoreOwnerAnalyticsRepository(),
            analyticsService: FirstPartyAnalyticsService()
        )
    }

    static var uiTesting: AppContainer {
        AppContainer(
            userRepository: MockUserRepository(),
            feedbackRepository: MockFeedbackRepository(),
            contentSafetyRepository: MockContentSafetyRepository(),
            userBlockingRepository: MockUserBlockingRepository(),
            notificationPreferencesRepository: MockNotificationPreferencesRepository(),
            notificationInboxRepository: MockNotificationInboxRepository(),
            notificationPushTokenRepository: MockNotificationPushTokenRepository(),
            ownerContentDraftRepository: MockOwnerContentDraftRepository(),
            notificationPermissionService: MockNotificationPermissionService(),
            localEventReminderService: MockLocalEventReminderService(),
            newsRepository: MockNewsRepository(),
            eventRepository: MockEventRepository(),
            organizationRepository: MockOrganizationRepository(),
            featuredBannerRepository: MockFeaturedBannerRepository(),
            featuredBannerCache: FeaturedBannerCache(),
            legalDocumentRepository: MockLegalDocumentRepository(),
            ownerAnalyticsRepository: MockOwnerAnalyticsRepository(),
            analyticsService: NoopAnalyticsService()
        )
    }
}
