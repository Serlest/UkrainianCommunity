import Combine
import MapKit
import SwiftUI

struct OrganizationNavigationRoute: Hashable {
    let organizationID: String
}

private let organizationsRootScrollTopID = "organizationsRootScrollTop"

struct OrganizationCategoryFilter: Identifiable, Equatable {
    let category: OrganizationEditorCategory?

    var id: String { category?.rawValue ?? "all" }

    static let all = OrganizationCategoryFilter(category: nil)
    static var allCases: [OrganizationCategoryFilter] {
        [.all] + OrganizationEditorCategory.allCases.map(OrganizationCategoryFilter.init(category:))
    }
    static var selectableCases: [OrganizationCategoryFilter] {
        OrganizationEditorCategory.allCases.map(OrganizationCategoryFilter.init(category:))
    }

    var title: String { category?.title ?? AppStrings.Home.filterAll }
    var systemImage: String? { category?.systemImage ?? "square.grid.2x2" }

    func matches(_ organization: Organization) -> Bool {
        guard !organization.isSystemOrganization else { return category == nil }
        guard let category else { return true }
        return organization.organizationType == category.rawValue
            || organization.directoryProfile?.secondaryCategories.contains(category.rawValue) == true
    }
}

private enum OrganizationSavedFilterMode {
    case none
    case subscribed
    case bookmarked
}

struct OrganizationsListView: View {
    @EnvironmentObject private var authState: AuthState
    @ObservedObject var viewModel: OrganizationsViewModel
    @StateObject var newsViewModel: NewsViewModel
    @StateObject var eventsViewModel: EventsViewModel
    @StateObject private var featuredBannerViewModel: FeaturedBannerListViewModel
    @Binding var navigationPath: [OrganizationNavigationRoute]
    let onOrganizationSaved: @MainActor () async -> Void
    let onOrganizationDeleted: @MainActor () -> Void
    let presentationMode: OrganizationPresentationMode
    let onFeaturedBannerTap: (FeaturedBanner) -> Void
    let scrollResetToken: Int
    let searchResetToken: Int
    @State private var pendingDeleteOrganizationID: String?
    @State private var deleteErrorMessage: String?
    @State private var isShowingDeleteError = false
    @State private var selectedCategory: OrganizationCategoryFilter = .all
    @State private var selectedFederalState: AustrianFederalState?
    @State private var savedFilterMode: OrganizationSavedFilterMode = .none
    @State private var didManuallyChangeRegion = false
    @State private var isRegionPickerPresented = false
    @State private var isSearchPresented = false
    @State private var searchText = ""
    @State private var isLoadingSearchPages = false
    @State private var isShowingCreateOrganization = false

    init(
        viewModel: OrganizationsViewModel,
        newsViewModel: NewsViewModel? = nil,
        eventsViewModel: EventsViewModel? = nil,
        newsRepository: NewsRepository = FirestoreNewsRepository(),
        eventRepository: EventRepository = FirestoreEventRepository(),
        featuredBannerRepository: FeaturedBannerRepository = FirestoreFeaturedBannerRepository(),
        featuredBannerCache: FeaturedBannerCache = FeaturedBannerCache(),
        navigationPath: Binding<[OrganizationNavigationRoute]> = .constant([]),
        onOrganizationSaved: @escaping @MainActor () async -> Void = {},
        onOrganizationDeleted: @escaping @MainActor () -> Void = {},
        presentationMode: OrganizationPresentationMode = .public,
        onFeaturedBannerTap: @escaping (FeaturedBanner) -> Void = { _ in },
        scrollResetToken: Int = 0,
        searchResetToken: Int = 0
    ) {
        self.viewModel = viewModel
        _newsViewModel = StateObject(wrappedValue: newsViewModel ?? NewsViewModel(repository: newsRepository))
        _eventsViewModel = StateObject(wrappedValue: eventsViewModel ?? EventsViewModel(repository: eventRepository))
        self.onOrganizationSaved = onOrganizationSaved
        self.onOrganizationDeleted = onOrganizationDeleted
        self.presentationMode = presentationMode
        self.onFeaturedBannerTap = onFeaturedBannerTap
        self.scrollResetToken = scrollResetToken
        self.searchResetToken = searchResetToken
        _featuredBannerViewModel = StateObject(wrappedValue: FeaturedBannerListViewModel(
            repository: featuredBannerRepository,
            cache: featuredBannerCache
        ))
        _navigationPath = navigationPath
    }

