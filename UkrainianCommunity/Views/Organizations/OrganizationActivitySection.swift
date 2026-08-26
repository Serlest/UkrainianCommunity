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
                    && PermissionService.canModerateOrganizationContent(organization, user: authState.user),
                currentUser: authState.user,
                onPhotosChanged: { photos in
                    previewPhotos = photos
                    loadedPreviewPhotoOrganizationID = organization.id
                }
            )
        }
    }

    var upcomingOrganizationEvents: [OrganizationActivityItem] {
        let today = Calendar.current.startOfDay(for: Date())
        return organizationEventItems
            .filter { ($0.eventStartDate ?? $0.publishedAt) >= today }
            .filter { item in
                selectedOrganizationEventCategory == nil || item.eventCategory == selectedOrganizationEventCategory
            }
            .filter { item in
                guard let audience = selectedOrganizationEventAudience else { return true }
                return item.eventAudience == .everyone || item.eventAudience == audience
            }
            .filter { item in
                guard let range = selectedOrganizationEventAge.ageRange else { return true }
                let eventRange = (item.eventMinimumAge ?? 0)...(item.eventMaximumAge ?? 120)
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
        Group {
            if activityViewModel.isLoading && activityViewModel.items.isEmpty {
                LoadingStateCard(title: nil)
            } else if activityViewModel.items.isEmpty && activityViewModel.error != nil {
                ErrorStateCard(
                    systemImage: "building.2",
                    title: AppStrings.Organizations.activityTitle,
                    message: readableOrganizationErrorText(activityViewModel.error),
                    retryTitle: AppStrings.Organizations.retry
                ) {
                    Task {
                        if let organization = viewModel.organization(for: organizationID) {
                            await refreshOrganizationActivity(for: organization, section: selectedSection)
                        }
                    }
                }
            } else if items.isEmpty {
                organizationCompactPlaceholder(
                    systemImage: emptySystemImage,
                    title: title,
                    message: emptyMessage
                )
            } else {
                DetailCard {
                    VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                        Text(title)
                            .font(AppTheme.sectionTitleFont)
                            .foregroundStyle(AppTheme.textPrimary)

                        ForEach(items) { item in
                            if let destination = item.destination {
                                NavigationLink {
                                    activityDestinationView(for: destination)
                                } label: {
                                    OrganizationActivityCompactCard(item: item)
                                }
                                .buttonStyle(.plain)
                            } else {
                                OrganizationActivityCompactCard(item: item)
                            }
                        }
                    }
                }
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
