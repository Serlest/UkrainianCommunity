import Combine
import SwiftUI

private func sanitizedHomeAuthorName(_ rawValue: String) -> String {
    let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedValue.isEmpty else {
        return AppStrings.NewsEditor.authorFallback
    }

    guard trimmedValue.count >= 20 else {
        return trimmedValue
    }

    guard trimmedValue.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
        return trimmedValue
    }

    let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    if trimmedValue.rangeOfCharacter(from: allowedCharacters.inverted) == nil {
        return AppStrings.NewsEditor.authorFallback
    }

    return trimmedValue
}

struct HomeView: View {
    @EnvironmentObject private var authState: AuthState
    @ObservedObject var viewModel: HomeViewModel
    @ObservedObject var newsViewModel: NewsViewModel
    @ObservedObject var eventsViewModel: EventsViewModel
    @ObservedObject var organizationsViewModel: OrganizationsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                homeHero
                    .padding(.top, 8)

                feedContent
            }
            .padding(.horizontal, AppTheme.pageHorizontal)
            .padding(.bottom, 32)
            .padding(.bottom, 32)
        }
        .background(AppTheme.subtleGradient.ignoresSafeArea())
        .navigationTitle(AppStrings.Tabs.home)
        .navigationBarTitleDisplayMode(.large)
        .refreshable {
            await refreshAllContent()
        }
        .task {
            await loadContentIfNeeded()
            await refreshContentIfStale()
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
        GradientHeroCard(title: AppStrings.Home.title, subtitle: AppStrings.Home.subtitle) {
            VStack(alignment: .leading, spacing: 18) {
                Text(AppStrings.Home.feedTitle.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.76))

                if let user = authState.user {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(user.fullName.isEmpty ? AppStrings.Profile.loadingUserProfile : user.fullName)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white)

                            if !user.city.isEmpty {
                                Label(user.city, systemImage: "mappin.and.ellipse")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.78))
                            }
                        }

                        Spacer(minLength: 12)

                        Text(user.globalRole.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.white.opacity(0.16), in: Capsule())
                    }
                } else {
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.white.opacity(0.24))
                                .frame(width: 164, height: 18)
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.white.opacity(0.18))
                                .frame(width: 112, height: 12)
                        }
                        Spacer(minLength: 12)
                        Capsule()
                            .fill(.white.opacity(0.16))
                            .frame(width: 88, height: 32)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var feedContent: some View {
        if viewModel.isLoading && viewModel.feedItems.isEmpty {
            VStack(spacing: 0) {
                LoadingStateCard(title: nil)
            }
            .frame(maxWidth: .infinity, minHeight: 420)
        } else if viewModel.feedItems.isEmpty && viewModel.error != nil {
            VStack(alignment: .leading, spacing: 16) {
                feedSectionHeader
                ErrorStateCard(
                    title: AppStrings.Tabs.home,
                    message: homeErrorText,
                    retryTitle: AppStrings.News.retry
                ) {
                    viewModel.reload()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 420)
        } else if viewModel.feedItems.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                feedSectionHeader
                EmptyStateCard(
                    systemImage: "tray",
                    title: AppStrings.Tabs.home,
                    message: AppStrings.Common.noItems
                )
            }
            .frame(maxWidth: .infinity, minHeight: 420)
        } else {
            VStack(alignment: .leading, spacing: 18) {
                feedSectionHeader

                if viewModel.error != nil {
                    ErrorStateCard(
                        title: AppStrings.Tabs.home,
                        message: homeErrorText,
                        retryTitle: AppStrings.News.retry
                    ) {
                        viewModel.reload()
                    }
                }

                LazyVStack(spacing: 16) {
                    ForEach(viewModel.feedItems) { item in
                        NavigationLink {
                            destinationView(for: item)
                        } label: {
                            HomeFeedCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var feedSectionHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(AppStrings.Home.feedTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(AppStrings.Home.latestNews)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Text("\(viewModel.feedItems.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppTheme.badgeBlueFill, in: Capsule())
        }
    }

    private func loadContentIfNeeded() async {
        async let homeLoad: Void = viewModel.loadIfNeeded()
        async let newsLoad: Void = newsViewModel.loadIfNeeded()
        async let eventsLoad: Void = eventsViewModel.loadIfNeeded()
        async let organizationsLoad: Void = organizationsViewModel.loadIfNeeded()
        _ = await (homeLoad, newsLoad, eventsLoad, organizationsLoad)
    }

    private func refreshContentIfStale() async {
        async let homeRefresh: Void = viewModel.refreshIfStale()
        async let newsRefresh: Void = newsViewModel.refreshIfStale()
        async let eventsRefresh: Void = eventsViewModel.refreshIfStale()
        async let organizationsRefresh: Void = organizationsViewModel.refreshIfStale()
        _ = await (homeRefresh, newsRefresh, eventsRefresh, organizationsRefresh)
    }

    private func refreshAllContent() async {
        async let homeRefresh: Void = viewModel.refresh()
        async let newsRefresh: Void = newsViewModel.refresh()
        async let eventsRefresh: Void = eventsViewModel.refresh()
        async let organizationsRefresh: Void = organizationsViewModel.refresh()
        _ = await (homeRefresh, newsRefresh, eventsRefresh, organizationsRefresh)
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

private struct HomeFeedCard: View {
    let item: HomeFeedItem
    private let previewImageHeight: CGFloat = 184

    var body: some View {
        CommunityCard {
            if item.imageURL != nil {
                ZStack(alignment: .bottomLeading) {
                    RemoteCardImage(
                        imageURL: item.imageURL,
                        height: previewImageHeight,
                        source: "HomeFeedCard",
                        isDecorative: true
                    )

                    LinearGradient(
                        colors: [.black.opacity(0.02), .black.opacity(0.22)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous))

                    if item.itemType == .event, let eventMetadataText {
                        metadataCapsule(title: eventMetadataText, systemImage: "calendar")
                            .padding(14)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 10) {
                        metadataCapsule(title: itemTypeTitle, systemImage: itemTypeSystemImage)

                        Spacer(minLength: 12)

                        Text(publishedDateText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        metadataCapsule(title: itemTypeTitle, systemImage: itemTypeSystemImage)

                        Text(publishedDateText)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(sourceSubtitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .textCase(.uppercase)

                    Text(item.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(item.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                VStack(alignment: .leading, spacing: 10) {
                    if item.imageURL == nil, let eventMetadataText {
                        metadataLine(title: eventMetadataText, systemImage: "calendar")
                    }

                    if let regionMetadataText {
                        metadataLine(title: regionMetadataText, systemImage: "mappin.and.ellipse")
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 10) {
                        metadataLine(title: sourceTypeTitle, systemImage: sourceTypeSystemImage)

                        Spacer(minLength: 8)

                        HStack(spacing: 6) {
                            Image(systemName: "heart")
                                .font(.caption)
                            Text("\(item.likeCount)")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        metadataLine(title: sourceTypeTitle, systemImage: sourceTypeSystemImage)

                        HStack(spacing: 6) {
                            Image(systemName: "heart")
                                .font(.caption)
                            Text("\(item.likeCount)")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    }
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
        case .organization:
            AppStrings.Tabs.organizations
        }
    }

    private var itemTypeSystemImage: String {
        switch item.itemType {
        case .news:
            return "newspaper"
        case .event:
            return "calendar"
        case .organization:
            return "building.2"
        }
    }

    private var sourceSubtitle: String {
        if let organizationName = item.organizationName, !organizationName.isEmpty {
            return organizationName
        }
        return AppStrings.Common.app
    }

    private var sourceTypeTitle: String {
        switch item.sourceType {
        case .app:
            return AppStrings.Common.app
        case .organization:
            return AppStrings.Tabs.organizations
        }
    }

    private var sourceTypeSystemImage: String {
        switch item.sourceType {
        case .app:
            return "sparkles"
        case .organization:
            return "building.2"
        }
    }

    private var publishedDateText: String {
        LocalizationStore.dateString(from: item.publishedAt, dateStyle: .medium, timeStyle: .short)
    }

    private var eventMetadataText: String? {
        guard let eventStartDate = item.eventStartDate else { return nil }
        return LocalizationStore.dateString(from: eventStartDate, dateStyle: .medium, timeStyle: .short)
    }

    private var regionMetadataText: String? {
        if let city = item.city, !city.isEmpty {
            if let venue = item.eventVenue, !venue.isEmpty {
                return "\(city) • \(venue)"
            }
            return city
        }
        return nil
    }

    private var accessibilitySummary: String {
        var parts = [itemTypeTitle, item.title]

        if !item.summary.isEmpty {
            parts.append(item.summary)
        }

        if let eventMetadataText {
            parts.append(eventMetadataText)
        }

        if let regionMetadataText {
            parts.append(regionMetadataText)
        }

        parts.append("\(item.likeCount) \(AppStrings.Common.likes)")
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private func metadataLine(title: String, systemImage: String) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)

            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func metadataCapsule(title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.semibold))
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(itemTypeCapsuleForeground)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(itemTypeCapsuleBackground, in: Capsule())
    }

    private var itemTypeCapsuleForeground: Color {
        switch item.itemType {
        case .news:
            return AppTheme.accentPrimary
        case .event:
            return AppTheme.accentPrimary
        case .organization:
            return .secondary
        }
    }

    private var itemTypeCapsuleBackground: Color {
        switch item.itemType {
        case .news:
            return AppTheme.badgeBlueFill
        case .event:
            return AppTheme.accentSupport.opacity(0.16)
        case .organization:
            return Color.secondary.opacity(0.12)
        }
    }
}

#Preview {
    NavigationStack {
        HomeView(
            viewModel: HomeViewModel(
                newsRepository: MockNewsRepository(),
                eventRepository: MockEventRepository(),
                organizationRepository: MockOrganizationRepository()
            ),
            newsViewModel: NewsViewModel(repository: MockNewsRepository()),
            eventsViewModel: EventsViewModel(repository: MockEventRepository()),
            organizationsViewModel: OrganizationsViewModel(repository: MockOrganizationRepository())
        )
    }
    .environmentObject(AuthState())
}
