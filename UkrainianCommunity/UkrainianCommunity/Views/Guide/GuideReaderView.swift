import SwiftUI

private let guideRootScrollTopID = "guideRootScrollTop"

struct GuideReaderView: View {
    @EnvironmentObject private var authState: AuthState
    @ObservedObject private var viewModel: GuideReaderViewModel
    @StateObject private var featuredBannerViewModel: FeaturedBannerListViewModel
    @State private var isSearchPresented = false
    @State private var searchPlaceholderText = ""
    @State private var searchResults = GuideSearchResults.empty
    @State private var isSearchLoading = false
    @State private var searchError: AppError?
    @State private var searchDebounceTask: Task<Void, Never>?
    @State private var isSavedFilterSelected = false
    @State private var guestAccessAction: GuestAccessAction?
    @State private var saveError: AppError?
    @State private var presentedBannerCategory: GuideCategory?
    @State private var presentedGuideNodeRoute: GuideNodeNavigationRoute?
    @State private var presentedGuideMaterialRoute: GuideMaterialNavigationRoute?
    @State private var guideMaterialRouteError: AppError?
    @Binding private var guideBannerCategoryTarget: GuideCategory?
    @Binding private var guideMaterialTargetID: String?
    private let feedbackRepository: FeedbackRepository
    private let onFeaturedBannerTap: (FeaturedBanner) -> Void
    private let navigationResetToken: Int
    private let scrollResetToken: Int

    private let categoryColumns = [
        GridItem(.flexible(), spacing: AppTheme.dashboardSpacing),
        GridItem(.flexible(), spacing: AppTheme.dashboardSpacing)
    ]

