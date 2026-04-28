//
//  UkrainianCommunityTests.swift
//  UkrainianCommunityTests
//
//  Created by Philipp Timofeev on 28.04.26.
//

import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct UkrainianCommunityTests {
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

    @Test func mockRepositoriesProvideFoundationContent() async throws {
        let user = try await MockUserRepository().fetchCurrentUser()
        let news = try await MockNewsRepository().fetchNews()
        let events = try await MockEventRepository().fetchEvents()
        let organizations = try await MockOrganizationRepository().fetchOrganizations()
        let marketplace = try await MockMarketplaceRepository().fetchMarketplaceItems()
        let info = try await MockInfoRepository().fetchInfoItems()

        #expect(user.fullName.isEmpty == false)
        #expect(news.isEmpty == false)
        #expect(events.isEmpty == false)
        #expect(organizations.isEmpty == false)
        #expect(marketplace.isEmpty == false)
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
        let marketplaceErrors = MarketplaceValidationService().validate(
            title: "",
            description: "short",
            city: "",
            price: Decimal(-1),
            isFreeGift: false,
            expirationDate: .now.addingTimeInterval(-60),
            contactValue: ""
        )

        #expect(newsErrors.isEmpty == false)
        #expect(eventErrors.isEmpty == false)
        #expect(marketplaceErrors.isEmpty == false)
    }

    @Test func contentModelsCarryModerationStatus() async throws {
        let news = try await MockNewsRepository().fetchNews()
        let events = try await MockEventRepository().fetchEvents()
        let organizations = try await MockOrganizationRepository().fetchOrganizations()
        let marketplace = try await MockMarketplaceRepository().fetchMarketplaceItems()

        #expect(news.contains(where: { $0.moderationStatus == .approved }))
        #expect(events.contains(where: { $0.moderationStatus == .draft }))
        #expect(organizations.contains(where: { $0.moderationStatus == .archived }))
        #expect(marketplace.contains(where: { $0.moderationStatus == .pendingReview }))
    }

    @Test func dtoMappingRoundTripPreservesIdentifiers() async throws {
        let user = try await MockUserRepository().fetchCurrentUser()
        let news = try await MockNewsRepository().fetchNews()
        let events = try await MockEventRepository().fetchEvents()
        let organizations = try await MockOrganizationRepository().fetchOrganizations()
        let marketplaceItems = try await MockMarketplaceRepository().fetchMarketplaceItems()
        let event = try #require(events.first)
        let organization = try #require(organizations.first)
        let marketplaceItem = try #require(marketplaceItems.first)

        let restoredUser = AppUser(dto: user.dto)
        let restoredNews = NewsPost(dto: news[0].dto)
        let restoredEvent = Event(dto: event.dto)
        let restoredOrganization = Organization(dto: organization.dto)
        let restoredMarketplaceItem = MarketplaceItem(dto: marketplaceItem.dto)

        #expect(restoredUser.id == user.id)
        #expect(restoredNews.id == news[0].id)
        #expect(restoredEvent.id == event.id)
        #expect(restoredOrganization.id == organization.id)
        #expect(restoredMarketplaceItem.id == marketplaceItem.id)
    }
}
