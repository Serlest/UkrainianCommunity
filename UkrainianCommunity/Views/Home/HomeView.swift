import Combine
import Foundation
import PhotosUI
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var authState: AuthState
    @ObservedObject var viewModel: HomeViewModel
    @ObservedObject var newsViewModel: NewsViewModel
    @ObservedObject var eventsViewModel: EventsViewModel
    @ObservedObject var organizationsViewModel: OrganizationsViewModel
    @State private var selectedBannerPhoto: PhotosPickerItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                homeHeader

                homeHero

                HomeFilterRow()

                feedContent
            }
            .padding(.horizontal, AppTheme.pageHorizontal)
            .padding(.bottom, 112)
        }
        .background(AppTheme.subtleGradient.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            await refreshAllContent()
        }
        .task {
            await loadContentIfNeeded()
            await refreshContentIfStale()
        }
        .onChange(of: selectedBannerPhoto) { _, newItem in
            Task {
                await updateHomeBanner(from: newItem)
                selectedBannerPhoto = nil
            }
        }
        .alert(
            AppStrings.Home.bannerUploadFailed,
            isPresented: Binding(
                get: { viewModel.bannerError != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.clearBannerError()
                    }
                }
            )
        ) {
            Button(AppStrings.News.dismissError, role: .cancel) {
                viewModel.clearBannerError()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newsChanged).debounce(for: .milliseconds(250), scheduler: RunLoop.main)) { _ in
            Task {
                async let homeRefresh: Void = viewModel.refresh()
                async let newsRefresh: Void = newsViewModel.refresh()
                _ = await (homeRefresh, newsRefresh)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eventsChanged).debounce(for: .milliseconds(250), scheduler: RunLoop.main)) { _ in
            Task {
                async let homeRefresh: Void = viewModel.refresh()
                async let eventsRefresh: Void = eventsViewModel.refresh()
                _ = await (homeRefresh, eventsRefresh)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .organizationsChanged).debounce(for: .milliseconds(250), scheduler: RunLoop.main)) { _ in
            Task {
                async let homeRefresh: Void = viewModel.refresh()
                async let organizationsRefresh: Void = organizationsViewModel.refresh()
                _ = await (homeRefresh, organizationsRefresh)
            }
        }
    }

    private var homeHero: some View {
        ZStack(alignment: .bottomTrailing) {
            AppHeroBanner(
                title: AppStrings.Home.bannerTitle,
                subtitle: AppStrings.Home.bannerSubtitle,
                imageSource: viewModel.bannerImageSource
            )

            if PermissionService.canManageHomeBanner(user: authState.user) {
                HomeBannerEditButton(
                    selectedItem: $selectedBannerPhoto,
                    isUploading: viewModel.isBannerUploading
                )
                .padding(10)
            }
        }
    }

    private var homeHeader: some View {
        BrandedScreenHeader(
            title: AppStrings.Home.brandTitle,
            subtitle: AppStrings.Home.brandSubtitle,
            brandAssetName: "logo1",
            showsBrandText: false,
            brandSize: CGSize(width: 190, height: 64)
        ) {
            HomeNotificationButton()
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var feedContent: some View {
        if viewModel.isLoading && viewModel.feedItems.isEmpty {
            LoadingStateCard(title: nil)
                .frame(maxWidth: .infinity, minHeight: 180)
        } else if viewModel.feedItems.isEmpty && viewModel.error != nil {
            ErrorStateCard(
                title: AppStrings.Tabs.home,
                message: homeErrorText,
                retryTitle: AppStrings.News.retry
            ) {
                viewModel.reload()
            }
            .frame(maxWidth: .infinity, minHeight: 180)
        } else if viewModel.feedItems.isEmpty {
            EmptyStateCard(
                systemImage: "tray",
                title: AppStrings.Tabs.home,
                message: AppStrings.Common.noItems
            )
            .frame(maxWidth: .infinity, minHeight: 180)
        } else {
            DashboardFeedContainer(items: viewModel.feedItems, spacing: 10) { item in
                NavigationLink {
                    destinationView(for: item)
                } label: {
                    HomeFeedCard(item: item)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func loadContentIfNeeded() async {
        async let homeLoad: Void = viewModel.loadIfNeeded()
        async let bannerLoad: Void = viewModel.loadBannerIfNeeded()
        async let newsLoad: Void = newsViewModel.loadIfNeeded()
        async let eventsLoad: Void = eventsViewModel.loadIfNeeded()
        async let organizationsLoad: Void = organizationsViewModel.loadIfNeeded()
        _ = await (homeLoad, bannerLoad, newsLoad, eventsLoad, organizationsLoad)
    }

    private func refreshContentIfStale() async {
        async let homeRefresh: Void = viewModel.refreshIfStale()
        async let bannerLoad: Void = viewModel.loadBannerIfNeeded()
        async let newsRefresh: Void = newsViewModel.refreshIfStale()
        async let eventsRefresh: Void = eventsViewModel.refreshIfStale()
        async let organizationsRefresh: Void = organizationsViewModel.refreshIfStale()
        _ = await (homeRefresh, bannerLoad, newsRefresh, eventsRefresh, organizationsRefresh)
    }

    private func refreshAllContent() async {
        async let homeRefresh: Void = viewModel.refresh()
        async let bannerRefresh: Void = viewModel.refreshBanner()
        async let newsRefresh: Void = newsViewModel.refresh()
        async let eventsRefresh: Void = eventsViewModel.refresh()
        async let organizationsRefresh: Void = organizationsViewModel.refresh()
        _ = await (homeRefresh, bannerRefresh, newsRefresh, eventsRefresh, organizationsRefresh)
    }

    private func updateHomeBanner(from item: PhotosPickerItem?) async {
        guard let item else { return }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                viewModel.setBannerSelectionFailed()
                return
            }

            await viewModel.updateHomeBannerImage(data: data, user: authState.user)
        } catch {
            viewModel.setBannerSelectionFailed()
        }
    }

    private var homeErrorText: String {
        switch viewModel.error {
        case .network:
            AppStrings.News.loadNetworkError
        case .permissionDenied:
            AppStrings.News.loadPermissionError
        case .validationFailed:
            AppStrings.News.loadValidationError
        case .notFound:
            AppStrings.Common.noItems
        case .unknown:
            AppStrings.News.loadUnknownError
        case nil:
            ""
        }
    }

    @ViewBuilder
    private func destinationView(for item: HomeFeedItem) -> some View {
        switch item.destination {
        case let .news(id):
            NewsDetailView(viewModel: newsViewModel, postID: id, onNewsDeleted: {})
        case let .event(id):
            EventDetailView(viewModel: eventsViewModel, eventID: id, onEventDeleted: {})
        case let .organization(id):
            OrganizationDetailView(viewModel: organizationsViewModel, organizationID: id)
        }
    }
}

private struct HomeFilterRow: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                HomeFilterChip(title: AppStrings.Home.filterAll, systemImage: "square.grid.2x2", isSelected: true)
                HomeFilterChip(title: AppStrings.Home.filterSubscriptions, systemImage: "bookmark", isSelected: false)
                HomeFilterChip(title: AppStrings.Home.filterFavorites, systemImage: "star", isSelected: false)
                HomeFilterChip(
                    title: AppStrings.Home.regionAllAustria,
                    systemImage: "mappin.and.ellipse",
                    isSelected: false,
                    trailingSystemImage: "chevron.down"
                )
            }
        }
        .scrollClipDisabled()
    }
}

