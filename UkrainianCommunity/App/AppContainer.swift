import Foundation

struct AppContainer {
    let authState: AuthState
    let userRepository: UserRepository
    let feedbackRepository: FeedbackRepository
    let notificationPreferencesRepository: NotificationPreferencesRepository
    let notificationInboxRepository: NotificationInboxRepository
    let notificationPushTokenRepository: NotificationPushTokenRepository
    let notificationPermissionService: NotificationPermissionServiceProtocol
    let localEventReminderService: LocalEventReminderServiceProtocol
    let newsRepository: NewsRepository
    let eventRepository: EventRepository
    let organizationRepository: OrganizationRepository
    let featuredBannerRepository: FeaturedBannerRepository
    let featuredBannerCache: FeaturedBannerCache
    let legalDocumentRepository: LegalDocumentRepository
    let ownerAnalyticsRepository: OwnerAnalyticsRepository
    let donationConfigRepository: DonationConfigRepository
    let recentViewsRepository: RecentViewsRepository
    let activityLogRepository: ActivityLogRepository
    let analyticsService: AnalyticsTracking
    let allowsAccountStatusMonitoring: Bool
    let allowsRemoteNotificationRegistration: Bool

    static var development: AppContainer {
        AppContainer(
            authState: AuthService.shared.authState,
            userRepository: FirestoreUserRepository(),
            feedbackRepository: FirestoreFeedbackRepository(),
            notificationPreferencesRepository: FirestoreNotificationPreferencesRepository(),
            notificationInboxRepository: FirestoreNotificationInboxRepository(),
            notificationPushTokenRepository: FirestoreNotificationPushTokenRepository(),
            notificationPermissionService: NotificationPermissionService(),
            localEventReminderService: LocalEventReminderService(),
            newsRepository: FirestoreNewsRepository(),
            eventRepository: FirestoreEventRepository(),
            organizationRepository: FirestoreOrganizationRepository(),
            featuredBannerRepository: FirestoreFeaturedBannerRepository(),
            featuredBannerCache: FeaturedBannerCache(),
            legalDocumentRepository: FirestoreLegalDocumentRepository(),
            ownerAnalyticsRepository: FirestoreOwnerAnalyticsRepository(),
            donationConfigRepository: FirestoreDonationConfigRepository(),
            recentViewsRepository: FirestoreRecentViewsRepository(),
            activityLogRepository: FirestoreActivityLogRepository(),
            analyticsService: FirebaseAnalyticsService(),
            allowsAccountStatusMonitoring: true,
            allowsRemoteNotificationRegistration: true
        )
    }

    static func uiTesting(authState: AuthState = AuthState(sessionState: .guest)) -> AppContainer {
        AppContainer(
            authState: authState,
            userRepository: MockUserRepository(),
            feedbackRepository: MockFeedbackRepository(),
            notificationPreferencesRepository: MockNotificationPreferencesRepository(),
            notificationInboxRepository: MockNotificationInboxRepository(),
            notificationPushTokenRepository: MockNotificationPushTokenRepository(),
            notificationPermissionService: MockNotificationPermissionService(),
            localEventReminderService: MockLocalEventReminderService(),
            newsRepository: MockNewsRepository(),
            eventRepository: MockEventRepository(),
            organizationRepository: MockOrganizationRepository(),
            featuredBannerRepository: MockFeaturedBannerRepository(),
            featuredBannerCache: FeaturedBannerCache(),
            legalDocumentRepository: MockLegalDocumentRepository(),
            ownerAnalyticsRepository: MockOwnerAnalyticsRepository(),
            donationConfigRepository: MockDonationConfigRepository(),
            recentViewsRepository: MockRecentViewsRepository(),
            activityLogRepository: MockActivityLogRepository(),
            analyticsService: NoopAnalyticsService(),
            allowsAccountStatusMonitoring: false,
            allowsRemoteNotificationRegistration: false
        )
    }
}
