import Foundation

struct AppContainer {
    var announcementRepository: any AnnouncementRepository = MockAnnouncementRepository()
    let userRepository: UserRepository
    let feedbackRepository: FeedbackRepository
    let contentSafetyRepository: ContentSafetyRepository
    let userBlockingRepository: UserBlockingRepository
    let organizationBlockingRepository: OrganizationBlockingRepository
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
    let bannerMeasurementService: BannerMeasurementService
    var updateNotificationRegistration: (String, Bool) -> Void = { id, enabled in
        RemoteNotificationRegistrationService.shared.configureUser(id, notificationsEnabled: enabled)
    }

    /// Actual SDK graph. Fixture UI tests use `uiTesting`; opt-in connected
    /// Debug Simulator journeys pin Firebase to the local demo before using this graph.
    static var live: AppContainer {
        AppContainer(
            announcementRepository: CloudAnnouncementRepository(),
            userRepository: FirestoreUserRepository(),
            feedbackRepository: FirestoreFeedbackRepository(),
            contentSafetyRepository: CloudContentSafetyRepository(),
            userBlockingRepository: CloudUserBlockingRepository(),
            organizationBlockingRepository: CloudOrganizationBlockingRepository(),
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
            featuredBannerCache: FeaturedBannerCache.persistent(),
            legalDocumentRepository: FirestoreLegalDocumentRepository(),
            ownerAnalyticsRepository: FirestoreOwnerAnalyticsRepository(),
            analyticsService: FirstPartyAnalyticsService(),
            bannerMeasurementService: BannerMeasurementService()
        )
    }

    static var uiTesting: AppContainer {
        AppContainer(
            userRepository: MockUserRepository(),
            feedbackRepository: MockFeedbackRepository(),
            contentSafetyRepository: MockContentSafetyRepository(),
            userBlockingRepository: MockUserBlockingRepository(),
            organizationBlockingRepository: MockOrganizationBlockingRepository(),
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
            analyticsService: NoopAnalyticsService(),
            bannerMeasurementService: MockContentBuilder.settingsBannerConsentFixture() ?? BannerMeasurementService(startsObservers: false),
            updateNotificationRegistration: { _, _ in }
        )
    }
}