private struct HomeFilterChip: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let trailingSystemImage: String?

    init(title: String, systemImage: String, isSelected: Bool, trailingSystemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.trailingSystemImage = trailingSystemImage
    }

    var body: some View {
        AppInfoChip(
            title: title,
            systemImage: systemImage,
            tint: isSelected ? AppTheme.accentPrimary : AppTheme.textSecondary,
            fill: isSelected ? AppTheme.badgeBlueFill : AppTheme.surfaceElevated,
            border: isSelected ? nil : AppTheme.borderSubtle,
            trailingSystemImage: trailingSystemImage,
            size: .regular
        )
        .frame(minHeight: 38)
    }
}

private struct HomeNotificationButton: View {
    var body: some View {
        Button {
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(AppTheme.accentPrimary)
                    .frame(width: 40, height: 40)

                Circle()
                    .fill(AppTheme.accentDestructive)
                    .frame(width: 8, height: 8)
                    .offset(x: -6, y: 6)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppStrings.Home.notifications)
    }
}

private struct HomeBannerEditButton: View {
    @Binding var selectedItem: PhotosPickerItem?
    let isUploading: Bool

    var body: some View {
        PhotosPicker(selection: $selectedItem, matching: .images, photoLibrary: .shared()) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 34, height: 34)
                    .overlay(
                        Circle()
                            .stroke(AppTheme.borderSubtle, lineWidth: 1)
                    )

                if isUploading {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: "photo.badge.plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accentPrimary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isUploading)
        .accessibilityLabel(AppStrings.Home.changeBanner)
    }
}

private struct HomeFeedCard: View {
    let item: HomeFeedItem