    private var featuredBannerLoadKey: String {
        selectedFederalState?.rawValue ?? "allAustria"
    }

    private var errorText: String {
        switch viewModel.error {
        case .network:
            AppStrings.Organizations.loadNetworkError
        case .permissionDenied:
            AppStrings.Organizations.loadPermissionError
        case .validationFailed:
            AppStrings.Organizations.loadValidationError
        case .notFound:
            AppStrings.Organizations.empty
        case .unknown:
            AppStrings.Organizations.loadUnknownError
        case nil:
            ""
        }
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.vertical, showsIndicators: false) {
                Color.clear
                    .frame(height: 0)
                    .id(organizationsRootScrollTopID)

                VStack(alignment: .leading, spacing: 0) {
                    organizationsHeader
                        .padding(.bottom, AppTheme.homeHeaderHeroSpacing)

                    organizationsHero
                        .padding(
                            .bottom,
                            featuredBannerViewModel.banners.isEmpty && featuredBannerViewModel.error == nil
                                ? 0
                                : AppTheme.homeSectionSpacing
                        )

                    OrganizationFiltersSection(
                        selectedCategory: selectedCategory,
                        selectedFederalState: selectedFederalState,
                        savedFilterMode: savedFilterMode,
                        onSelectCategory: { selectedCategory = $0 },
                        onSelectRegion: { isRegionPickerPresented = true },
                        onToggleSubscribed: { toggleSavedFilterMode(.subscribed) },
                        onToggleBookmarked: { toggleSavedFilterMode(.bookmarked) }
                    )
                    .padding(.bottom, AppTheme.homeSectionSpacing)

                    AppGroupedContentPlane {
                        organizationsPlaneContent
                    }
                }
                .padding(.horizontal, AppTheme.pageHorizontal)
                .padding(.bottom, AppTheme.homeBottomContentPadding)
                .appCenteredContent(maxWidth: AppTheme.feedContentMaxWidth)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: scrollResetToken) {
                scrollToTop(with: scrollProxy)
            }
        }
        .background(AppBackgroundView())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: OrganizationNavigationRoute.self) { route in
            OrganizationDetailView(
                viewModel: viewModel,
                organizationID: route.organizationID,
                newsViewModel: newsViewModel,
                eventsViewModel: eventsViewModel,
                onOrganizationSaved: onOrganizationSaved,
                onOrganizationDeleted: onOrganizationDeleted
            )
            .environment(\.organizationPresentationMode, presentationMode)
        }
        .task(id: featuredBannerLoadKey) {
            applyDefaultRegion()
            await viewModel.loadIfNeeded()
            await viewModel.refreshIfStale()
            await refreshFeaturedBannersIfStale()
        }
        .task(id: searchText) {
            let queryKey = LocalSearchMatcher.normalized(searchText)
            isLoadingSearchPages = false
            guard !queryKey.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            isLoadingSearchPages = true
            defer {
                if LocalSearchMatcher.normalized(searchText) == queryKey {
                    isLoadingSearchPages = false
                }
            }
            await viewModel.loadRemainingPagesForSearch()
        }
        .appRefreshable {
            async let content: Void = viewModel.refresh()
            async let banners: Void = refreshFeaturedBanners()
            _ = await (content, banners)
        }
        .onChange(of: authState.user?.selectedFederalState) { _, newRegion in
            guard !didManuallyChangeRegion else { return }
            selectedFederalState = newRegion
        }
        .onReceive(NotificationCenter.default.publisher(for: .organizationsChanged).debounce(for: .milliseconds(250), scheduler: RunLoop.main)) { _ in
            Task {
                await viewModel.refresh()
            }
        }
        .appErrorDialog(Binding(
            get: {
                viewModel.interactionError.map {
                    AppErrorDialog(message: readableOrganizationErrorText($0))
                }
            },
            set: { if $0 == nil { viewModel.dismissInteractionError() } }
        ))
        .confirmationDialog(AppStrings.Home.regionAllAustria, isPresented: $isRegionPickerPresented, titleVisibility: .visible) {
            Button(AppStrings.Home.regionAllAustria) {
                selectRegion(nil)
            }

            ForEach(AustrianFederalState.organizationFilterOrder, id: \.self) { federalState in
                Button(federalState.displayName) {
                    selectRegion(federalState)
                }
            }

            Button(AppStrings.Events.cancel, role: .cancel) {}
        }
        .appDestructiveActionDialog(Binding(
            get: {
                guard let organizationID = pendingDeleteOrganizationID else { return nil }
                return AppDestructiveActionDialog(
                    title: AppStrings.Organizations.deleteConfirmation,
                    message: "",
                    destructiveActionTitle: AppStrings.Organizations.delete,
                    cancelTitle: AppStrings.Organizations.cancel
                ) {
                    Task {
                        do {
                            try await viewModel.deleteOrganization(id: organizationID, user: authState.user)
                            viewModel.removeDeletedOrganization(id: organizationID)
                            onOrganizationDeleted()
                        } catch let appError as AppError {
                            deleteErrorMessage = readableOrganizationErrorText(appError)
                            isShowingDeleteError = true
                        } catch {
                            deleteErrorMessage = readableOrganizationErrorText(.unknown)
                            isShowingDeleteError = true
                        }
                        pendingDeleteOrganizationID = nil
                    }
                }
            },
            set: { if $0 == nil { pendingDeleteOrganizationID = nil } }
        ))
        .appErrorDialog(Binding(
            get: {
                guard isShowingDeleteError else { return nil }
                return AppErrorDialog(
                    title: AppStrings.Organizations.deleteFailed,
                    message: deleteErrorMessage ?? readableOrganizationErrorText(.unknown),
                    okTitle: AppStrings.Organizations.dismissError
                )
            },
            set: {
                if $0 == nil {
                    isShowingDeleteError = false
                    deleteErrorMessage = nil
                }
            }
        ))
        .observesKeyboardDismissTaps()
        .sheet(isPresented: $isShowingCreateOrganization) {
            NavigationStack {
                OrganizationEditorView(
                    organizationsViewModel: viewModel,
                    onSaved: {
                        await viewModel.refresh()
                        await onOrganizationSaved()
                    }
                )
            }
            .environmentObject(authState)
        }
    }

    private func scrollToTop(with scrollProxy: ScrollViewProxy) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            scrollProxy.scrollTo(organizationsRootScrollTopID, anchor: .top)
        }
    }

    private var organizationsHeader: some View {
        AppSearchableBrandHeader(
            isSearchPresented: $isSearchPresented,
            searchText: $searchText,
            placeholder: AppStrings.Search.organizationsPlaceholder,
            collapseToken: searchResetToken,
            additionalCreateAction: PermissionService.canCreateOrganization(user: authState.user)
                ? { isShowingCreateOrganization = true } : nil,
            additionalCreateTitle: AppStrings.Organizations.addOrganization,
            additionalCreateIdentifier: "organizations.add"
        )
    }

    @ViewBuilder
    private var organizationsHero: some View {
        if !featuredBannerViewModel.banners.isEmpty {
            FeaturedBannerCarouselView(
                banners: featuredBannerViewModel.banners,
                sizing: .responsiveHero,
                onBannerTap: onFeaturedBannerTap
            )
        } else if let error = featuredBannerViewModel.error {
            FeaturedBannerLoadFailureView(error: error) {
                await refreshFeaturedBanners()
            }
        }
    }

    private func refreshFeaturedBannersIfStale() async {
        await featuredBannerViewModel.refreshIfStale(
            for: .organizations,
            federalState: selectedFederalState
        )
    }

    private func refreshFeaturedBanners() async {
        await featuredBannerViewModel.refresh(
            for: .organizations,
            federalState: selectedFederalState
        )
    }

    @ViewBuilder
    private var organizationsPlaneContent: some View {
        if viewModel.organizations.isEmpty && viewModel.isLoading {
            LoadingStateCard(title: nil)
                .frame(maxWidth: .infinity, minHeight: 180)
        } else if viewModel.organizations.isEmpty && viewModel.error != nil {
            ErrorStateCard(
                systemImage: "building.2",
                title: AppStrings.Organizations.title,
                message: errorText,
                retryTitle: AppStrings.Organizations.retry
            ) {
                Task {
                    await viewModel.refresh()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 180)
        } else if viewModel.organizations.isEmpty {
            EmptyStateCard(
                systemImage: "building.2",
                title: AppStrings.Organizations.title,
                message: AppStrings.Organizations.empty
            )
            .frame(maxWidth: .infinity, minHeight: 180)
        } else if filteredOrganizations.isEmpty, isLoadingSearchPages {
            LoadingStateCard(title: AppStrings.Search.searching)
                .frame(maxWidth: .infinity, minHeight: 180)
        } else if filteredOrganizations.isEmpty {
            EmptyStateCard(
                systemImage: hasActiveSearch ? "magnifyingglass" : "line.3.horizontal.decrease.circle",
                title: hasActiveSearch ? AppStrings.Search.noResultsTitle : AppStrings.Organizations.title,
                message: filteredEmptyMessage
            )
            .frame(maxWidth: .infinity, minHeight: 180)
        } else {
            VStack(alignment: .leading, spacing: AppTheme.feedRowSpacing) {
                if viewModel.error != nil {
                    ErrorStateCard(
                        title: AppStrings.Organizations.title,
                        message: errorText,
                        retryTitle: AppStrings.Organizations.retry
                    ) {
                        Task {
                            await viewModel.refresh()
                        }
                    }
                }

                DashboardSectionHeader(title: AppStrings.Organizations.title)

                DashboardFeedContainer(
                    items: filteredOrganizations,
                    spacing: AppTheme.feedRowSpacing,
                    onItemAppear: { organization in
                        Task {
                            await viewModel.loadNextPageIfNeeded(currentItemID: organization.id)
                        }
                    }
                ) { organization in
                    organizationLink(for: organization)
                }
            }
        }
    }

    private var filteredOrganizations: [Organization] {
        viewModel.organizations.filter { organization in
            selectedCategory.matches(organization)
                && matchesSelectedRegion(organization)
                && matchesSavedFilterMode(organization)
                && matchesSearch(organization)
        }
    }

    private var hasActiveSearch: Bool {
        LocalSearchMatcher.hasQuery(searchText)
    }

    private var filteredEmptyMessage: String {
        if hasActiveSearch {
            return AppStrings.Search.noResultsMessage
        }

        if savedFilterMode == .bookmarked {
            return AppStrings.Organizations.emptyBookmarked
        }
        if savedFilterMode == .subscribed {
            return AppStrings.Home.emptySubscribed
        }
        return AppStrings.Organizations.empty
    }

    private func matchesSelectedRegion(_ organization: Organization) -> Bool {
        RegionVisibilityMatcher.isVisible(
            regionScope: organization.regionScope,
            federalState: organization.federalState,
            selectedFederalState: selectedFederalState
        )
    }

    private func matchesSavedFilterMode(_ organization: Organization) -> Bool {
        switch savedFilterMode {
        case .none:
            return true
        case .subscribed:
            guard authState.isAuthenticated else { return false }
            return organization.isSubscribed
        case .bookmarked:
            guard authState.isAuthenticated else { return false }
            return organization.isBookmarked
        }
    }

    private func matchesSearch(_ organization: Organization) -> Bool {
        LocalSearchMatcher.matches(
            query: searchText,
            values: [
                organization.localizedName,
                organization.localizedShortDescription,
                organization.description,
                organization.localizedFullDescription,
                organization.city,
                organization.organizationType,
                selectedCategoryTitle(for: organization.organizationType),
                organization.contactPerson,
                organization.localizedMissionStatement,
                organization.localizedDirectoryProfile?.serviceArea,
                organization.localizedDirectoryProfile?.services.joined(separator: " "),
                organization.localizedDirectoryProfile?.currentOfferTitle
            ]
        )
    }

    private func selectedCategoryTitle(for organizationType: String?) -> String? {
        guard let organizationType else { return nil }
        return OrganizationEditorCategory(rawValue: organizationType)?.title
    }

    private func toggleSavedFilterMode(_ mode: OrganizationSavedFilterMode) {
        savedFilterMode = savedFilterMode == mode ? .none : mode
    }

    private func selectRegion(_ federalState: AustrianFederalState?) {
        selectedFederalState = federalState
        didManuallyChangeRegion = true
    }

    private func applyDefaultRegion() {
        guard !didManuallyChangeRegion else { return }
        selectedFederalState = authState.user?.selectedFederalState
    }

    private func organizationLink(for organization: Organization) -> some View {
        NavigationLink(value: OrganizationNavigationRoute(organizationID: organization.id)) {
            OrganizationCard(organization: organization)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("organization.card.\(organization.id)")
        .modifier(OrganizationDeleteSwipeActions(
            isEnabled: presentationMode.allowsManagementControls
                && !organization.isSystemOrganization
                && PermissionService.canDeleteOrganization(user: authState.user),
            onDelete: {
                pendingDeleteOrganizationID = organization.id
            }
        ))
    }
}

func readableOrganizationErrorText(_ error: AppError?) -> String {
    switch error {
    case .network:
        AppStrings.Organizations.loadNetworkError
    case .permissionDenied:
        AppStrings.Organizations.actionPermissionError
    case .validationFailed:
        AppStrings.Organizations.actionValidationError
    case .notFound:
        AppStrings.Organizations.actionNotFoundError
    case .unknown:
        AppStrings.Organizations.actionUnknownError
    case nil:
        AppStrings.Organizations.actionUnknownError
    }
}

private struct OrganizationCard: View {
    let organization: Organization
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        SoftContentCard(padding: AppTheme.compactCardInnerSpacing) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppTheme.compactCardInnerSpacing) {
                    organizationThumbnail
                    organizationDetails
                }
            } else {
                HStack(alignment: .center, spacing: AppTheme.compactCardInnerSpacing) {
                    organizationThumbnail
                    organizationDetails
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var organizationThumbnail: some View {
        AppFeedThumbnail(
            imageURL: organization.imageURL,
            fallbackSystemImage: "building.2",
            tint: AppTheme.accentPrimaryForeground,
            fill: AppTheme.badgeBlueFill,
            size: thumbnailSize,
            cornerRadius: AppTheme.feedThumbnailRadius,
            source: "OrganizationCard"
        )
        .frame(width: thumbnailSize, height: thumbnailSize, alignment: .center)
    }

    private var organizationDetails: some View {
        VStack(alignment: .leading, spacing: AppTheme.compactCardInnerSpacingDense) {
            Text(organization.localizedName)
                .font(AppTheme.cardTitleFont)
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)

            Text(organization.localizedShortDescription)
                .font(AppTheme.cardSubtitleFont)
                .foregroundStyle(AppTheme.textSecondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)

            organizationMetadataChips
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var thumbnailSize: CGFloat {
        AppTheme.organizationsThumbnailSize
    }

    private var organizationMetadataChips: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppTheme.compactCardInnerSpacingTight) {
                metadataChips
            }

            VStack(alignment: .leading, spacing: AppTheme.compactCardInnerSpacingTight) {
                metadataChips
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var metadataChips: some View {
        ForEach(Array(metadataItems.enumerated()), id: \.offset) { _, item in
            AppInfoChip(
                title: item.title,
                systemImage: item.systemImage,
                tint: AppTheme.textSecondary,
                fill: AppTheme.surfaceControl.opacity(0.62),
                size: .small
            )
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var metadataItems: [(title: String, systemImage: String)] {
        var items: [(title: String, systemImage: String)] = []

        if let region = regionText {
            items.append((region, "mappin.and.ellipse"))
        }

        items.append((organizationCategoryText, organization.directoryProfile?.profileKind.systemImage ?? "building.2"))
        return items
    }

    private var accessibilitySummary: String {
        [
            organization.localizedName,
            organization.localizedShortDescription,
            regionText ?? organization.city,
            organizationCategoryText
        ]
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
    }

    private var regionText: String? {
        if let federalState = organization.federalState {
            return AppStrings.FederalStates.title(for: federalState)
        }

        let city = organization.city.trimmingCharacters(in: .whitespacesAndNewlines)
        return city.isEmpty ? nil : city
    }

    private var organizationCategoryText: String {
        guard let organizationType = organization.organizationType,
              let category = OrganizationEditorCategory(rawValue: organizationType) else {
            return AppStrings.Organizations.detailBadge
        }

        return category.title
    }

}

private struct OrganizationFiltersSection: View {
    let selectedCategory: OrganizationCategoryFilter
    let selectedFederalState: AustrianFederalState?
    let savedFilterMode: OrganizationSavedFilterMode
    let onSelectCategory: (OrganizationCategoryFilter) -> Void
    let onSelectRegion: () -> Void
    let onToggleSubscribed: () -> Void
    let onToggleBookmarked: () -> Void

    private enum Filter: String {
        case category, region, subscribed, bookmarked
    }

    var body: some View {
        AppPrioritizedFilterRow(
            pinned: [.category, .region],
            filters: [.subscribed, .bookmarked],
            isActive: isActive
        ) { filter in
            filterControl(filter)
                .accessibilityIdentifier("organizations.filter.\(filter.rawValue)")
        }
        .accessibilityIdentifier("organizations.filters")
    }

    private func isActive(_ filter: Filter) -> Bool {
        switch filter {
        case .category: selectedCategory != .all
        case .region: selectedFederalState != nil
        case .subscribed: savedFilterMode == .subscribed
        case .bookmarked: savedFilterMode == .bookmarked
        }
    }

    @ViewBuilder
    private func filterControl(_ filter: Filter) -> some View {
        switch filter {
        case .category:
            Menu {
                ForEach(OrganizationCategoryFilter.allCases) { category in
                    Button {
                        onSelectCategory(category)
                    } label: {
                        Label(category.title, systemImage: category.systemImage ?? "tag")
                    }
                }
            } label: {
                AppFilterChip(
                    title: selectedCategory.title,
                    systemImage: selectedCategory.systemImage,
                    isSelected: selectedCategory != .all,
                    trailingSystemImage: "chevron.down"
                )
            }
            .buttonStyle(.plain)
        case .region:
            Button(action: onSelectRegion) {
                AppFilterChip(
                    title: selectedFederalState?.displayName ?? AppStrings.Home.regionAllAustria,
                    systemImage: "mappin.and.ellipse",
                    isSelected: selectedFederalState != nil,
                    trailingSystemImage: "chevron.down"
                )
            }
            .buttonStyle(.plain)
        case .subscribed:
            Button(action: onToggleSubscribed) {
                AppFilterChip(
                    title: AppStrings.Home.filterSubscribed,
                    systemImage: "person.2.fill",
                    isSelected: savedFilterMode == .subscribed
                )
            }
            .buttonStyle(.plain)
        case .bookmarked:
            Button(action: onToggleBookmarked) {
                AppFilterChip(
                    title: AppStrings.Organizations.filterBookmarks,
                    systemImage: "bookmark",
                    isSelected: savedFilterMode == .bookmarked
                )
            }
            .buttonStyle(.plain)
        }
    }
}

private extension AustrianFederalState {
    static var organizationFilterOrder: [AustrianFederalState] {
        [
            .tirol,
            .wien,
            .niederoesterreich,
            .oberoesterreich,
            .salzburg,
            .steiermark,
            .kaernten,
            .vorarlberg,
            .burgenland
        ]
    }

}

private struct OrganizationDeleteSwipeActions: ViewModifier {
    let isEnabled: Bool
    let onDelete: () -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.swipeActions(edge: .trailing) {
                Button(AppStrings.Organizations.delete, role: .destructive) {
                    onDelete()
                }
            }
        } else {
            content
        }
    }
}
