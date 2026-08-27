//
//  UkrainianCommunityTests.swift
//  UkrainianCommunityTests
//
//  Created by Philipp Timofeev on 28.04.26.
//

import Combine
import Foundation
import Testing
@testable import UkrainianCommunity

private actor RecordingFeedbackRepository: FeedbackRepository {
    private(set) var submittedItems: [FeedbackItem] = []

    func submitFeedback(_ feedback: FeedbackItem) async throws {
        submittedItems.append(feedback)
    }

    func fetchFeedback() async throws -> [FeedbackItem] {
        submittedItems
    }

    func updateFeedbackStatus(id: String, status: FeedbackStatus) async throws {}

    func snapshot() async -> [FeedbackItem] {
        submittedItems
    }
}

@MainActor
struct UkrainianCommunityTests {
    @Test func localSearchMatchesMultipleWordsAcrossFieldsAndIgnoresDiacritics() {
        #expect(LocalSearchMatcher.matches(
            query: "Muller Wien",
            values: ["Café Müller", "Wien Neubau"]
        ))
        #expect(LocalSearchMatcher.matches(
            query: "українські продукти",
            values: ["Українські товари", "Продукти з доставкою"]
        ))
        #expect(!LocalSearchMatcher.matches(
            query: "Muller Salzburg",
            values: ["Café Müller", "Wien Neubau"]
        ))
    }

    @Test func emptyOrPunctuationOnlySearchDoesNotHideContent() {
        #expect(LocalSearchMatcher.matches(query: "   —  ", values: ["Будь-який запис"]))
        #expect(!LocalSearchMatcher.hasQuery("   —  "))
    }

    @Test func organizationDirectoryProfileNormalizesUserInputAndCapsLists() {
        let profile = OrganizationDirectoryProfile(
            profileKind: .business,
            secondaryCategories: ["retail", "ukrainianProducts", "support"],
            serviceModes: [.delivery, .pickup, .delivery],
            serviceArea: "  Wien und Umgebung  ",
            regularHours: ["monday": "09:00-18:00", "": "ignored"],
            services: [
                " Lebensmittel ", "Lebensmittel", "Geschenkkörbe", "Beratung",
                "Lieferung", "Abholung", "Catering", "Bestellung", "Neunte Leistung"
            ],
            orderURL: "  https://example.com/order  "
        )

        #expect(profile.secondaryCategories == ["retail", "ukrainianProducts"])
        #expect(profile.serviceModes == [.delivery, .pickup])
        #expect(profile.serviceArea == "Wien und Umgebung")
        #expect(profile.regularHours == ["monday": "09:00-18:00"])
        #expect(profile.services.count == OrganizationDirectoryProfile.maximumServiceCount)
        #expect(profile.services.first == "Lebensmittel")
        #expect(profile.orderURL == "https://example.com/order")
    }

    @Test func organizationValidationRequiresARealCity() {
        let errors = OrganizationValidationService().validate(
            name: "Ukrainian Market",
            shortDescription: "Ukrainian products and delivery in Vienna.",
            region: .wien,
            city: "   ",
            email: "shop@example.com",
            website: "https://example.com",
            foundedYear: "2024"
        )

        #expect(errors.contains(AppStrings.Validation.organizationCityRequired))
    }

    @Test func analyticsRequiresExplicitConsentAndPersistsTheChoice() {
        let suiteName = "AnalyticsConsentServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let service = AnalyticsConsentService(userDefaults: defaults)

        #expect(service.isAnalyticsEnabled(for: "user-a") == false)

        service.setAnalyticsEnabled(true, for: "user-a")
        #expect(service.isAnalyticsEnabled(for: "user-a") == true)
        #expect(service.isAnalyticsEnabled(for: "user-b") == false)

        service.setAnalyticsEnabled(false, for: "user-a")
        #expect(service.isAnalyticsEnabled(for: "user-a") == false)
    }

    private func makeUser(
        id: String = UUID().uuidString,
        role: UserRole = .user,
        globalRole: GlobalRole? = nil,
        blockState: UserBlockState = .active,
        accountStatus: AccountStatus? = nil,
        moderatorSections: [AppSection] = [],
        communityMemberships: [CommunityMembership] = []
    ) -> AppUser {
        AppUser(
            id: id,
            fullName: "Test User",
            displayName: "Tester",
            city: "Innsbruck",
            email: "\(id)@example.com",
            bio: "Bio",
            role: role,
            globalRole: globalRole,
            moderatorSections: moderatorSections,
            blockState: blockState,
            accountStatus: accountStatus,
            communityMemberships: communityMemberships,
            createdAt: .now,
            updatedAt: .now
        )
    }

    private func makeOrganization(
        id: String = "org-1",
        ownerId: String? = nil,
        adminIds: [String] = [],
        moderatorIds: [String] = []
    ) -> Organization {
        Organization(
            id: id,
            name: "Test Organization",
            description: "Description",
            city: "Innsbruck",
            ownerId: ownerId,
            adminIds: adminIds,
            moderatorIds: moderatorIds,
            createdAt: .now,
            updatedAt: .now,
            moderationStatus: .approved,
            likeCount: 0,
            likeState: .notLiked
        )
    }

    @Test func legacyRolesDoNotGrantPlatformPermissions() {
        let userPermissions = PermissionService(role: .user)
        let moderatorPermissions = PermissionService(role: .moderator)
        let adminPermissions = PermissionService(role: .admin)
        let ownerPermissions = PermissionService(role: .owner)

        #expect(userPermissions.canCreateNews == false)
        #expect(userPermissions.canBlockUsers == false)
        #expect(moderatorPermissions.canCreateNews == false)
        #expect(moderatorPermissions.canDeleteNews == false)
        #expect(adminPermissions.canAssignModerator == false)
        #expect(adminPermissions.canBlockUsers == false)
        #expect(adminPermissions.canAssignAdmin == false)
        #expect(ownerPermissions.canManageUsers == true)
        #expect(ownerPermissions.canDeleteEvent == true)
        #expect(ownerPermissions.canAccessOwnerTools == true)
    }

    @Test func finalPlatformRoleMatrixMatchesContract() {
        let owner = makeUser(id: "owner", globalRole: .owner)
        let admin = makeUser(id: "admin", globalRole: .admin)
        let normalUser = makeUser(id: "normal-user", globalRole: .user)

        #expect(PermissionService.canAssignAppAdmin(user: owner))
        #expect(PermissionService.canManageUsers(user: owner))
        #expect(PermissionService.canManageOrganizationRequests(user: owner))
        #expect(PermissionService.canAccessModerationTools(user: owner))
        #expect(PermissionService.canManageFeedback(user: owner))
        #expect(PermissionService.canManageReports(user: owner))
        #expect(PermissionService.canManageFeaturedBanners(user: owner))
        #expect(PermissionService.canUseOrganizationOverride(user: owner))
        #expect(PermissionService.canAccessBlockedUsersSettings(user: owner))
        #expect(PermissionService.canSendTestNotification(user: owner))

        #expect(PermissionService.canManageOrganizationRequests(user: admin))
        #expect(PermissionService.canAccessModerationTools(user: admin))
        #expect(PermissionService.canAccessAdminTools(user: admin))
        #expect(PermissionService.canManageUsers(user: admin))
        #expect(PermissionService.canManageFeedback(user: admin))
        #expect(PermissionService.canManageReports(user: admin))
        #expect(PermissionService.canAssignGlobalRoles(user: admin))
        #expect(PermissionService.canTemporarilyBan(user: admin))
        #expect(PermissionService.canPermanentlyBan(user: admin))
        #expect(PermissionService.canAssignAppAdmin(user: admin) == false)
        #expect(PermissionService.canUseOrganizationOverride(user: admin) == false)
        #expect(PermissionService.canAccessBlockedUsersSettings(user: admin))
        #expect(PermissionService.canSendTestNotification(user: admin) == false)

        #expect(PermissionService.canManageUsers(user: normalUser) == false)
        #expect(PermissionService.canAccessModerationTools(user: normalUser) == false)
        #expect(PermissionService.canAccessBlockedUsersSettings(user: normalUser))
        #expect(PermissionService.canSendTestNotification(user: normalUser) == false)
    }

    @Test func restrictedAndLegacyPlatformRolesDoNotGrantElevatedAccess() {
        let suspendedOwner = makeUser(
            id: "suspended-owner",
            globalRole: .owner,
            blockState: .suspendedUntil,
            accountStatus: .suspendedUntil
        )
        let warnedAdmin = makeUser(
            id: "warned-admin",
            globalRole: .admin,
            blockState: .warned,
            accountStatus: .warned
        )
        let legacyTopAdmin = makeUser(id: "legacy-top-admin", globalRole: .topAdmin)

        #expect(PermissionService.isUsableAccount(user: suspendedOwner) == false)
        #expect(PermissionService.canManageUsers(user: suspendedOwner) == false)
        #expect(PermissionService.canUseOrganizationOverride(user: suspendedOwner) == false)

        #expect(PermissionService.isUsableAccount(user: warnedAdmin))
        #expect(PermissionService.canManageUsers(user: warnedAdmin))
        #expect(PermissionService.canManageOrganizationRequests(user: warnedAdmin))
        #expect(PermissionService.canAccessModerationTools(user: warnedAdmin))

        #expect(legacyTopAdmin.globalRole.authorizationRole == .user)
        #expect(PermissionService.canAccessModerationTools(user: legacyTopAdmin) == false)
        #expect(GlobalRole(rawValue: "moderator") == nil)
        #expect(GlobalRole(rawValue: "appModerator") == nil)
    }

    @Test func userManagementTargetHierarchyProtectsOwnerAndAppAdmins() {
        let owner = makeUser(id: "owner", globalRole: .owner)
        let adminA = makeUser(id: "admin-a", globalRole: .admin)
        let adminB = makeUser(id: "admin-b", globalRole: .admin)
        let normalUser = makeUser(id: "normal-user", globalRole: .user)

        #expect(PermissionService.canManageUserTarget(actor: owner, target: adminA))
        #expect(PermissionService.canManageUserTarget(actor: adminA, target: normalUser))
        #expect(PermissionService.canManageUserTarget(actor: adminA, target: adminB) == false)
        #expect(PermissionService.canManageUserTarget(actor: adminA, target: owner) == false)
        #expect(PermissionService.canManageUserTarget(actor: owner, target: owner) == false)
    }

    @Test func authStateSupportsRestoringGuestAndAuthenticatedSessions() async {
        let authState = AuthState()

        #expect(authState.isRestoring)
        #expect(authState.isGuest == false)
        #expect(authState.isAuthenticated == false)

        await MainActor.run {
            authState.setGuestSession()
        }

        #expect(authState.isGuest)
        #expect(authState.user == nil)

        await MainActor.run {
            authState.setAuthenticatedSession(user: MockContentBuilder.currentUser())
        }

        #expect(authState.isAuthenticated)
        #expect(authState.isGuest == false)
    }

    @Test func authStatePresentsAndDismissesAuthFlows() async {
        let authState = AuthState()

        await MainActor.run {
            authState.presentAuthFlow(.register)
        }

        #expect(authState.presentedAuthFlow == .register)

        await MainActor.run {
            authState.dismissAuthFlow()
        }

        #expect(authState.presentedAuthFlow == nil)
    }

    @Test func permissionServiceUsesOrganizationArraysForOrganizationScopedAccess() {
        let owner = makeUser(globalRole: .owner)
        let platformAdmin = makeUser(id: "platform-admin", globalRole: .admin)
        let ordinaryUser = makeUser(role: .user, globalRole: .user)
        let organizationOwner = makeUser(id: "org-owner", role: .user, globalRole: .user)
        let organizationAdmin = makeUser(id: "org-admin", role: .user, globalRole: .user)
        let organizationModerator = makeUser(id: "org-moderator", role: .user, globalRole: .user)
        let organization = makeOrganization(
            ownerId: organizationOwner.id,
            adminIds: [organizationAdmin.id],
            moderatorIds: [organizationModerator.id]
        )

        #expect(PermissionService.canDeleteNews(user: owner))
        #expect(PermissionService.canDeleteEvent(user: owner))
        #expect(PermissionService.canDeleteOrganization(user: owner))
        #expect(PermissionService.canEditNews(user: owner))
        #expect(PermissionService.canEditEvent(user: owner))

        let appEvent = makeEvent(
            id: "app-event",
            startDate: Date(timeIntervalSince1970: 1_800_000_000),
            endDate: Date(timeIntervalSince1970: 1_800_003_600)
        )
        #expect(PermissionService.canEditEvent(appEvent, user: owner))
        #expect(PermissionService.canDeleteEvent(appEvent, user: owner))
        #expect(PermissionService.canEditEvent(appEvent, user: platformAdmin) == false)
        #expect(PermissionService.canDeleteEvent(appEvent, user: platformAdmin) == false)

        #expect(PermissionService.canAccessContentManagement(user: ordinaryUser) == false)
        #expect(PermissionService.canAccessOrganizationManagement(user: ordinaryUser) == false)
        #expect(PermissionService.canCreateNews(user: ordinaryUser) == false)
        #expect(PermissionService.canCreateEvent(user: ordinaryUser) == false)

        #expect(PermissionService.canEditOrganizationInfo(organization, user: platformAdmin) == false)
        #expect(PermissionService.canManageOrganizationRoles(organization, user: platformAdmin) == false)
        #expect(PermissionService.canCreateOrganizationNews(organization, user: platformAdmin) == false)
        #expect(PermissionService.canCreateOrganizationEvent(organization, user: platformAdmin) == false)

        #expect(PermissionService.canAccessOrganizationManagement(user: organizationAdmin) == false)
        #expect(PermissionService.canCreateOrganizationNews(organization, user: ordinaryUser) == false)
        #expect(PermissionService.canCreateOrganizationEvent(organization, user: ordinaryUser) == false)

        #expect(PermissionService.canEditOrganizationInfo(organization, user: organizationOwner))
        #expect(PermissionService.canManageOrganizationRoles(organization, user: organizationOwner))
        #expect(PermissionService.canDeleteOrganizationContent(organization, user: organizationOwner))
        #expect(PermissionService.canCreateOrganizationNews(organization, user: organizationOwner))
        #expect(PermissionService.canCreateOrganizationEvent(organization, user: organizationOwner))

        #expect(PermissionService.canEditOrganizationInfo(organization, user: organizationAdmin))
        #expect(PermissionService.canManageOrganizationRoles(organization, user: organizationAdmin) == false)
        #expect(PermissionService.canDeleteOrganizationContent(organization, user: organizationAdmin) == false)
        #expect(PermissionService.canCreateOrganizationNews(organization, user: organizationAdmin))
        #expect(PermissionService.canCreateOrganizationEvent(organization, user: organizationAdmin))

        #expect(PermissionService.canEditOrganizationInfo(organization, user: organizationModerator) == false)
        #expect(PermissionService.canManageOrganizationRoles(organization, user: organizationModerator) == false)
        #expect(PermissionService.canDeleteOrganizationContent(organization, user: organizationModerator) == false)
        #expect(PermissionService.canCreateOrganizationNews(organization, user: organizationModerator))
        #expect(PermissionService.canCreateOrganizationEvent(organization, user: organizationModerator))

        #expect(PermissionService.canDeleteOrganizationContent(organization, user: owner))
        #expect(PermissionService.canDeleteOrganizationContent(organization, user: platformAdmin) == false)
    }

    @Test func subscriberIdentityVisibilityMatchesBackendOwnerContract() {
        let appOwner = makeUser(id: "app-owner", globalRole: .owner)
        let appAdmin = makeUser(id: "app-admin", globalRole: .admin)
        let organizationOwner = makeUser(id: "organization-owner")
        let organizationAdmin = makeUser(id: "organization-admin")
        let organizationModerator = makeUser(id: "organization-moderator")
        let unrelatedUser = makeUser(id: "unrelated-user")
        let suspendedAppOwner = makeUser(
            id: "suspended-app-owner",
            globalRole: .owner,
            blockState: .suspendedUntil,
            accountStatus: .suspendedUntil
        )
        let organization = makeOrganization(
            ownerId: organizationOwner.id,
            adminIds: [organizationAdmin.id],
            moderatorIds: [organizationModerator.id]
        )

        #expect(PermissionService.canViewOrganizationSubscriberIdentities(organization, user: appOwner))
        #expect(PermissionService.canViewOrganizationSubscriberIdentities(organization, user: organizationOwner))
        #expect(
            PermissionService.canViewOrganizationSubscriberIdentities(organization, user: appAdmin) == false
        )
        #expect(
            PermissionService.canViewOrganizationSubscriberIdentities(organization, user: organizationAdmin) == false
        )
        #expect(
            PermissionService.canViewOrganizationSubscriberIdentities(
                organization,
                user: organizationModerator
            ) == false
        )
        #expect(
            PermissionService.canViewOrganizationSubscriberIdentities(organization, user: unrelatedUser) == false
        )
        #expect(
            PermissionService.canViewOrganizationSubscriberIdentities(
                organization,
                user: suspendedAppOwner
            ) == false
        )
        #expect(PermissionService.canViewOrganizationSubscriberIdentities(organization, user: nil) == false)
    }

    @Test func mockRepositoriesProvideFoundationContent() async throws {
        let user = try await MockUserRepository().fetchCurrentUser()
        let news = try await MockNewsRepository().fetchNews()
        let events = try await MockEventRepository().fetchEvents()
        let organizations = try await MockOrganizationRepository().fetchOrganizations()

        #expect(user.fullName.isEmpty == false)
        #expect(news.isEmpty == false)
        #expect(events.isEmpty == false)
        #expect(organizations.isEmpty == false)
    }

    @Test func settingsPersistenceStoresLanguageAndAppearance() async throws {
        let previousSettings = UserSettings.stored
        defer { UserSettings.stored = previousSettings }

        let savedSettings = UserSettings(language: .ukrainian, appearance: .dark)
        UserSettings.stored = savedSettings

        #expect(UserSettings.stored.language == .ukrainian)
        #expect(UserSettings.stored.appearance == .dark)
        #expect(try await MockUserRepository().fetchSettings().language == .ukrainian)
        #expect(try await MockUserRepository().fetchSettings().appearance == .dark)
    }

    @Test func selectedLanguageAffectsDateFormatting() {
        let previousLanguage = AppLanguage.stored
        defer { AppLanguage.stored = previousLanguage }

        let sampleDate = Date(timeIntervalSince1970: 1_778_377_600) // May 10, 2026 UTC

        AppLanguage.stored = .german
        let germanDate = LocalizationStore.dateString(from: sampleDate)
        let repeatedGermanDate = LocalizationStore.dateString(from: sampleDate)
        let germanMonth = LocalizationStore.dateString(from: sampleDate, localizedTemplate: "MMMM")

        AppLanguage.stored = .ukrainian
        let ukrainianDate = LocalizationStore.dateString(from: sampleDate)
        let ukrainianMonth = LocalizationStore.dateString(from: sampleDate, localizedTemplate: "MMMM")

        #expect(germanDate == repeatedGermanDate)
        #expect(germanDate != ukrainianDate)
        #expect(germanMonth != ukrainianMonth)
    }

    @Test func selectedLanguageAffectsLocalizedStrings() {
        let previousLanguage = AppLanguage.stored
        defer { AppLanguage.stored = previousLanguage }

        AppLanguage.stored = .german
        let germanHome = LocalizationStore.localizedString("tab.home", defaultValue: "Home")
        let repeatedGermanHome = LocalizationStore.localizedString("tab.home", defaultValue: "Home")

        AppLanguage.stored = .ukrainian
        let ukrainianHome = LocalizationStore.localizedString("tab.home", defaultValue: "Home")

        #expect(germanHome == repeatedGermanHome)
        #expect(germanHome != ukrainianHome)
    }

    @Test func languagePickerTitlesRemainCorrectDuringLocaleSwitch() {
        let previousLanguage = AppLanguage.stored
        defer { AppLanguage.stored = previousLanguage }

        AppLanguage.stored = .ukrainian
        #expect(AppLanguage.german.title == "Deutsch")

        AppLanguage.stored = .german
        #expect(AppLanguage.ukrainian.title == "Українська")
    }

    @Test func profileStringsSwitchBetweenGermanAndUkrainian() {
        let previousLanguage = AppLanguage.stored
        defer { AppLanguage.stored = previousLanguage }

        AppLanguage.stored = .german
        let germanSettings = AppStrings.Profile.settingsSection
        let germanUsers = AppStrings.UserManagement.title
        let germanNotifications = AppStrings.NotificationInbox.title
        let germanSystemLogs = AppStrings.SystemLogs.ownerTitle

        AppLanguage.stored = .ukrainian
        #expect(AppStrings.Profile.settingsSection != germanSettings)
        #expect(AppStrings.UserManagement.title != germanUsers)
        #expect(AppStrings.NotificationInbox.title != germanNotifications)
        #expect(AppStrings.SystemLogs.ownerTitle != germanSystemLogs)
    }

    @Test func sortingControlsSwitchBetweenGermanAndUkrainian() {
        let previousLanguage = AppLanguage.stored
        defer { AppLanguage.stored = previousLanguage }

        AppLanguage.stored = .german
        #expect(AppStrings.Sorting.title == "Sortierung")
        #expect(AppStrings.Sorting.newest == "Neueste zuerst")
        #expect(AppStrings.SystemLogs.sortSeverityHigh == "Stufe: kritisch zuerst")

        AppLanguage.stored = .ukrainian
        #expect(AppStrings.Sorting.title == "Сортування")
        #expect(AppStrings.Sorting.newest == "Спочатку нові")
        #expect(AppStrings.SystemLogs.sortSeverityHigh == "Рівень: від критичного")
    }

    @Test func notificationSettingsSwitchBetweenGermanAndUkrainian() {
        let previousLanguage = AppLanguage.stored
        defer { AppLanguage.stored = previousLanguage }

        AppLanguage.stored = .german
        #expect(AppStrings.Profile.notificationsEnabled == "Push-Benachrichtigungen")
        #expect(AppStrings.Profile.eventRemindersEnabled == "Veranstaltungserinnerungen")
        #expect(AppStrings.Profile.reminderLeadTime == "Zeitpunkt der Erinnerung")
        #expect(AppStrings.profileNotificationReminderMinutes(30) == "30 Min.")

        AppLanguage.stored = .ukrainian
        #expect(AppStrings.Profile.notificationsEnabled == "Push-сповіщення")
        #expect(AppStrings.Profile.eventRemindersEnabled == "Нагадування про події")
        #expect(AppStrings.Profile.reminderLeadTime == "Час нагадування")
        #expect(AppStrings.profileNotificationReminderMinutes(30) == "30 хв")
    }

    @Test func accountStatusInboxContentUsesSelectedLanguageAndReason() {
        let previousLanguage = AppLanguage.stored
        defer { AppLanguage.stored = previousLanguage }
        let notification = AppNotification(
            id: "status-1",
            recipientUserId: "user-1",
            type: .accountStatusChanged,
            sourceType: .account,
            sourceId: "user-1",
            severity: .warning,
            actionType: .openProfile,
            actionTargetId: "user-1",
            requiresPopup: false,
            popupPresentedAt: nil,
            expiresAt: nil,
            archivedAt: nil,
            deletedAt: nil,
            title: "Account temporarily suspended",
            message: "Your account is temporarily suspended.",
            metadata: ["newAccountStatus": "suspendedUntil", "reason": "Custom reason"],
            payload: [:],
            isRead: false,
            readAt: nil,
            createdAt: .now
        )

        AppLanguage.stored = .german
        let germanContent = notification.localizedDisplayContent
        #expect(germanContent.title == AppStrings.AccountStatusAlert.suspendedTitle)
        #expect(germanContent.body.contains("Custom reason"))

        AppLanguage.stored = .ukrainian
        let ukrainianContent = notification.localizedDisplayContent
        #expect(ukrainianContent.title == AppStrings.AccountStatusAlert.suspendedTitle)
        #expect(ukrainianContent.title != germanContent.title)
        #expect(ukrainianContent.body.contains("Custom reason"))
    }

    @Test func workflowNotificationsUseSelectedLanguageAndSupportColdStartRouting() throws {
        let previousLanguage = AppLanguage.stored
        defer { AppLanguage.stored = previousLanguage }
        let notification = AppNotification(
            id: "submission-1", recipientUserId: "owner", type: .organizationRequestSubmitted,
            sourceType: .organization, sourceId: "org-1", actionType: .openOrganizationRequest,
            actionTargetId: "org-1", title: "Fallback", message: "Organization name",
            metadata: ["titleLocKey": "notifications.push.organization_submitted.title"],
            payload: [:], isRead: false, readAt: nil, createdAt: .now
        )
        AppLanguage.stored = .german
        #expect(notification.localizedDisplayContent.title == "Organisationsantrag zur Prüfung")
        AppLanguage.stored = .ukrainian
        #expect(notification.localizedDisplayContent.title == "Заявка організації на перевірку")
        #expect(notification.localizedDisplayContent.body == "Organization name")
        let route = try #require(RemoteNotificationRoute(userInfo: [
            "type": "organizationRequestSubmitted", "notificationId": "submission-1",
            "sourceType": "organization", "sourceId": "org-1",
            "actionType": "openOrganizationRequest", "actionTargetId": "org-1"
        ]))
        #expect(route.destination == .openOrganizationRequest(organizationId: "org-1"))
        #expect(route.notificationId == "submission-1")
    }

    @Test func notificationDetailsPreserveMessageWithoutRequiringDestination() {
        let notification = AppNotification(
            id: "detail", recipientUserId: "user-1", type: .eventUpdated,
            sourceType: .event, sourceId: "", title: "Updated",
            message: "The venue has moved.\nPlease use the north entrance.",
            actorDisplayName: "  Organizer  ", payload: [:], isRead: false, readAt: nil, createdAt: .now
        )
        #expect(notification.localizedDetailContent.body == notification.message)
        #expect(notification.detailSender == "Organizer")
        #expect(!notification.canOpenDestination)
        #expect(notification.localizedDetailContent.body != AppStrings.NotificationInbox.genericBody)
    }

    @Test func feedbackDetailsIncludeSubjectAndMessageWithoutInternalMetadata() {
        let notification = AppNotification(
            id: "feedback-detail", recipientUserId: "user-1", type: .feedbackReply,
            sourceType: .feedback, sourceId: "feedback-1", actionType: .openFeedback,
            message: "notifications.push.feedback_reply.body",
            metadata: ["privateInternalValue": "must-not-display"],
            payload: ["subject": "Question about an event", "messagePreview": "Thank you. We updated the address."],
            isRead: false, readAt: nil, createdAt: .now
        )
        let body = notification.localizedDetailContent.body
        #expect(body.contains("Question about an event"))
        #expect(body.contains("Thank you. We updated the address."))
        #expect(!body.contains("notifications.push"))
        #expect(!body.contains("must-not-display"))
        #expect(notification.canOpenDestination)
    }

    @Test func notificationDestinationsRejectInvalidOrExpiredActions() {
        func notification(action: AppNotificationActionType, target: String?, expires: Date? = nil) -> AppNotification {
            AppNotification(id: "route", recipientUserId: "user-1", type: .systemAnnouncement,
                sourceType: .system, sourceId: "  ", actionType: action, actionTargetId: target,
                expiresAt: expires, payload: [:], isRead: false, readAt: nil, createdAt: .now)
        }
        #expect(!notification(action: .none, target: "event-1").canOpenDestination)
        #expect(!notification(action: .openEvent, target: " \n ").canOpenDestination)
        #expect(notification(action: .openEvent, target: " event-1 ").destinationTargetID == "event-1")
        #expect(notification(action: .openEvent, target: "event-1").canOpenDestination)
        #expect(!notification(action: .openEvent, target: "event-1", expires: .distantPast).canOpenDestination)
        #expect(notification(action: .openURL, target: "https://example.com/details").canOpenDestination)
        for unsafe in ["javascript:alert(1)", "file:///etc/passwd", "relative/path", "https://"] {
            #expect(!notification(action: .openURL, target: unsafe).canOpenDestination)
        }
    }

    @Test func notificationDetailActionsAreLocalized() {
        let previousLanguage = AppLanguage.stored
        defer { AppLanguage.stored = previousLanguage }
        AppLanguage.stored = .german
        #expect(AppStrings.NotificationInbox.detailTitle == "Details")
        #expect(AppStrings.NotificationInbox.closeDetails == "Schließen")
        #expect(AppStrings.NotificationInbox.deleteConfirmationTitle == "Diese Benachrichtigung löschen?")
        AppLanguage.stored = .ukrainian
        #expect(AppStrings.NotificationInbox.detailTitle == "Деталі")
        #expect(AppStrings.NotificationInbox.closeDetails == "Закрити")
        #expect(AppStrings.NotificationInbox.deleteConfirmationTitle == "Видалити це сповіщення?")
    }

    @Test func selectedLanguageAffectsCurrencyFormatting() {
        let previousLanguage = AppLanguage.stored
        defer { AppLanguage.stored = previousLanguage }

        let amount = Decimal(string: "1234.5")

        AppLanguage.stored = .german
        let germanCurrency = CurrencyFormatter.priceString(for: amount)

        AppLanguage.stored = .ukrainian
        let ukrainianCurrency = CurrencyFormatter.priceString(for: amount)

        #expect(germanCurrency != ukrainianCurrency)
    }

    @Test func unsupportedLegacyFeaturedBannerIsPreparedForMigration() throws {
        let now = Date()
        let legacyBanner = FeaturedBanner(
            id: "legacy-guide-banner",
            title: "Legacy guide banner",
            imageURL: "https://example.com/banner.jpg",
            actionType: .unsupportedLegacy,
            actionTargetID: "firstSteps",
            visibleSections: [.home, .unsupportedLegacy],
            createdAt: now,
            updatedAt: now,
            createdBy: "owner"
        )

        #expect(FeaturedBannerActionType.normalized(from: "guide") == .unsupportedLegacy)
        #expect(FeaturedBannerVisibleSection(rawValue: "guide") == .unsupportedLegacy)
        #expect(legacyBanner.hasUnsupportedLegacyConfiguration)
        try FeaturedBannerValidationService().validate(legacyBanner, allowsUnsupportedLegacy: true)
        #expect(throws: AppError.self) {
            try FeaturedBannerValidationService().validate(legacyBanner)
        }
        #expect(FeaturedBannerActionResolver().resolve(legacyBanner) == .noAction)

        let repository = MockFeaturedBannerRepository(banners: [legacyBanner])
        let viewModel = FeaturedBannerEditorViewModel(
            repository: repository,
            mode: .edit(legacyBanner)
        )

        #expect(viewModel.isMigratingLegacyBanner)
        #expect(viewModel.actionType == .none)
        #expect(viewModel.actionTargetID.isEmpty)
        #expect(viewModel.visibleSections == [.home])
        #expect(viewModel.canSave)
        #expect(viewModel.validationMessage == nil)
        #expect([legacyBanner].activeFeaturedBanners(for: .home, federalState: nil).isEmpty)

        let mixedSectionsBanner = FeaturedBanner(
            id: "legacy-mixed-sections",
            title: "Supported home banner",
            imageURL: "https://example.com/banner.jpg",
            actionType: .none,
            visibleSections: [.home, .unsupportedLegacy],
            createdAt: now,
            updatedAt: now,
            createdBy: "owner"
        )
        #expect(
            [mixedSectionsBanner].activeFeaturedBanners(for: .home, federalState: nil)
                == [mixedSectionsBanner]
        )
    }

    @Test func unsupportedLegacyFeaturedBannerCanBeMigratedAndDeleted() async throws {
        let now = Date()
        let legacyBanner = FeaturedBanner(
            id: "legacy-guide-banner",
            title: "Legacy guide banner",
            imageURL: "https://example.com/banner.jpg",
            actionType: .unsupportedLegacy,
            actionTargetID: "firstSteps",
            visibleSections: [.home, .unsupportedLegacy],
            createdAt: now,
            updatedAt: now,
            createdBy: "owner"
        )
        let repository = MockFeaturedBannerRepository(banners: [legacyBanner])

        try await repository.setBannerActive(id: legacyBanner.id, isActive: false, updatedBy: "owner")
        let storedBanners = try await repository.fetchAllBannersForOwner()
        let storedBanner = try #require(storedBanners.first)
        #expect(storedBanner.isActive == false)

        await #expect(throws: AppError.self) {
            try await repository.setBannerActive(id: legacyBanner.id, isActive: true, updatedBy: "owner")
        }
        let supportedReplacement = FeaturedBanner(
            id: legacyBanner.id,
            title: "Replacement",
            imageURL: "https://example.com/replacement.jpg",
            actionType: .none,
            visibleSections: [.home],
            createdAt: now,
            updatedAt: now,
            createdBy: "owner"
        )
        try await repository.updateBanner(supportedReplacement)
        try await repository.setBannerActive(id: legacyBanner.id, isActive: true, updatedBy: "owner")
        try await repository.deleteBanner(id: legacyBanner.id)
        #expect(try await repository.fetchAllBannersForOwner().isEmpty)
    }

    @Test func featuredBannerLifecycleStateCoversPublishingWindow() {
        let now = Date(timeIntervalSince1970: 1_777_000_000)
        let base = FeaturedBanner(
            id: "banner",
            title: "Banner",
            imageURL: "https://example.com/banner.jpg",
            visibleSections: [.home],
            createdAt: now,
            updatedAt: now,
            createdBy: "owner"
        )

        #expect(base.lifecycleState(at: now) == .live)

        let scheduled = FeaturedBanner(
            id: base.id,
            title: base.title,
            imageURL: base.imageURL,
            visibleSections: base.visibleSections,
            startsAt: now.addingTimeInterval(60),
            createdAt: now,
            updatedAt: now,
            createdBy: base.createdBy
        )
        #expect(scheduled.lifecycleState(at: now) == .scheduled)

        let expired = FeaturedBanner(
            id: base.id,
            title: base.title,
            imageURL: base.imageURL,
            visibleSections: base.visibleSections,
            endsAt: now.addingTimeInterval(-60),
            createdAt: now,
            updatedAt: now,
            createdBy: base.createdBy
        )
        #expect(expired.lifecycleState(at: now) == .expired)
    }

    @Test func featuredBannerRegionFilteringMatchesPublicFeedSemantics() {
        let now = Date()
        let nationalBanner = FeaturedBanner(
            id: "national",
            title: "Austria",
            imageURL: "https://example.com/national.jpg",
            visibleSections: [.home],
            createdAt: now,
            updatedAt: now,
            createdBy: "owner"
        )
        let viennaBanner = FeaturedBanner(
            id: "vienna",
            title: "Vienna",
            imageURL: "https://example.com/vienna.jpg",
            regionScope: .federalState,
            federalState: .wien,
            visibleSections: [.home],
            createdAt: now,
            updatedAt: now,
            createdBy: "owner"
        )

        let allAustria = [nationalBanner, viennaBanner]
            .activeFeaturedBanners(for: .home, federalState: nil, now: now)
        let allAustriaIDs = Set(allAustria.map(\.id))
        #expect(allAustriaIDs == ["national", "vienna"])

        let vienna = [nationalBanner, viennaBanner]
            .activeFeaturedBanners(for: .home, federalState: .wien, now: now)
        let viennaIDs = Set(vienna.map(\.id))
        #expect(viennaIDs == ["national", "vienna"])

        let tirol = [nationalBanner, viennaBanner]
            .activeFeaturedBanners(for: .home, federalState: .tirol, now: now)
        let tirolIDs = tirol.map(\.id)
        #expect(tirolIDs == ["national"])
    }

    @Test func retiredGuideNotificationValuesDecodeToSafeFallbacks() throws {
        let decoder = JSONDecoder()

        let notificationType = try decoder.decode(
            AppNotificationType.self,
            from: Data(#""guideMaterialUpdated""#.utf8)
        )
        let sourceType = try decoder.decode(
            AppNotificationSourceType.self,
            from: Data(#""guideMaterial""#.utf8)
        )
        let actionType = try decoder.decode(
            AppNotificationActionType.self,
            from: Data(#""openGuideMaterial""#.utf8)
        )

        #expect(notificationType == .unknown)
        #expect(sourceType == .system)
        #expect(actionType == .none)

        let retiredReportUserInfo: [AnyHashable: Any] = [
            "type": "reportReviewed",
            "sourceType": "guideReport",
            "actionType": "openGuideReport"
        ]
        let retiredMaterialUserInfo: [AnyHashable: Any] = [
            "type": "guideMaterialUpdated",
            "sourceType": "guideMaterial",
            "actionType": "openGuideMaterial"
        ]

        #expect(RemoteNotificationRoute(userInfo: retiredReportUserInfo) == nil)
        #expect(RemoteNotificationRoute(userInfo: retiredMaterialUserInfo) == nil)
    }

    @Test func legacyGuideAnalyticsIsExcludedFromActiveTotalsAndContent() {
        let metrics: [AnalyticsMetricType: Int] = [
            .totalViews: 999,
            .newsViews: 4,
            .eventViews: 3,
            .organizationViews: 2
        ]
        let contentKeys: [String: Any] = [
            "news_current": true,
            "organization_current": true,
            "guideArticle_retired": true,
            "unknown_retired": true
        ]

        #expect(AnalyticsFirestoreSchema.activeViewCount(in: metrics) == 9)
        #expect(AnalyticsFirestoreSchema.activeContentCount(in: contentKeys) == 2)
        #expect(AnalyticsFirestoreSchema.activeContentCount(in: [:]) == 0)
        #expect(AnalyticsFirestoreSchema.hasActiveRegionAnalytics(viewCount: 0, contentCount: 0) == false)
        #expect(AnalyticsFirestoreSchema.hasActiveRegionAnalytics(viewCount: 1, contentCount: 0))
        #expect(AnalyticsFirestoreSchema.hasActiveRegionAnalytics(viewCount: 0, contentCount: 1))
        #expect(AnalyticsContentType(rawValue: "guideArticle") == nil)
    }

    @Test func filterOrderPinsLeadingControlsAndStablyPromotesActiveFilters() {
        let pinned = ["first", "region"]
        let filters = ["category", "audience", "age", "registered", "saved"]
        #expect(AppFilterOrder.ordered(pinned: pinned, filters: filters, active: []) == pinned + filters)
        #expect(AppFilterOrder.ordered(pinned: pinned, filters: filters, active: ["saved"]) ==
            ["first", "region", "saved", "category", "audience", "age", "registered"])
        #expect(AppFilterOrder.ordered(pinned: pinned, filters: filters, active: ["saved", "audience", "region"]) ==
            ["first", "region", "audience", "saved", "category", "age", "registered"])
        #expect(AppFilterOrder.ordered(pinned: pinned, filters: filters, active: Set(filters)) == pinned + filters)
    }

    @Test func authValidationRejectsInvalidRegistrationAndResetInputs() {
        let service = AuthValidationService()

        let registrationErrors = service.validateRegistration(
            email: "invalid",
            password: "short",
            repeatedPassword: "different",
            displayName: " ",
            selectedFederalState: nil,
            acceptedTerms: false,
            acceptedPrivacy: false,
            confirmedMinimumAge: false
        )

        #expect(registrationErrors.contains(AppStrings.Validation.authEmailInvalid))
        #expect(registrationErrors.contains(AppStrings.Validation.authPasswordTooShort))
        #expect(registrationErrors.contains(AppStrings.Validation.authPasswordMismatch))
        #expect(registrationErrors.contains(AppStrings.Validation.authDisplayNameRequired))
        #expect(registrationErrors.contains(AppStrings.Validation.authFederalStateRequired))
        #expect(registrationErrors.contains(AppStrings.Validation.authTermsRequired))
        #expect(registrationErrors.contains(AppStrings.Validation.authPrivacyRequired))
        #expect(registrationErrors.contains(AppStrings.Validation.authMinimumAgeRequired))

        let resetErrors = service.validatePasswordReset(email: "nope")
        #expect(resetErrors == [AppStrings.Validation.authEmailInvalid])
    }

    @Test func registrationRequiresAnExplicitFederalStateSelection() {
        let service = AuthValidationService()
        func errors(for state: AustrianFederalState?) -> [String] {
            service.validateRegistration(
                email: "member@example.org", password: "secure-password",
                repeatedPassword: "secure-password", displayName: "Member",
                selectedFederalState: state, acceptedTerms: true,
                acceptedPrivacy: true, confirmedMinimumAge: true
            )
        }

        #expect(errors(for: nil) == [AppStrings.Validation.authFederalStateRequired])
        for state in AustrianFederalState.allCases {
            #expect(errors(for: state).isEmpty)
        }
        #expect(errors(for: nil) == [AppStrings.Validation.authFederalStateRequired])
    }

    @Test func authLegalVersionsAreStableAndNonEmpty() {
        #expect(AuthService.currentTermsVersion.isEmpty == false)
        #expect(AuthService.currentPrivacyVersion.isEmpty == false)
        #expect(AuthService.currentTermsVersion == "2026.10")
        #expect(AuthService.currentPrivacyVersion == "2026.11")
        #expect(AuthService.currentMinimumAgeVersion == "14+")
    }

    @Test func legalDraftVersionGenerationUsesReadableVersionAndInternalNumber() {
        let nextFromSecondVersion = LegalDocumentDraft.from(
            activeDocument: makeLegalDocument(version: "2026.2", versionNumber: 202602)
        )
        #expect(nextFromSecondVersion.version == "2026.3")
        #expect(nextFromSecondVersion.versionNumber == 202603)

        let nextFromNinthVersion = LegalDocumentDraft.from(
            activeDocument: makeLegalDocument(version: "2026.9", versionNumber: 202609)
        )
        #expect(nextFromNinthVersion.version == "2026.10")
        #expect(nextFromNinthVersion.versionNumber == 202610)

        let nextFromMalformedVersion = LegalDocumentDraft.from(
            activeDocument: makeLegalDocument(version: "2026.202605", versionNumber: 202605)
        )
        #expect(nextFromMalformedVersion.version == "2026.6")
        #expect(nextFromMalformedVersion.versionNumber == 202606)
    }

    @Test func registrationPayloadMatchesSafeUserDefaults() {
        let acceptedAt = Date(timeIntervalSince1970: 1_767_225_600)
        let draft = RegistrationProfileDraft(
            email: "new@example.com",
            displayName: "New User",
            telegramUsername: "newuser",
            selectedFederalState: .tirol,
            acceptedTermsAt: acceptedAt,
            acceptedPrivacyAt: acceptedAt,
            termsVersion: AuthService.currentTermsVersion,
            privacyVersion: AuthService.currentPrivacyVersion,
            minimumAgeConfirmedAt: acceptedAt,
            minimumAgeVersion: AuthService.currentMinimumAgeVersion
        )

        let payload = UserProfileService.makeRegisteredUserDocumentData(uid: "user-123", draft: draft)

        #expect(payload.id == "user-123")
        #expect(payload.role == nil)
        #expect(payload.globalRole == GlobalRole.user.rawValue)
        #expect(payload.accountStatus == AccountStatus.active.rawValue)
        #expect(payload.blockState == UserBlockState.active.rawValue)
        #expect(payload.warningCount == 0)
        #expect(payload.communityMemberships.isEmpty)
        #expect(payload.displayName == "New User")
        #expect(payload.fullName == "New User")
        #expect(payload.email == "new@example.com")
        #expect(payload.selectedFederalState == AustrianFederalState.tirol.rawValue)
        #expect(payload.acceptedTermsAt == acceptedAt)
        #expect(payload.acceptedPrivacyAt == acceptedAt)
        #expect(payload.termsVersion == AuthService.currentTermsVersion)
        #expect(payload.privacyVersion == AuthService.currentPrivacyVersion)
        #expect(payload.minimumAgeConfirmedAt == acceptedAt)
        #expect(payload.minimumAgeVersion == AuthService.currentMinimumAgeVersion)
        #expect(payload.isBlocked == false)
    }

    @Test func contentModelsCarryModerationStatus() async throws {
        let news = try await MockNewsRepository().fetchNews()
        let approvedEvents = try await MockEventRepository().fetchEvents()
        let allMockEvents = MockContentBuilder.events()
        let organizations = try await MockOrganizationRepository().fetchOrganizations()

        #expect(news.contains(where: { $0.moderationStatus == .approved }))
        #expect(approvedEvents.allSatisfy { $0.moderationStatus == .approved })
        #expect(allMockEvents.contains(where: { $0.moderationStatus == .draft }))
        #expect(organizations.contains(where: { $0.moderationStatus == .approved }))
    }

    private func makeLegalDocument(version: String, versionNumber: Int) -> LegalDocument {
        LegalDocument(
            id: LegalDocumentType.terms.rawValue,
            type: .terms,
            version: version,
            versionNumber: versionNumber,
            locales: [
                AppLanguage.german.rawValue: LegalDocumentLocaleContent(
                    title: "Terms",
                    contentMarkdown: "Terms",
                    contentText: nil,
                    contentHash: nil
                )
            ],
            defaultLocale: AppLanguage.german.rawValue,
            canonicalLocale: AppLanguage.german.rawValue,
            contentHash: nil,
            changeSummary: nil,
            requiresAcceptance: true,
            status: .published,
            updatedAt: nil,
            updatedBy: nil,
            publishedAt: nil,
            publishedBy: nil
        )
    }

    @Test func homeViewModelSortsNewestFirstAndContainsSupportedItemTypes() async throws {
        let newsRepository = MockNewsRepository()
        let eventRepository = MockEventRepository()
        let organizationRepository = MockOrganizationRepository()
        let viewModel = HomeViewModel(
            newsRepository: newsRepository,
            eventRepository: eventRepository,
            organizationRepository: organizationRepository
        )

        let posts = try await newsRepository.fetchNews()
        let events = try await eventRepository.fetchEvents()
        let organizations = try await organizationRepository.fetchOrganizations()
        viewModel.updateFeed(
            posts: posts,
            events: events,
            organizations: organizations,
            isLoading: false,
            error: nil
        )

        #expect(viewModel.feedItems.isEmpty == false)
        #expect(viewModel.feedItems.map(\.publishedAt) == viewModel.feedItems.map(\.publishedAt).sorted(by: >))

        let itemTypes = Set(viewModel.feedItems.map(\.itemType))
        #expect(itemTypes.contains(.news))
        #expect(itemTypes.contains(.event))
        #expect(itemTypes.contains(.organization))

        let destinations = viewModel.feedItems.map(\.destination)
        #expect(destinations.contains { if case .news = $0 { return true } else { return false } })
        #expect(destinations.contains { if case .event = $0 { return true } else { return false } })
        #expect(destinations.contains { if case .organization = $0 { return true } else { return false } })
    }

    @Test func homeViewModelDoesNotRepublishAnIdenticalFeedSnapshot() async throws {
        let newsRepository = MockNewsRepository()
        let eventRepository = MockEventRepository()
        let organizationRepository = MockOrganizationRepository()
        let viewModel = HomeViewModel(
            newsRepository: newsRepository,
            eventRepository: eventRepository,
            organizationRepository: organizationRepository
        )
        let posts = try await newsRepository.fetchNews()
        let events = try await eventRepository.fetchEvents()
        let organizations = try await organizationRepository.fetchOrganizations()
        var publicationCount = 0
        let observation = viewModel.objectWillChange.sink {
            publicationCount += 1
        }

        viewModel.updateFeed(
            posts: posts,
            events: events,
            organizations: organizations,
            isLoading: false,
            error: nil
        )
        let firstPublicationCount = publicationCount
        viewModel.updateFeed(
            posts: posts,
            events: events,
            organizations: organizations,
            isLoading: false,
            error: nil
        )

        #expect(firstPublicationCount > 0)
        #expect(publicationCount == firstPublicationCount)
        withExtendedLifetime(observation) {}
    }

    @Test func homeViewModelRemovesDuplicateDocumentsBeforeRendering() async throws {
        let newsRepository = MockNewsRepository()
        let eventRepository = MockEventRepository()
        let organizationRepository = MockOrganizationRepository()
        let viewModel = HomeViewModel(
            newsRepository: newsRepository,
            eventRepository: eventRepository,
            organizationRepository: organizationRepository
        )
        let post = try #require(await newsRepository.fetchNews().first)
        let event = try #require(await eventRepository.fetchEvents().first)
        let organization = try #require(await organizationRepository.fetchOrganizations().first)

        viewModel.updateFeed(
            posts: [post, post],
            events: [event, event],
            organizations: [organization, organization],
            isLoading: false,
            error: nil
        )

        #expect(viewModel.feedItems.count == 3)
        #expect(Set(viewModel.feedItems.map(\.id)).count == viewModel.feedItems.count)
    }

    @Test func eventDiscoveryDateRulesSupportUpcomingPastTodayAndThisWeek() {
        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 5, day: 11, hour: 12, minute: 0)) ?? Date()
        let todayEvent = makeEvent(
            id: "today",
            startDate: calendar.date(bySettingHour: 14, minute: 0, second: 0, of: now) ?? now,
            endDate: calendar.date(bySettingHour: 16, minute: 0, second: 0, of: now) ?? now
        )
        let thisWeekEvent = makeEvent(
            id: "week",
            startDate: calendar.date(byAdding: .day, value: 2, to: todayEvent.startDate) ?? now,
            endDate: calendar.date(byAdding: .day, value: 2, to: todayEvent.endDate) ?? now
        )
        let futureEvent = makeEvent(
            id: "future",
            startDate: calendar.date(byAdding: .day, value: 10, to: todayEvent.startDate) ?? now,
            endDate: calendar.date(byAdding: .day, value: 10, to: todayEvent.endDate) ?? now
        )
        let pastEvent = makeEvent(
            id: "past",
            startDate: calendar.date(byAdding: .day, value: -3, to: todayEvent.startDate) ?? now,
            endDate: calendar.date(byAdding: .day, value: -3, to: todayEvent.endDate) ?? now
        )

        let events = [todayEvent, thisWeekEvent, futureEvent, pastEvent]
        let upcomingEvents = events
            .filter { $0.endDate >= now }
            .sorted { $0.startDate < $1.startDate }
        let pastEvents = events
            .filter { $0.endDate < now }
            .sorted { $0.startDate > $1.startDate }
        let todayEvents = upcomingEvents.filter { calendar.isDate($0.startDate, inSameDayAs: now) }
        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now)
        let thisWeekEvents = upcomingEvents.filter { event in
            guard let weekInterval else { return true }
            return weekInterval.contains(event.startDate)
        }

        #expect(upcomingEvents.map(\.id) == ["today", "week", "future"])
        #expect(pastEvents.map(\.id) == ["past"])
        #expect(todayEvents.map(\.id) == ["today"])
        #expect(thisWeekEvents.map(\.id).contains("today"))
        #expect(thisWeekEvents.map(\.id).contains("week"))
        #expect(thisWeekEvents.map(\.id).contains("future") == false)
    }

    @Test func feedbackSubmissionUsesOpenStatusForAllSupportedTypes() async {
        let feedbackRepository = RecordingFeedbackRepository()
        let viewModel = ProfileViewModel(
            repository: MockUserRepository(),
            feedbackRepository: feedbackRepository,
            notificationPreferencesRepository: MockNotificationPreferencesRepository(),
            notificationPermissionService: MockNotificationPermissionService(),
            localEventReminderService: MockLocalEventReminderService()
        )
        let user = makeUser()

        for type in FeedbackType.allCases {
            let didSubmit = await viewModel.submitFeedback(type: type, message: "Message for \(type.rawValue)", user: user)
            #expect(didSubmit)
        }

        let submittedItems = await feedbackRepository.snapshot()
        #expect(submittedItems.count == FeedbackType.allCases.count)
        #expect(Set(submittedItems.map(\.type)) == Set(FeedbackType.allCases))
        #expect(submittedItems.allSatisfy { $0.status == .open })
    }

    @Test func dtoMappingRoundTripPreservesIdentifiers() async throws {
        let user = try await MockUserRepository().fetchCurrentUser()
        let news = try await MockNewsRepository().fetchNews()
        let events = try await MockEventRepository().fetchEvents()
        let organizations = try await MockOrganizationRepository().fetchOrganizations()
        let event = try #require(events.first)
        let organization = try #require(organizations.first)

        let restoredUser = AppUser(dto: user.dto)
        let restoredNews = NewsPost(dto: news[0].dto)
        let restoredEvent = Event(dto: event.dto)
        let restoredOrganization = Organization(dto: organization.dto)

        #expect(restoredUser.id == user.id)
        #expect(restoredNews.id == news[0].id)
        #expect(restoredEvent.id == event.id)
        #expect(restoredOrganization.id == organization.id)
    }

    @Test func userDtoRoundTripPreservesConsentFields() {
        let acceptedAt = Date(timeIntervalSince1970: 1_778_377_600)
        let user = AppUser(
            id: "user-1",
            fullName: "Test User",
            displayName: "Tester",
            city: "Innsbruck",
            email: "tester@example.com",
            avatarURL: URL(string: "https://example.com/avatar.png"),
            bio: "Bio",
            telegramUsername: "tester",
            role: .user,
            globalRole: .user,
            moderatorSections: [],
            blockState: .active,
            communityMemberships: [],
            selectedFederalState: .tirol,
            acceptedTermsAt: acceptedAt,
            acceptedPrivacyAt: acceptedAt,
            termsVersion: "2026.1",
            privacyVersion: "2026.1",
            createdAt: acceptedAt,
            updatedAt: acceptedAt
        )

        let restored = AppUser(dto: user.dto)

        #expect(restored.acceptedTermsAt == acceptedAt)
        #expect(restored.acceptedPrivacyAt == acceptedAt)
        #expect(restored.termsVersion == "2026.1")
        #expect(restored.privacyVersion == "2026.1")
        #expect(restored.selectedFederalState == .tirol)
        #expect(restored.avatarURL?.absoluteString == "https://example.com/avatar.png")
    }

    @Test func mockUserRepositoryUpdatesExpandedProfileFields() async throws {
        let updated = try await MockUserRepository().updateProfile(
            EditableUserProfileDraft(
                fullName: "Olena Marchenko",
                displayName: "Olena",
                telegramUsername: "olena.tirol",
                city: "Innsbruck",
                bio: "Community volunteer",
                selectedFederalState: .tirol,
                avatarURL: URL(string: "https://example.com/new-avatar.jpg")
            )
        )

        #expect(updated.fullName == "Olena Marchenko")
        #expect(updated.displayName == "Olena")
        #expect(updated.telegramUsername == "olena.tirol")
        #expect(updated.city == "Innsbruck")
        #expect(updated.bio == "Community volunteer")
        #expect(updated.selectedFederalState == .tirol)
        #expect(updated.avatarURL?.absoluteString == "https://example.com/new-avatar.jpg")
    }

    @Test func mockEventRepositoryFetchRegisteredEventsReturnsOnlyRegisteredItems() async throws {
        let repository = MockEventRepository()
        let targetEvent = makeEvent(
            id: "registered-events-test-\(UUID().uuidString)",
            startDate: .now.addingTimeInterval(86_400),
            endDate: .now.addingTimeInterval(90_000)
        )
        try await repository.createEvent(targetEvent)

        let initialRegisteredEvents = try await repository.fetchRegisteredEvents()
        #expect(initialRegisteredEvents.allSatisfy { $0.registrationState == .registered })

        _ = try await repository.registerForEvent(id: targetEvent.id, actionCapture: nil)

        let registeredEvents = try await repository.fetchRegisteredEvents()

        #expect(registeredEvents.contains(where: { $0.id == targetEvent.id }))
        #expect(registeredEvents.allSatisfy { $0.registrationState == .registered })
        #expect(registeredEvents.map(\.startDate) == registeredEvents.map(\.startDate).sorted(by: <))
    }

    @Test func myRegistrationsViewModelCancelRegistrationRemovesEventAndUpdatesCount() async throws {
        let repository = MockEventRepository()
        let targetEvent = try #require((try await repository.fetchEvents()).first(where: { $0.registrationState == .registered }))
        let viewModel = MyRegistrationsViewModel(
            repository: repository,
            localEventReminderService: MockLocalEventReminderService()
        )

        await viewModel.refresh()
        #expect(viewModel.events.contains(where: { $0.id == targetEvent.id }))

        await viewModel.cancelRegistration(for: targetEvent.id)

        #expect(viewModel.events.contains(where: { $0.id == targetEvent.id }) == false)
        #expect(viewModel.pendingCancellationIDs.contains(targetEvent.id) == false)
        #expect(viewModel.registrationsCount == viewModel.events.count)
        let registeredEvents = try await repository.fetchRegisteredEvents()
        #expect(registeredEvents.contains(where: { $0.id == targetEvent.id }) == false)
    }

    @Test func feedbackModelSupportsExpectedTypesAndOpenStatus() {
        #expect(Set(FeedbackType.allCases) == Set([.question, .suggestion, .bug, .report]))
        #expect(Set(FeedbackStatus.allCases) == Set([.open, .answered, .reviewed, .archived, .closed]))

        let item = FeedbackItem(
            id: "feedback-1",
            type: .bug,
            subject: nil,
            message: "Example",
            status: .open,
            createdAt: .now,
            updatedAt: .now,
            userId: "user-1",
            userDisplayName: "Tester",
            ownerReply: nil,
            repliedAt: nil,
            repliedByUserId: nil,
            lastMessageText: "Example",
            lastMessageAt: .now,
            lastMessageByUserId: "user-1",
            lastMessageByRole: .user,
            unreadForOwner: true,
            unreadForUser: false
        )

        #expect(item.status == .open)
        #expect(item.type == .bug)
    }

    @Test func accountDeletionUsesDedicatedServerCallable() {
        #expect(CloudFunctionName.deleteOwnAccount.rawValue == "deleteOwnAccount")
        #expect(CloudFunctionName.allCases.contains(.deleteOwnAccount))
    }

    @Test func contentDeletionUsesDedicatedServerCallables() {
        #expect(CloudFunctionName.deleteNews.rawValue == "deleteNews")
        #expect(CloudFunctionName.deleteOrganization.rawValue == "deleteOrganization")
        #expect(CloudFunctionName.allCases.contains(.deleteNews))
        #expect(CloudFunctionName.allCases.contains(.deleteOrganization))
    }

    @Test func organizationPhotoMutationsUseDedicatedServerCallables() {
        #expect(
            CloudFunctionName.createOrganizationPhotoMetadata.rawValue
                == "createOrganizationPhotoMetadata"
        )
        #expect(
            CloudFunctionName.deleteOrganizationPhotoMetadata.rawValue
                == "deleteOrganizationPhotoMetadata"
        )
        #expect(CloudFunctionName.allCases.contains(.createOrganizationPhotoMetadata))
        #expect(CloudFunctionName.allCases.contains(.deleteOrganizationPhotoMetadata))
    }

    @Test func mediaStoragePathsAreCanonical() {
        #expect(MediaStoragePath.newsCover(newsID: "news-1") == "news/news-1/cover.jpg")
        #expect(MediaStoragePath.eventCover(eventID: "event-1") == "events/event-1/cover.jpg")
        #expect(
            MediaStoragePath.organizationPhoto(organizationID: "org-1", photoID: "photo-1")
                == "organizations/org-1/photos/photo-1.jpg"
        )
        #expect(MediaStoragePath.profileAvatar(userID: "user-1") == "profileImages/user-1/avatar.jpg")
    }

    private func makeEvent(id: String, startDate: Date, endDate: Date) -> Event {
        Event(
            id: id,
            title: id,
            summary: "Summary",
            details: "Details",
            source: ContentSourceMetadata(),
            city: "Innsbruck",
            venue: "Venue",
            startDate: startDate,
            endDate: endDate,
            createdAt: startDate.addingTimeInterval(-3_600),
            updatedAt: startDate.addingTimeInterval(-1_800),
            capacity: nil,
            registeredCount: 0,
            comments: [],
            moderationStatus: .approved,
            registrationState: .notRegistered,
            likeCount: 0,
            likeState: .notLiked
        )
    }
}