    var body: some View {
        SoftContentCard(padding: 9) {
            HStack(alignment: .top, spacing: 11) {
                AppFeedThumbnail(
                    imageURL: item.imageURL,
                    fallbackSystemImage: itemTypeSystemImage,
                    tint: itemTypeTint,
                    fill: itemTypeFill,
                    size: thumbnailSize,
                    source: "HomeFeedCard"
                )

                VStack(alignment: .leading, spacing: 4) {
                    typeChip

                    Text(item.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)

                    if shouldShowPreview, !item.summary.isEmpty {
                        Text(item.summary)
                            .font(.caption2)
                            .foregroundStyle(AppTheme.textSecondary.opacity(0.78))
                            .lineLimit(1)
                    }

                    if item.itemType == .event {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 10) {
                                metadataLine
                                if let secondaryMetadataText {
                                    AppMetadataLine(title: secondaryMetadataText, systemImage: "mappin.and.ellipse")
                                }
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                metadataLine
                                if let secondaryMetadataText {
                                    AppMetadataLine(title: secondaryMetadataText, systemImage: "mappin.and.ellipse")
                                }
                            }
                        }
                    }
                }

                Spacer(minLength: 2)

                rightAccessory
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var typeChip: some View {
        AppInfoChip(
            title: itemTypeTitle.uppercased(),
            systemImage: itemTypeSystemImage,
            tint: itemTypeTint,
            fill: itemTypeFill,
            size: .small
        )
    }

    private var timestampText: some View {
        Text(publishedDateText)
            .font(.caption2.weight(.medium))
            .foregroundStyle(AppTheme.textSecondary)
            .lineLimit(1)
    }

    @ViewBuilder
    private var rightAccessory: some View {
        if item.itemType == .event, let eventStartDate = item.eventStartDate {
            HStack(alignment: .top, spacing: 6) {
                AppDateBadge(date: eventStartDate)
                bookmarkIcon
            }
        } else {
            VStack(alignment: .trailing, spacing: 8) {
                timestampText
                Spacer(minLength: 8)
                bookmarkIcon
            }
            .frame(minHeight: AppTheme.feedThumbnailSize)
        }
    }

    private var bookmarkIcon: some View {
        Image(systemName: "bookmark")
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.textSecondary.opacity(0.78))
            .frame(width: 20, height: 20)
    }

    private var metadataLine: some View {
        AppMetadataLine(title: primaryMetadataText, systemImage: primaryMetadataIcon)
    }

    private var itemTypeTitle: String {
        switch item.itemType {
        case .news:
            AppStrings.News.title
        case .event:
            AppStrings.Tabs.events
        case .organization:
            AppStrings.Tabs.organizations
        }
    }

    private var itemTypeSystemImage: String {
        switch item.itemType {
        case .news:
            "newspaper"
        case .event:
            "calendar"
        case .organization:
            "building.2"
        }
    }

    private var itemTypeTint: Color {
        switch item.itemType {
        case .news:
            Color.green
        case .event:
            AppTheme.accentPrimary
        case .organization:
            Color.purple
        }
    }

    private var itemTypeFill: Color {
        switch item.itemType {
        case .news:
            AppTheme.badgeGreenFill
        case .event:
            AppTheme.badgeBlueFill
        case .organization:
            AppTheme.badgePurpleFill
        }
    }

    private var thumbnailSize: CGFloat {
        item.itemType == .event ? AppTheme.feedThumbnailSize + 2 : AppTheme.feedThumbnailSize + 8
    }

    private var shouldShowPreview: Bool {
        item.itemType == .news || item.itemType == .event
    }

    private var publishedDateText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = LocalizationStore.locale
        formatter.unitsStyle = .short
        return formatter.localizedString(for: item.publishedAt, relativeTo: Date())
    }

    private var primaryMetadataText: String {
        if item.itemType == .event, let eventStartDate = item.eventStartDate {
            return LocalizationStore.timeRangeString(startDate: eventStartDate, endDate: item.eventEndDate)
        }

        if let city = item.city, !city.isEmpty {
            return city
        }

        if let organizationName = item.organizationName, !organizationName.isEmpty {
            return organizationName
        }

        return sourceTypeTitle
    }

    private var primaryMetadataIcon: String {
        item.itemType == .event ? "clock" : "mappin.and.ellipse"
    }

    private var secondaryMetadataText: String? {
        guard item.itemType == .event else { return nil }
        if let city = item.city, !city.isEmpty {
            return city
        }
        return nil
    }

    private var sourceTypeTitle: String {
        switch item.sourceType {
        case .app:
            AppStrings.Common.app
        case .organization:
            AppStrings.Tabs.organizations
        }
    }

    private var accessibilitySummary: String {
        var parts = [itemTypeTitle, item.title]

        if !item.summary.isEmpty {
            parts.append(item.summary)
        }

        parts.append(primaryMetadataText)

        parts.append("\(item.likeCount) \(AppStrings.Common.likes)")
        return parts.joined(separator: ", ")
    }
}

#Preview {
    NavigationStack {
        HomeView(
            viewModel: HomeViewModel(
                newsRepository: MockNewsRepository(),
                eventRepository: MockEventRepository(),
                organizationRepository: MockOrganizationRepository(),
                homeBannerService: MockHomeBannerService()
            ),
            newsViewModel: NewsViewModel(repository: MockNewsRepository()),
            eventsViewModel: EventsViewModel(repository: MockEventRepository()),
            organizationsViewModel: OrganizationsViewModel(repository: MockOrganizationRepository())
        )
    }
    .environmentObject(AuthState())
}
