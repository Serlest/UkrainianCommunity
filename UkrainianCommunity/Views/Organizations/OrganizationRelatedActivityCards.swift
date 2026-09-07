import Combine
import MapKit
import PhotosUI
import SwiftUI

extension OrganizationDetailView {
    func hasCommunityHighlights(for organization: Organization) -> Bool {
        highlightedEvent(for: organization) != nil ||
            !highlightedNewsItems(for: organization).isEmpty ||
            !previewPhotos.isEmpty
    }

    func communityHighlightsBlock(for organization: Organization) -> some View {
        DetailCard {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                Text(AppStrings.Organizations.communityHighlightsTitle)
                    .font(AppTheme.sectionTitleFont)
                    .foregroundStyle(AppTheme.textPrimary)

                if let event = highlightedEvent(for: organization) {
                    highlightedEventSection(event)
                }

                let newsItems = highlightedNewsItems(for: organization)
                if !newsItems.isEmpty {
                    highlightedNewsSection(newsItems, organization: organization)
                }

                if !previewPhotos.isEmpty {
                    highlightedPhotosSection
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    func highlightedEventSection(_ item: OrganizationActivityItem) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
            organizationHighlightHeader(title: AppStrings.Organizations.nearestEventTitle, actionTitle: AppStrings.Organizations.viewAction) {
                if let destination = item.destination {
                    NavigationLink {
                        activityDestinationView(for: destination)
                    } label: {
                        highlightActionLabel(AppStrings.Organizations.viewAction)
                    }
                    .buttonStyle(.plain)
                }
            }

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

    func highlightedNewsSection(_ items: [OrganizationActivityItem], organization: Organization) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
            organizationHighlightHeader(title: AppStrings.Organizations.latestNewsTitle, actionTitle: AppStrings.Organizations.allNewsAction) {
                Button {
                    switchToSection(.news)
                } label: {
                    highlightActionLabel(AppStrings.Organizations.allNewsAction)
                }
                .buttonStyle(.plain)
            }

            ForEach(items) { item in
                if let destination = item.destination {
                    NavigationLink {
                        activityDestinationView(for: destination)
                    } label: {
                        OrganizationActivityCompactCard(item: item, isPinned: isPinnedNews(item, for: organization))
                    }
                    .buttonStyle(.plain)
                } else {
                    OrganizationActivityCompactCard(item: item, isPinned: isPinnedNews(item, for: organization))
                }
            }
        }
    }

    func organizationHighlightHeader<Content: View>(
        title: String,
        actionTitle: String,
        @ViewBuilder action: () -> Content
    ) -> some View {
        HStack(alignment: .center) {
            Text(title)
                .font(AppTheme.cardTitleFont)
                .foregroundStyle(AppTheme.textPrimary)

            Spacer(minLength: AppTheme.eventsMetadataSpacing)

            action()
                .accessibilityLabel(actionTitle)
        }
    }

    func highlightActionLabel(_ title: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
            Image(systemName: "chevron.right")
                .font(AppTheme.badgeFont)
        }
        .font(AppTheme.metadataStrongFont)
        .foregroundStyle(AppTheme.accentPrimaryForeground)
    }

    func switchToSection(_ section: OrganizationDetailSection) {
        if reduceMotion {
            selectedSection = section
        } else {
            withAnimation(.snappy) {
                selectedSection = section
            }
        }
    }

    func highlightedEvent(for organization: Organization) -> OrganizationActivityItem? {
        if let pinnedEventId = organization.pinnedEventId,
           let pinnedEvent = organizationEventItems.first(where: { destinationID(for: $0) == pinnedEventId }) {
            return pinnedEvent
        }

        return upcomingOrganizationEvents.first
    }

    func highlightedNewsItems(for organization: Organization) -> [OrganizationActivityItem] {
        var selected: [OrganizationActivityItem] = []

        if let pinnedNewsId = organization.pinnedNewsId,
           let pinnedNews = organizationNewsItems.first(where: { destinationID(for: $0) == pinnedNewsId }) {
            selected.append(pinnedNews)
        }

        for item in organizationNewsItems where selected.count < 2 && !selected.contains(where: { $0.id == item.id }) {
            selected.append(item)
        }

        return selected
    }

    func isPinnedNews(_ item: OrganizationActivityItem, for organization: Organization) -> Bool {
        guard let pinnedNewsId = organization.pinnedNewsId else { return false }
        return destinationID(for: item) == pinnedNewsId
    }

    func destinationID(for item: OrganizationActivityItem) -> String? {
        guard let destination = item.destination else { return nil }
        switch destination {
        case let .news(id), let .event(id), let .organization(id):
            return id
        }
    }

    func activitySection(for organization: Organization) -> some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                HStack {
                    AppEditorSectionTitle(title: AppStrings.Organizations.upcomingEventsTitle)

                    Spacer(minLength: AppTheme.eventsMetadataSpacing)

                }

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
                            await refreshOrganizationActivity(for: organization, section: selectedSection)
                        }
                    }
                } else {
                    let eventItems = activityViewModel.items.filter { $0.itemType == .event }

                    if eventItems.isEmpty {
                        EmptyStateCard(
                            systemImage: "calendar",
                            title: AppStrings.Organizations.upcomingEventsTitle,
                            message: AppStrings.Organizations.empty
                        )
                    } else {
                        ForEach(eventItems) { item in
                            if let destination = item.destination {
                                NavigationLink {
                                    activityDestinationView(for: destination)
                                } label: {
                                    OrganizationActivityCard(item: item)
                                }
                                .buttonStyle(.plain)
                            } else {
                                OrganizationActivityCard(item: item)
                            }
                        }
                    }
                }
            }
        }
    }

    func organizationInitials(for organization: Organization) -> String {
        let words = organization.localizedName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        let initials = String(words).uppercased()
        return initials.isEmpty ? "UC" : initials
    }

    @ViewBuilder
    func activityDestinationView(for destination: HomeFeedDestinationReference) -> some View {
        switch destination {
        case let .news(id):
            NewsDetailView(
                viewModel: newsDetailViewModel,
                postID: id,
                onNewsDeleted: {}
            )
        case let .event(id):
            EventDetailView(
                viewModel: eventsDetailViewModel,
                eventID: id,
                onEventDeleted: {}
            )
        case let .organization(id):
            OrganizationDetailView(
                viewModel: viewModel,
                organizationID: id,
                newsViewModel: newsDetailViewModel,
                eventsViewModel: eventsDetailViewModel,
                onOrganizationSaved: onOrganizationSaved,
                onOrganizationDeleted: onOrganizationDeleted
            )
            .environment(\.organizationPresentationMode, presentationMode)
        }
    }
}

struct OrganizationActivityCompactCard: View {
    let item: OrganizationActivityItem
    var isPinned = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ContentFeedCard(item: item.feedItem)
            if isPinned { Label(AppStrings.Organizations.pinnedLabel, systemImage: "pin.fill").font(.caption).foregroundStyle(AppTheme.textSecondary) }
        }
    }
}

struct OrganizationActivityCard: View {
    let item: OrganizationActivityItem

    var body: some View {
        ContentFeedCard(item: item.feedItem)
    }
}
