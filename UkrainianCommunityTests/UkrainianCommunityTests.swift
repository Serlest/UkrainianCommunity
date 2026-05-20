//
//  UkrainianCommunityTests.swift
//  UkrainianCommunityTests
//
//  Created by Philipp Timofeev on 28.04.26.
//

import Foundation
import Testing
@testable import UkrainianCommunity

private actor RecordingFeedbackRepository: FeedbackRepository {
    private(set) var submittedItems: [FeedbackItem] = []

    func submitFeedback(_ feedback: FeedbackItem) async throws {
        submittedItems.append(feedback)
    }

    func snapshot() async -> [FeedbackItem] {
        submittedItems
    }
}

@MainActor
struct UkrainianCommunityTests {
    private func makeUser(
        id: String = UUID().uuidString,
        role: UserRole = .user,
        globalRole: GlobalRole? = nil,
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
            blockState: .active,
            communityMemberships: communityMemberships,
            createdAt: .now,
            updatedAt: .now
        )
    }

    @Test func moderatorPermissionsAreScopedCorrectly() {
        let userPermissions = PermissionService(role: .user)
        let moderatorPermissions = PermissionService(role: .moderator)
        let adminPermissions = PermissionService(role: .admin)
        let ownerPermissions = PermissionService(role: .owner)

        #expect(userPermissions.canCreateNews == false)
        #expect(userPermissions.canBlockUsers == false)
        #expect(moderatorPermissions.canCreateNews == true)
        #expect(moderatorPermissions.canDeleteNews == false)
        #expect(adminPermissions.canAssignModerator == true)
        #expect(adminPermissions.canBlockUsers == true)
        #expect(adminPermissions.canAssignAdmin == false)
        #expect(ownerPermissions.canManageUsers == true)
        #expect(ownerPermissions.canDeleteEvent == true)
        #expect(ownerPermissions.canAccessOwnerTools == true)
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
            authState.setAuthenticatedSession()
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

    @Test func permissionServiceSupportsOwnerTopAdminOrdinaryAndOrganizationManagerAccess() {
        let owner = makeUser(role: .owner)
        let topAdmin = makeUser(role: .admin, globalRole: .topAdmin)
        let ordinaryUser = makeUser(role: .user, globalRole: .user)
        let organizationManager = makeUser(
            role: .user,
            globalRole: .user,
            communityMemberships: [CommunityMembership(organizationId: "org-1", role: .communityAdmin)]
        )

        #expect(PermissionService.canDeleteNews(user: owner))
        #expect(PermissionService.canDeleteEvent(user: owner))
        #expect(PermissionService.canDeleteOrganization(user: owner))

        #expect(PermissionService.canAccessAdminTools(user: topAdmin))
        #expect(PermissionService.canAccessModerationTools(user: topAdmin))
        #expect(PermissionService.canAccessContentManagement(user: topAdmin))

        #expect(PermissionService.canAccessContentManagement(user: ordinaryUser) == false)
        #expect(PermissionService.canAccessOrganizationManagement(user: ordinaryUser) == false)
        #expect(PermissionService.canCreateNews(user: ordinaryUser) == false)
        #expect(PermissionService.canCreateEvent(user: ordinaryUser) == false)

        #expect(PermissionService.canAccessOrganizationManagement(user: organizationManager))
        #expect(PermissionService.canCreateNews(for: "org-1", user: organizationManager))
        #expect(PermissionService.canCreateEvent(for: "org-1", user: organizationManager))
        #expect(PermissionService.canEditOrganization(organizationId: "org-1", user: organizationManager))
        #expect(PermissionService.canCreateNews(for: "org-2", user: organizationManager) == false)
    }

    @Test func mockRepositoriesProvideFoundationContent() async throws {
        let user = try await MockUserRepository().fetchCurrentUser()
        let news = try await MockNewsRepository().fetchNews()
        let events = try await MockEventRepository().fetchEvents()
        let organizations = try await MockOrganizationRepository().fetchOrganizations()
        let info = try await MockInfoRepository().fetchGuideArticles()

        #expect(user.fullName.isEmpty == false)
        #expect(news.isEmpty == false)
        #expect(events.isEmpty == false)
        #expect(organizations.isEmpty == false)
        #expect(info.isEmpty == false)
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

        AppLanguage.stored = .ukrainian
        let ukrainianDate = LocalizationStore.dateString(from: sampleDate)

        #expect(germanDate != ukrainianDate)
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

    @Test func validationServicesRejectClearlyInvalidData() {
        let newsErrors = NewsValidationService().validate(title: "", subtitle: "", body: "short")
        let eventErrors = EventValidationService().validate(
            title: "",
            details: "short",
            startDate: .now,
            endDate: .now.addingTimeInterval(-60),
            city: "",
            venue: ""
        )

        #expect(newsErrors.isEmpty == false)
        #expect(eventErrors.isEmpty == false)
    }

    @Test func authValidationRejectsInvalidRegistrationAndResetInputs() {
        let service = AuthValidationService()

        let registrationErrors = service.validateRegistration(
            email: "invalid",
            password: "short",
            repeatedPassword: "different",
            displayName: " ",
            acceptedTerms: false,
            acceptedPrivacy: false
        )

        #expect(registrationErrors.contains(AppStrings.Validation.authEmailInvalid))
        #expect(registrationErrors.contains(AppStrings.Validation.authPasswordTooShort))
        #expect(registrationErrors.contains(AppStrings.Validation.authPasswordMismatch))
        #expect(registrationErrors.contains(AppStrings.Validation.authDisplayNameRequired))
        #expect(registrationErrors.contains(AppStrings.Validation.authTermsRequired))
        #expect(registrationErrors.contains(AppStrings.Validation.authPrivacyRequired))

        let resetErrors = service.validatePasswordReset(email: "nope")
        #expect(resetErrors == [AppStrings.Validation.authEmailInvalid])
    }

    @Test func authLegalVersionsAreStableAndNonEmpty() {
        #expect(AuthService.currentTermsVersion.isEmpty == false)
        #expect(AuthService.currentPrivacyVersion.isEmpty == false)
        #expect(AuthService.currentTermsVersion == "2026.1")
        #expect(AuthService.currentPrivacyVersion == "2026.1")
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
            privacyVersion: AuthService.currentPrivacyVersion
        )

        let payload = UserProfileService.makeRegisteredUserDocumentData(uid: "user-123", draft: draft)

        #expect(payload.id == "user-123")
        #expect(payload.role == UserRole.user.rawValue)
        #expect(payload.globalRole == GlobalRole.user.rawValue)
        #expect(payload.accountStatus == AccountStatus.active.rawValue)
        #expect(payload.blockState == UserBlockState.active.rawValue)
        #expect(payload.warningCount == 0)
        #expect(payload.moderatorSections.isEmpty)
        #expect(payload.communityMemberships.isEmpty)
        #expect(payload.displayName == "New User")
        #expect(payload.fullName == "New User")
        #expect(payload.email == "new@example.com")
        #expect(payload.selectedFederalState == AustrianFederalState.tirol.rawValue)
        #expect(payload.acceptedTermsAt == acceptedAt)
        #expect(payload.acceptedPrivacyAt == acceptedAt)
        #expect(payload.termsVersion == AuthService.currentTermsVersion)
        #expect(payload.privacyVersion == AuthService.currentPrivacyVersion)
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

    @Test func homeFeedViewModelSortsNewestFirstAndContainsSupportedItemTypes() async {
        let viewModel = HomeFeedViewModel(
            newsRepository: MockNewsRepository(),
            eventRepository: MockEventRepository(),
            organizationRepository: MockOrganizationRepository()
        )

        await viewModel.refresh()

        #expect(viewModel.items.isEmpty == false)
        #expect(viewModel.items.map(\.publishedAt) == viewModel.items.map(\.publishedAt).sorted(by: >))

        let itemTypes = Set(viewModel.items.map(\.itemType))
        #expect(itemTypes.contains(.news))
        #expect(itemTypes.contains(.event))
        #expect(itemTypes.contains(.organization))

        let destinations = viewModel.items.map(\.destination)
        #expect(destinations.contains { if case .news = $0 { return true } else { return false } })
        #expect(destinations.contains { if case .event = $0 { return true } else { return false } })
        #expect(destinations.contains { if case .organization = $0 { return true } else { return false } })
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
            feedbackRepository: feedbackRepository
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

        try await repository.registerForEvent(id: targetEvent.id)

        let registeredEvents = try await repository.fetchRegisteredEvents()

        #expect(registeredEvents.contains(where: { $0.id == targetEvent.id }))
        #expect(registeredEvents.allSatisfy { $0.registrationState == .registered })
        #expect(registeredEvents.map(\.startDate) == registeredEvents.map(\.startDate).sorted(by: <))
    }

    @Test func myRegistrationsViewModelCancelRegistrationRemovesEventAndUpdatesCount() async throws {
        let repository = MockEventRepository()
        let targetEvent = try #require((try await repository.fetchEvents()).first(where: { $0.registrationState == .registered }))
        let viewModel = MyRegistrationsViewModel(repository: repository)

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
        #expect(Set(FeedbackStatus.allCases) == Set([.open, .reviewed, .closed]))

        let item = FeedbackItem(
            id: "feedback-1",
            type: .bug,
            message: "Example",
            status: .open,
            createdAt: .now,
            userId: "user-1",
            userDisplayName: "Tester"
        )

        #expect(item.status == .open)
        #expect(item.type == .bug)
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
