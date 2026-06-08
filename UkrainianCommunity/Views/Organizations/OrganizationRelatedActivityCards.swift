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
        .foregroundStyle(AppTheme.accentPrimary)
    }

    func switchToSection(_ section: OrganizationDetailSection) {
        withAnimation(.snappy) {
            selectedSection = section
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
                            await refreshOrganizationActivity(for: organization)
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
        let words = organization.name
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

    private let thumbnailSize: CGFloat = 58

    var body: some View {
        SoftContentCard(padding: AppTheme.organizationsCardPadding) {
            HStack(alignment: .center, spacing: AppTheme.eventsCardHorizontalSpacing) {
                thumbnail

                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(AppTheme.cardTitleFont)
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    metadataRow
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    @ViewBuilder
    private var thumbnail: some View {
        AppFeedThumbnail(
            imageURL: item.imageURL,
            fallbackSystemImage: itemTypeSystemImage,
            tint: AppTheme.accentPrimary,
            fill: AppTheme.accentPrimary.opacity(0.10),
            size: thumbnailSize,
            cornerRadius: AppTheme.feedThumbnailRadius,
            source: "OrganizationActivityCompactCard"
        )
        .frame(width: thumbnailSize, height: thumbnailSize, alignment: .center)
    }

    private var metadataRow: some View {
        HStack(spacing: 6) {
            ContentMetadataPill(systemImage: itemTypeSystemImage, text: itemTypeTitle)
                .fixedSize(horizontal: true, vertical: false)

            if let eventText = organizationActivityEventText(for: item) {
                ContentMetadataPill(systemImage: "clock", text: eventText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                ContentMetadataPill(systemImage: "calendar", text: organizationActivityDateText(for: item))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if isPinned {
                ContentMetadataPill(systemImage: "pin.fill", text: AppStrings.Organizations.pinnedLabel)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }

    private var itemTypeTitle: String {
        switch item.itemType {
        case .news:
            AppStrings.News.title
        case .event:
            AppStrings.Tabs.events
        case .organizationProfile:
            AppStrings.Tabs.organizations
        }
    }

    private var itemTypeSystemImage: String {
        switch item.itemType {
        case .news:
            "newspaper"
        case .event:
            "calendar"
        case .organizationProfile:
            "building.2"
        }
    }

    private var accessibilitySummary: String {
        var parts = [itemTypeTitle, item.title, item.summary]

        if let eventText = organizationActivityEventText(for: item) {
            parts.append(eventText)
        }

        if let locationText = organizationActivityLocationText(for: item) {
            parts.append(locationText)
        }

        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

struct OrganizationActivityCard: View {
    let item: OrganizationActivityItem

    var body: some View {
        CommunityCard {
            if item.imageURL != nil {
                RemoteCardImage(imageURL: item.imageURL, height: 160, source: "OrganizationActivityCard", isDecorative: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        ContentMetadataPill(systemImage: itemTypeSystemImage, text: itemTypeTitle)
                        ContentMetadataPill(systemImage: "calendar", text: organizationActivityDateText(for: item))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ContentMetadataPill(systemImage: itemTypeSystemImage, text: itemTypeTitle)
                        ContentMetadataPill(systemImage: "calendar", text: organizationActivityDateText(for: item))
                    }
                }

                Text(item.title)
                    .font(AppTheme.sectionTitleFont)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(item.summary)
                    .font(AppTheme.secondaryBodyFont)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let eventText = organizationActivityEventText(for: item) {
                    ContentMetadataPill(systemImage: "clock", text: eventText)
                }

                if let locationText = organizationActivityLocationText(for: item) {
                    ContentMetadataPill(systemImage: "mappin.and.ellipse", text: locationText)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var itemTypeTitle: String {
        switch item.itemType {
        case .news:
            AppStrings.News.title
        case .event:
            AppStrings.Tabs.events
        case .organizationProfile:
            AppStrings.Tabs.organizations
        }
    }

    private var itemTypeSystemImage: String {
        switch item.itemType {
        case .news:
            "newspaper"
        case .event:
            "calendar"
        case .organizationProfile:
            "building.2"
        }
    }

    private var accessibilitySummary: String {
        var parts = [itemTypeTitle, item.title, item.summary, organizationActivityDateText(for: item)]

        if let eventText = organizationActivityEventText(for: item) {
            parts.append(eventText)
        }

        if let locationText = organizationActivityLocationText(for: item) {
            parts.append(locationText)
        }

        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
