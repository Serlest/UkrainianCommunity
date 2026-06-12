import Combine
import MapKit
import PhotosUI
import SwiftUI

extension OrganizationDetailView {
    var organizationSectionTabs: some View {
        AppHorizontalFilterRow {
            ForEach(OrganizationDetailSection.allCases) { section in
                Button {
                    withAnimation(.snappy) {
                        selectedSection = section
                    }
                } label: {
                    AppFilterChip(
                        title: section.title,
                        systemImage: section.systemImage,
                        isSelected: selectedSection == section
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    func selectedSectionContent(for organization: Organization) -> some View {
        switch selectedSection {
        case .events:
            organizationActivityList(
                title: AppStrings.Organizations.tabEvents,
                items: upcomingOrganizationEvents,
                emptySystemImage: "calendar",
                emptyMessage: AppStrings.Organizations.emptyOrganizationEvents,
                sortAscending: true
            )
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
            .sorted { ($0.eventStartDate ?? $0.publishedAt) < ($1.eventStartDate ?? $1.publishedAt) }
    }

    var organizationEventItems: [OrganizationActivityItem] {
        activityViewModel.items
            .filter { $0.itemType == .event }
            .sorted { ($0.eventStartDate ?? $0.publishedAt) < ($1.eventStartDate ?? $1.publishedAt) }
    }

    var organizationNewsItems: [OrganizationActivityItem] {
        activityViewModel.items
            .filter { $0.itemType == .news }
            .sorted { $0.publishedAt > $1.publishedAt }
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