    init(
        viewModel: GuideReaderViewModel,
        featuredBannerRepository: FeaturedBannerRepository = FirestoreFeaturedBannerRepository(),
        featuredBannerCache: FeaturedBannerCache = FeaturedBannerCache(),
        feedbackRepository: FeedbackRepository = FirestoreFeedbackRepository(),
        onFeaturedBannerTap: @escaping (FeaturedBanner) -> Void = { _ in },
        guideBannerCategoryTarget: Binding<GuideCategory?> = .constant(nil),
        guideMaterialTargetID: Binding<String?> = .constant(nil),
        navigationResetToken: Int = 0,
        scrollResetToken: Int = 0
    ) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
        _featuredBannerViewModel = StateObject(
            wrappedValue: FeaturedBannerListViewModel(
                repository: featuredBannerRepository,
                cache: featuredBannerCache
            )
        )
        _guideBannerCategoryTarget = guideBannerCategoryTarget
        _guideMaterialTargetID = guideMaterialTargetID
        self.feedbackRepository = feedbackRepository
        self.onFeaturedBannerTap = onFeaturedBannerTap
        self.navigationResetToken = navigationResetToken
        self.scrollResetToken = scrollResetToken
    }

    var body: some View {
        guideScrollContent
        .background(AppBackgroundView().allowsHitTesting(false))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: featuredBannerLoadKey) {
            await viewModel.syncProfileFederalState(authState.user?.selectedFederalState)
            await refreshFeaturedBannersIfStale()
        }
        .onAppear {
            if authState.isAuthenticated {
                Task {
                    await viewModel.loadSavedMaterialsIfNeeded()
                }
            }
            if let materialID = guideMaterialTargetID {
                handleGuideMaterialTarget(materialID)
            }
        }
        .onChange(of: authState.user?.id) { _, newValue in
            viewModel.resetSavedMaterialsState()
            if newValue == nil {
                isSavedFilterSelected = false
            } else if isSavedFilterSelected {
                Task {
                    await viewModel.refreshSavedMaterials()
                }
            }
        }
        .onChange(of: authState.user?.selectedFederalState) { _, newValue in
            Task {
                await viewModel.syncProfileFederalState(newValue)
            }
        }
        .onChange(of: featuredBannerLoadKey) { _, _ in
            triggerSearchDebounce()
        }
        .onChange(of: guideBannerCategoryTarget) { _, newValue in
            guard let category = newValue else { return }
            handleGuideBannerCategoryTarget(category)
        }
        .onChange(of: guideMaterialTargetID) { _, newValue in
            guard let materialID = newValue else { return }
            handleGuideMaterialTarget(materialID)
        }
        .onChange(of: navigationResetToken) { _, _ in
            resetNavigationState()
        }
        .onChange(of: searchPlaceholderText) { _, _ in
            triggerSearchDebounce()
        }
        .refreshable {
            await refreshFeaturedBanners()
            if isSavedFilterSelected && authState.isAuthenticated {
                await viewModel.refreshSavedMaterials()
            }
        }
        .guestAccessAlert($guestAccessAction)
        .observesKeyboardDismissTaps()
        .appErrorDialog(Binding(
            get: {
                if let guideMaterialRouteError {
                    return AppErrorDialog(
                        title: AppStrings.NotificationInbox.destinationUnavailableTitle,
                        message: guideMaterialRouteErrorMessage(guideMaterialRouteError)
                    )
                }
                guard let saveError else { return nil }
                return AppErrorDialog(
                    title: GuideCategoryPresentation.saveActionFailedTitle,
                    message: GuideCategoryPresentation.saveActionErrorMessage(for: saveError)
                )
            },
            set: {
                if $0 == nil {
                    saveError = nil
                    guideMaterialRouteError = nil
                }
            }
        ))
        .navigationDestination(item: $presentedBannerCategory) { category in
            GuideCategoryDetailView(
                category: category,
                viewModel: viewModel.makeChildViewModel()
            )
        }
        .navigationDestination(item: $presentedGuideNodeRoute) { route in
            GuideSectionDetailView(
                node: route.node,
                viewModel: viewModel.makeChildViewModel(),
                feedbackRepository: feedbackRepository
            )
        }
        .navigationDestination(item: $presentedGuideMaterialRoute) { route in
            GuideMaterialDetailView(
                material: route.material,
                viewModel: viewModel,
                feedbackRepository: feedbackRepository
            )
        }
    }

    private var guideScrollContent: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.vertical, showsIndicators: false) {
                Color.clear
                    .frame(height: 0)
                    .id(guideRootScrollTopID)

                guideRootContent
                    .padding(.horizontal, AppTheme.pageHorizontal)
                    .padding(.bottom, AppTheme.homeBottomContentPadding)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: scrollResetToken) {
                withAnimation(.easeInOut(duration: 0.22)) {
                    scrollProxy.scrollTo(guideRootScrollTopID, anchor: .top)
                }
            }
        }
    }

    private var guideRootContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            guideHeader
                .padding(.bottom, AppTheme.homeHeaderHeroSpacing)

            featuredGuideCarousel

            placeholderFilterRow

            AppGroupedContentPlane(padding: AppTheme.homeFeedPlanePadding) {
                if isSearchActive {
                    searchResultsContent
                } else if isSavedFilterSelected {
                    savedMaterialsContent
                } else {
                    defaultRootContent
                }
            }
        }
    }

    private var featuredBannerLoadKey: String {
        viewModel.selectedFederalState?.rawValue ?? "allRegions"
    }

    private var selectedRegionTitle: String {
        viewModel.selectedFederalState.map(regionTitle(for:)) ?? GuideCategoryPresentation.allRegionsTitle
    }

    private var isSearchActive: Bool {
        !searchPlaceholderText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var guideHeader: some View {
        AppSearchableBrandHeader(
            isSearchPresented: $isSearchPresented,
            searchText: $searchPlaceholderText,
            placeholder: AppStrings.Search.guidePlaceholder,
            collapseToken: scrollResetToken
        )
    }

    private var placeholderFilterRow: some View {
        AppHorizontalFilterRow {
            Menu {
                Button(GuideCategoryPresentation.allRegionsTitle) {
                    Task {
                        await viewModel.selectFederalState(nil)
                    }
                }

                Divider()

                ForEach(AustrianFederalState.allCases) { federalState in
                    Button(regionTitle(for: federalState)) {
                        Task {
                            await viewModel.selectFederalState(federalState)
                        }
                    }
                }
            } label: {
                AppFilterChip(
                    title: selectedRegionTitle,
                    systemImage: "mappin.and.ellipse",
                    isSelected: viewModel.selectedFederalState != nil,
                    trailingSystemImage: "chevron.down"
                )
            }
            .buttonStyle(.plain)

            Button {
                toggleSavedFilter()
            } label: {
                AppFilterChip(
                    title: GuideCategoryPresentation.savedPlaceholderTitle,
                    systemImage: "bookmark",
                    isSelected: isSavedFilterSelected
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, AppTheme.homeSectionSpacing)
    }

    private var defaultRootContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.feedRowSpacing + 2) {
            SectionHeaderBlock(
                title: GuideCategoryPresentation.categoriesSectionTitle,
                subtitle: GuideCategoryPresentation.categoriesSectionSubtitle
            )

            LazyVGrid(columns: categoryColumns, alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                ForEach(GuideCategoryPresentation.publicTopLevelCategories) { category in
                    Button {
                        presentedBannerCategory = category
                    } label: {
                        GuideCategoryLinkCard(
                            title: GuideCategoryPresentation.publicTitle(for: category),
                            systemImage: category.systemImage
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var searchResultsContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
            SectionHeaderBlock(
                title: GuideCategoryPresentation.searchResultsTitle,
                subtitle: GuideCategoryPresentation.searchResultsSubtitle
            )

            if isSearchLoading {
                GuideLoadingView()
            } else if let searchError {
                GuideErrorStateView(error: searchError) {
                    triggerSearchDebounce()
                }
            } else if searchResults.isEmpty {
                EmptyStateCard(
                    systemImage: "magnifyingglass",
                    title: GuideCategoryPresentation.searchEmptyTitle,
                    message: GuideCategoryPresentation.searchEmptyMessage
                )
            } else {
                if !searchResults.categories.isEmpty {
                    VStack(alignment: .leading, spacing: AppTheme.feedRowSpacing) {
                        SectionHeaderBlock(title: GuideCategoryPresentation.searchCategoriesTitle)

                        LazyVGrid(columns: categoryColumns, alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                            ForEach(searchResults.categories) { category in
                                Button {
                                    presentedBannerCategory = category
                                } label: {
                                    GuideCategoryLinkCard(
                                        title: GuideCategoryPresentation.publicTitle(for: category),
                                        systemImage: category.systemImage
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if !searchResults.nodes.isEmpty {
                    VStack(alignment: .leading, spacing: AppTheme.feedRowSpacing) {
                        SectionHeaderBlock(title: GuideCategoryPresentation.searchNodesTitle)

                        ForEach(searchResults.nodes) { node in
                            Button {
                                presentedGuideNodeRoute = GuideNodeNavigationRoute(node: node)
                            } label: {
                                GuideSectionCard(node: node)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !searchResults.materials.isEmpty {
                    VStack(alignment: .leading, spacing: AppTheme.feedRowSpacing) {
                        SectionHeaderBlock(title: GuideCategoryPresentation.searchMaterialsTitle)

                        ForEach(searchResults.materials) { material in
                            GuideMaterialResultRow(
                                material: material,
                                isSaved: viewModel.isMaterialSaved(material.id),
                                isSavePending: viewModel.isMaterialSavePending(material.id),
                                openMaterial: {
                                    presentedGuideMaterialRoute = GuideMaterialNavigationRoute(material: material)
                                },
                                onToggleSaved: {
                                    handleSavedToggle(for: material)
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var savedMaterialsContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
            SectionHeaderBlock(
                title: GuideCategoryPresentation.savedMaterialsTitle,
                subtitle: GuideCategoryPresentation.savedMaterialsSubtitle
            )

            if viewModel.isLoadingSavedMaterials {
                GuideLoadingView()
            } else if viewModel.savedMaterials.isEmpty {
                EmptyStateCard(
                    systemImage: "bookmark",
                    title: GuideCategoryPresentation.savedMaterialsEmptyTitle,
                    message: GuideCategoryPresentation.savedMaterialsEmptyMessage
                )
            } else {
                ForEach(viewModel.savedMaterials) { material in
                    GuideMaterialResultRow(
                        material: material,
                        isSaved: true,
                        isSavePending: viewModel.isMaterialSavePending(material.id),
                        openMaterial: {
                            presentedGuideMaterialRoute = GuideMaterialNavigationRoute(material: material)
                        },
                        onToggleSaved: {
                            handleSavedToggle(for: material)
                        }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var featuredGuideCarousel: some View {
        if !featuredBannerViewModel.banners.isEmpty {
            FeaturedBannerCarouselView(
                banners: featuredBannerViewModel.banners,
                sizing: .responsiveHero,
                onBannerTap: onFeaturedBannerTap
            )
            .padding(.bottom, AppTheme.homeSectionSpacing)
        }
    }

    private func refreshFeaturedBannersIfStale() async {
        await featuredBannerViewModel.refreshIfStale(
            for: .guide,
            federalState: viewModel.selectedFederalState
        )
    }

    private func refreshFeaturedBanners() async {
        await featuredBannerViewModel.refresh(
            for: .guide,
            federalState: viewModel.selectedFederalState
        )
    }

    private func triggerSearchDebounce() {
        searchDebounceTask?.cancel()

        let trimmedQuery = searchPlaceholderText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.count >= guideMinimumSearchQueryLength else {
            isSearchLoading = false
            searchError = nil
            searchResults = .empty
            return
        }

        searchDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await runSearch(query: trimmedQuery)
        }
    }

    @MainActor
    private func runSearch(query: String) async {
        isSearchLoading = true
        defer { isSearchLoading = false }

        do {
            searchResults = try await viewModel.searchResults(for: query)
            searchError = nil
        } catch let appError as AppError {
            searchError = appError
            searchResults = .empty
        } catch {
            searchError = .unknown
            searchResults = .empty
        }
    }

    private func toggleSavedFilter() {
        guard authState.isAuthenticated else {
            guestAccessAction = .bookmarks
            return
        }

        isSavedFilterSelected.toggle()
        guard isSavedFilterSelected else { return }

        Task {
            await viewModel.loadSavedMaterialsIfNeeded()
        }
    }

    private func handleSavedToggle(for material: GuideMaterial) {
        guard authState.isAuthenticated else {
            guestAccessAction = .bookmarks
            return
        }

        Task {
            do {
                try await viewModel.toggleSavedMaterial(material)
                saveError = nil
            } catch let appError as AppError {
                saveError = appError
            } catch {
                saveError = .unknown
            }
        }
    }

    private func handleGuideBannerCategoryTarget(_ category: GuideCategory) {
        searchDebounceTask?.cancel()
        isSearchPresented = false
        searchPlaceholderText = ""
        searchResults = .empty
        isSearchLoading = false
        searchError = nil
        isSavedFilterSelected = false
        presentedBannerCategory = category
        guideBannerCategoryTarget = nil
    }

    private func resetNavigationState() {
        searchDebounceTask?.cancel()
        searchDebounceTask = nil
        isSearchPresented = false
        searchPlaceholderText = ""
        searchResults = .empty
        isSearchLoading = false
        searchError = nil
        isSavedFilterSelected = false
        presentedBannerCategory = nil
        presentedGuideNodeRoute = nil
        presentedGuideMaterialRoute = nil
        guideMaterialRouteError = nil
        guideBannerCategoryTarget = nil
        guideMaterialTargetID = nil
    }

    private func handleGuideMaterialTarget(_ materialID: String) {
        searchDebounceTask?.cancel()
        isSearchPresented = false
        searchPlaceholderText = ""
        searchResults = .empty
        isSearchLoading = false
        searchError = nil
        isSavedFilterSelected = false

        Task {
            do {
                let material = try await viewModel.material(id: materialID)
                presentedGuideMaterialRoute = GuideMaterialNavigationRoute(material: material)
                guideMaterialRouteError = nil
            } catch let appError as AppError {
                guideMaterialRouteError = appError
            } catch {
                guideMaterialRouteError = .unknown
            }
            guideMaterialTargetID = nil
        }
    }

    private func guideMaterialRouteErrorMessage(_ error: AppError) -> String {
        switch error {
        case .notFound:
            return AppStrings.NotificationInbox.destinationUnavailableMessage
        case .network:
            return AppStrings.News.loadNetworkError
        case .permissionDenied:
            return AppStrings.News.loadPermissionError
        case .validationFailed:
            return AppStrings.News.loadValidationError
        case .unknown:
            return AppStrings.NotificationInbox.destinationUnavailableMessage
        }
    }

    private func regionTitle(for federalState: AustrianFederalState) -> String {
        switch federalState {
        case .burgenland:
            return "Burgenland"
        case .kaernten:
            return "Kärnten"
        case .niederoesterreich:
            return "Niederösterreich"
        case .oberoesterreich:
            return "Oberösterreich"
        case .salzburg:
            return "Salzburg"
        case .steiermark:
            return "Steiermark"
        case .tirol:
            return "Tirol"
        case .vorarlberg:
            return "Vorarlberg"
        case .wien:
            return "Wien"
        }
    }
}

private struct GuideMaterialNavigationRoute: Identifiable, Hashable {
    let material: GuideMaterial

    var id: String { material.id }

    static func == (lhs: GuideMaterialNavigationRoute, rhs: GuideMaterialNavigationRoute) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

private struct GuideNodeNavigationRoute: Identifiable, Hashable {
    let node: GuideNode

    var id: String { node.id }

    static func == (lhs: GuideNodeNavigationRoute, rhs: GuideNodeNavigationRoute) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

private struct GuideCategoryLinkCard: View {
    let title: String
    let systemImage: String

    var body: some View {
        SoftContentCard(padding: AppTheme.organizationsCardPadding) {
            VStack(alignment: .leading, spacing: AppTheme.compactCardInnerSpacing) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.feedThumbnailRadius, style: .continuous)
                        .fill(AppTheme.badgeBlueFill)

                    Image(systemName: systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.accentPrimary)
                }
                .frame(width: AppTheme.iconButtonSize, height: AppTheme.iconButtonSize)

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
            }
            .frame(
                maxWidth: .infinity,
                minHeight: AppTheme.organizationsCategoryCardHeight,
                alignment: .leading
            )
        }
    }
}

private struct GuideMaterialResultRow: View {
    let material: GuideMaterial
    let isSaved: Bool
    let isSavePending: Bool
    let openMaterial: () -> Void
    let onToggleSaved: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.compactCardInnerSpacingRelaxed) {
            Button(action: openMaterial) {
                GuideMaterialCard(material: material)
            }
            .buttonStyle(.plain)

            Button(action: onToggleSaved) {
                GuideBookmarkButton(
                    isSaved: isSaved,
                    isDisabled: isSavePending,
                    action: onToggleSaved
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.Action.save)
        }
    }
}

#Preview {
    NavigationStack {
        GuideReaderView(
            viewModel: GuideReaderViewModel(repository: MockGuideRepository())
        )
    }
    .environmentObject(AuthState())
}
