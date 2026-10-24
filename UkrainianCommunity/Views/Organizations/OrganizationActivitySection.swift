import Combine
import MapKit
import PhotosUI
import SwiftUI

extension OrganizationDetailView {
    var organizationSectionTabs: some View {
        AppHorizontalFilterRow {
            ForEach(OrganizationDetailSection.allCases) { section in
                Button {
                    switchToSection(section)
                } label: {
                    AppFilterChip(
                        title: section.title,
                        systemImage: section.systemImage,
                        isSelected: selectedSection == section
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("organization.section.\(section)")
            }
        }
        .accessibilityIdentifier("organization.sections")
    }

    @ViewBuilder
    func selectedSectionContent(for organization: Organization) -> some View {
        switch selectedSection {
        case .events:
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                organizationEventFilters
                organizationActivityList(
                    title: AppStrings.Organizations.tabEvents,
                    items: upcomingOrganizationEvents,
                    emptySystemImage: "calendar",
                    emptyMessage: AppStrings.Organizations.emptyOrganizationEvents,
                    sortAscending: true
                )
            }
        case .news:
            organizationActivityList(
                title: AppStrings.Organizations.tabNews,
                items: organizationNewsItems,
                emptySystemImage: "newspaper",
                emptyMessage: AppStrings.Organizations.emptyOrganizationNews,
                sortAscending: false
            )
        case .about:
            aboutCard(for: organization)
        case .contacts:
            contactCard(for: organization)
        case .team:
            organizationTeamSection
        case .photos:
            OrganizationPhotoGallerySection(
                organizationId: organization.id,
                canManage: presentationMode.allowsManagementControls
                    && PermissionService.canManageOrganizationPhotos(organization, user: authState.user),
                currentUser: authState.user,
                repository: photoRepository,
                refreshToken: photoRefreshToken,
                onPhotosChanged: { photos in
                    previewPhotos = photos
                    loadedPreviewPhotoOrganizationID = organization.id
                }
            )
        }
    }

    var upcomingOrganizationEvents: [OrganizationActivityItem] {
        let now = Date()
        return organizationEventItems
            .filter { $0.isUpcomingEvent(at: now) }
            .filter { item in
                selectedOrganizationEventCategory == nil || item.eventCategory == selectedOrganizationEventCategory
                    || item.eventAdditionalCategories.contains { $0 == selectedOrganizationEventCategory }
            }
            .filter { item in
                guard let audience = selectedOrganizationEventAudience else { return true }
                return item.eventAudience == .everyone || item.eventAudience == audience
            }
            .filter { item in
                guard let range = selectedOrganizationEventAge.ageRange else { return true }
                let minimum = item.eventMinimumAge ?? 0
                let maximum = item.eventMaximumAge ?? 120
                guard minimum <= maximum else { return false }
                let eventRange = minimum...maximum
                return eventRange.overlaps(range)
            }
            .sorted {
                let lhsDate = $0.eventStartDate ?? $0.publishedAt
                let rhsDate = $1.eventStartDate ?? $1.publishedAt
                return lhsDate == rhsDate ? $0.id < $1.id : lhsDate < rhsDate
            }
    }

    var organizationEventItems: [OrganizationActivityItem] {
        activityViewModel.items
            .filter { $0.itemType == .event }
            .sorted {
                let lhsDate = $0.eventStartDate ?? $0.publishedAt
                let rhsDate = $1.eventStartDate ?? $1.publishedAt
                return lhsDate == rhsDate ? $0.id < $1.id : lhsDate < rhsDate
            }
    }

    var organizationNewsItems: [OrganizationActivityItem] {
        activityViewModel.items
            .filter { $0.itemType == .news }
            .sorted {
                $0.publishedAt == $1.publishedAt ? $0.id < $1.id : $0.publishedAt > $1.publishedAt
            }
    }

    var organizationEventFilters: some View {
        AppHorizontalFilterRow {
            Menu {
                Button(AppStrings.Events.allCategories) { selectedOrganizationEventCategory = nil }
                ForEach(EventCategory.allCases) { category in
                    Button { selectedOrganizationEventCategory = category } label: {
                        Label(category.title, systemImage: category.systemImage)
                    }
                }
            } label: {
                AppFilterChip(
                    title: selectedOrganizationEventCategory?.title ?? AppStrings.Events.allCategories,
                    systemImage: selectedOrganizationEventCategory?.systemImage ?? "tag",
                    isSelected: selectedOrganizationEventCategory != nil,
                    trailingSystemImage: "chevron.down"
                )
            }
            .buttonStyle(.plain)

            Menu {
                Button(AppStrings.Events.audienceAll) { selectedOrganizationEventAudience = nil }
                ForEach(EventAudience.allCases.filter { $0 != .everyone }) { audience in
                    Button { selectedOrganizationEventAudience = audience } label: {
                        Label(audience.title, systemImage: audience.systemImage)
                    }
                }
            } label: {
                AppFilterChip(
                    title: selectedOrganizationEventAudience?.title ?? AppStrings.Events.audienceAll,
                    systemImage: selectedOrganizationEventAudience?.systemImage ?? "person.3",
                    isSelected: selectedOrganizationEventAudience != nil,
                    trailingSystemImage: "chevron.down"
                )
            }
            .buttonStyle(.plain)

            Menu {
                ForEach(OrganizationEventAgeFilter.allCases) { ageFilter in
                    Button { selectedOrganizationEventAge = ageFilter } label: {
                        Label(ageFilter.title, systemImage: "birthday.cake")
                    }
                }
            } label: {
                AppFilterChip(
                    title: selectedOrganizationEventAge.title,
                    systemImage: "birthday.cake",
                    isSelected: selectedOrganizationEventAge != .any,
                    trailingSystemImage: "chevron.down"
                )
            }
            .buttonStyle(.plain)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AppStrings.Events.organizationEventFilters)
    }

    func organizationActivityList(
        title: String,
        items: [OrganizationActivityItem],
        emptySystemImage: String,
        emptyMessage: String,
        sortAscending: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
            if let error = activityViewModel.error(section: selectedSection) {
                ErrorStateCard(systemImage: emptySystemImage, title: title,
                    message: readableOrganizationErrorText(error), retryTitle: AppStrings.Organizations.retry) {
                    guard let organization = viewModel.organization(for: organizationID) else { return }
                    Task { await refreshOrganizationActivity(for: organization, section: selectedSection) }
                }
                .accessibilityIdentifier("organization.activity.error")
            }
            if items.isEmpty && (activityViewModel.isLoading(section: selectedSection)
                || (!activityViewModel.hasLoaded(section: selectedSection) && activityViewModel.error(section: selectedSection) == nil)) {
                LoadingStateCard(title: nil)
            } else if items.isEmpty && activityViewModel.error(section: selectedSection) == nil {
                organizationCompactPlaceholder(systemImage: emptySystemImage, title: title, message: emptyMessage)
            } else if !items.isEmpty {
                DetailCard {
                    VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                        Text(title).font(AppTheme.sectionTitleFont).foregroundStyle(AppTheme.textPrimary)
                        ForEach(items) { item in
                            if let destination = item.destination {
                                NavigationLink { activityDestinationView(for: destination) } label: {
                                    OrganizationActivityCompactCard(item: item)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("organization.activity.\(item.id)")
                            }
                        }
                    }
                }
            }
            if activityViewModel.hasMore(section: selectedSection) {
                PrimaryActionButton(title: AppStrings.Organizations.showMore,
                    isLoading: activityViewModel.isLoading(section: selectedSection)) {
                    guard let organization = viewModel.organization(for: organizationID) else { return }
                    Task { await activityViewModel.loadMore(for: organization, section: selectedSection) }
                }
                .accessibilityIdentifier("organization.activity.loadMore")
            }
        }
    }

    func organizationCompactPlaceholder(systemImage: String, title: String, message: String, badge: String? = nil) -> some View {
        UnifiedEmptyStateCard(systemImage: systemImage, title: title, message: message) {
            if let badge {
                Text(badge)
                    .font(AppTheme.metadataStrongFont)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(AppTheme.surfaceControl.opacity(0.34), in: Capsule())
                    .overlay(Capsule().strokeBorder(AppTheme.borderSubtle))
            }
        }
    }
}
