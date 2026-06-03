import SwiftUI

private struct GuideScreenContent {
    let filteredArticles: [GuideArticle]
    let secondaryArticles: [GuideArticle]
    let smartCollections: GuideSmartCollectionSet
    let availableCategories: [GuideCategory]
    let hasActiveFilters: Bool
    let smartSectionIDs: Set<String>
}

private let guideRootScrollTopID = "guideRootScrollTop"

struct GuideNavigationRoute: Hashable {
    let articleID: String
}

struct GuideHomeView: View {
    @EnvironmentObject private var authState: AuthState
    @ObservedObject var viewModel: GuideListViewModel
    @StateObject private var featuredBannerViewModel: FeaturedBannerListViewModel
    @State private var isSearchPresented = false
    @Binding var navigationPath: [GuideNavigationRoute]
    let onFeaturedBannerTap: (FeaturedBanner) -> Void
    let scrollResetToken: Int

    init(
        viewModel: GuideListViewModel,
        featuredBannerRepository: FeaturedBannerRepository = FirestoreFeaturedBannerRepository(),
        navigationPath: Binding<[GuideNavigationRoute]> = .constant([]),
        onFeaturedBannerTap: @escaping (FeaturedBanner) -> Void = { _ in },
        scrollResetToken: Int = 0
    ) {
        self.viewModel = viewModel
        self.onFeaturedBannerTap = onFeaturedBannerTap
        self.scrollResetToken = scrollResetToken
        _featuredBannerViewModel = StateObject(wrappedValue: FeaturedBannerListViewModel(
            repository: featuredBannerRepository
        ))
        _navigationPath = navigationPath
    }

    private var screenContent: GuideScreenContent {
        let filteredArticles = viewModel.filteredArticles
        let hasActiveFilters = viewModel.filterState.hasActiveFilters
        let smartCollections = viewModel.smartCollections
        let smartSectionIDs = Set([
            smartCollections.importantNow,
            smartCollections.newcomers,
            smartCollections.emergency,
            smartCollections.popular,
            smartCollections.recentlyUpdated
        ].flatMap { $0.map(\.id) })
        let secondaryArticles = filteredArticles
            .filter { hasActiveFilters || !smartSectionIDs.contains($0.id) }
            .sorted { $0.updatedAt > $1.updatedAt }
        let categories = Set(viewModel.articles.map(\.category))
        let availableCategories = GuideCategory.allCases.filter { categories.contains($0) }

        return GuideScreenContent(
            filteredArticles: filteredArticles,
            secondaryArticles: secondaryArticles,
            smartCollections: smartCollections,
            availableCategories: availableCategories,
            hasActiveFilters: hasActiveFilters,
            smartSectionIDs: smartSectionIDs
        )
    }

    private var selectedFederalState: AustrianFederalState? {
        authState.user?.selectedFederalState
    }

    private var featuredBannerLoadKey: String {
        selectedFederalState?.rawValue ?? "allAustria"
    }

    var body: some View {
        let content = screenContent

        ScrollViewReader { scrollProxy in
            ScrollView(.vertical, showsIndicators: false) {
                Color.clear
                    .frame(height: 0)
                    .id(guideRootScrollTopID)

                VStack(alignment: .leading, spacing: 0) {
                    guideHeader
                        .padding(.bottom, AppTheme.homeHeaderHeroSpacing)

                    featuredGuideCarousel
                        .padding(.bottom, featuredBannerViewModel.banners.isEmpty ? 0 : AppTheme.homeSectionSpacing)

                    GuideSearchAndFiltersView(viewModel: viewModel)
                        .padding(.bottom, AppTheme.homeSectionSpacing)

                    GuidePopularCategoriesSection(
                        categories: content.availableCategories,
                        selectedCategory: $viewModel.selectedCategory
                    )
                    .padding(.bottom, AppTheme.homeSectionSpacing)

                    AppGroupedContentPlane {
                        guideArticlesContent(content)
                    }
                }
                .padding(.horizontal, AppTheme.pageHorizontal)
                .padding(.bottom, AppTheme.homeBottomContentPadding)
            }
            .onChange(of: scrollResetToken) {
                scrollToTop(with: scrollProxy)
            }
        }
        .background(AppBackgroundView())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: featuredBannerLoadKey) {
            await viewModel.loadIfNeeded()
            await viewModel.refreshIfStale()
            await refreshFeaturedBannersIfStale()
        }
        .refreshable {
            await viewModel.refresh()
            await refreshFeaturedBanners()
        }
        .onReceive(NotificationCenter.default.publisher(for: .guideChanged)) { _ in
            Task {
                await viewModel.refresh()
            }
        }
        .navigationDestination(for: GuideNavigationRoute.self) { route in
            if let article = viewModel.articles.first(where: { $0.id == route.articleID }) {
                GuideDetailView(article: article)
            }
        }
    }

    private func scrollToTop(with scrollProxy: ScrollViewProxy) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            scrollProxy.scrollTo(guideRootScrollTopID, anchor: .top)
        }
    }

    private var guideHeader: some View {
        AppSearchableBrandHeader(
            isSearchPresented: $isSearchPresented,
            searchText: $viewModel.searchText,
            placeholder: AppStrings.Search.guidePlaceholder
        )
    }

    @ViewBuilder
    private var featuredGuideCarousel: some View {
        if !featuredBannerViewModel.banners.isEmpty {
            FeaturedBannerCarouselView(
                banners: featuredBannerViewModel.banners,
                sizing: .responsiveHero,
                onBannerTap: onFeaturedBannerTap
            )
        }
    }

    private func refreshFeaturedBannersIfStale() async {
        await featuredBannerViewModel.refreshIfStale(
            for: .guide,
            federalState: selectedFederalState
        )
    }

    private func refreshFeaturedBanners() async {
        await featuredBannerViewModel.refresh(
            for: .guide,
            federalState: selectedFederalState
        )
    }

    @ViewBuilder
    private func guideArticlesContent(_ content: GuideScreenContent) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.feedRowSpacing) {
            if viewModel.isLoading && viewModel.articles.isEmpty {
                GuideLoadingView()
            } else if viewModel.articles.isEmpty, let error = viewModel.error {
                GuideErrorStateView(error: error) {
                    viewModel.reload()
                }
            } else if viewModel.articles.isEmpty {
                GuideEmptyStateView(kind: .noArticles)
            } else {
                populatedGuideContent(content)
            }
        }
    }

    @ViewBuilder
    private func populatedGuideContent(_ content: GuideScreenContent) -> some View {
        if content.hasActiveFilters {
            DashboardSectionHeader(title: AppStrings.Guide.allArticlesTitle)

            if content.filteredArticles.isEmpty {
                narrowedResultsEmptyState
            } else {
                DashboardFeedContainer(
                    items: content.filteredArticles.sorted { $0.updatedAt > $1.updatedAt },
                    spacing: AppTheme.feedRowSpacing
                ) { article in
                    guideArticleLink(article, emphasized: false)
                }
            }
        } else {
            smartSection(title: AppStrings.Guide.pinnedTitle, articles: content.smartCollections.importantNow, emphasized: true)
            smartSection(title: AppStrings.Guide.newcomersTitle, articles: content.smartCollections.newcomers, emphasized: false)
            smartSection(title: AppStrings.Guide.emergencyTitle, articles: content.smartCollections.emergency, emphasized: false)
            smartSection(title: AppStrings.Guide.featuredTitle, articles: content.smartCollections.popular, emphasized: false)
            smartSection(title: AppStrings.Guide.recentlyUpdatedTitle, articles: content.smartCollections.recentlyUpdated, emphasized: false)

            if !content.secondaryArticles.isEmpty {
                DashboardSectionHeader(
                    title: content.smartSectionIDs.isEmpty ? AppStrings.Guide.allArticlesTitle : AppStrings.Guide.moreArticlesTitle
                )

                DashboardFeedContainer(
                    items: content.secondaryArticles,
                    spacing: AppTheme.feedRowSpacing
                ) { article in
                    guideArticleLink(article, emphasized: false)
                }
            } else if content.smartSectionIDs.isEmpty {
                GuideEmptyStateView(kind: .noArticles)
            }
        }
    }

    private var narrowedResultsEmptyState: some View {
        EmptyStateCard(
            systemImage: "line.3.horizontal.decrease.circle",
            title: AppStrings.Guide.noMatchesTitle,
            message: noResultsContextMessage
        )
        .frame(maxWidth: .infinity, minHeight: 180)
    }

    private var noResultsContextMessage: String {
        let summaryParts = viewModel.filterState.homeSummaryParts
        guard !summaryParts.isEmpty else {
            return AppStrings.Guide.noResultsNarrowHint
        }

        let summary = summaryParts.joined(separator: ", ")
        return "\(AppStrings.Guide.noResultsForSummary(summary)) \(AppStrings.Guide.noResultsNarrowHint)"
    }

    @ViewBuilder
    private func smartSection(title: String, articles: [GuideArticle], emphasized: Bool) -> some View {
        if !articles.isEmpty {
            DashboardSectionHeader(title: title)

            DashboardFeedContainer(items: articles, spacing: AppTheme.feedRowSpacing) { article in
                guideArticleLink(article, emphasized: emphasized)
            }
        }
    }

    private func guideArticleLink(_ article: GuideArticle, emphasized: Bool) -> some View {
        NavigationLink(value: GuideNavigationRoute(articleID: article.id)) {
            GuideArticleCard(article: article, emphasized: emphasized)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(article.title)
        .accessibilityHint(AppStrings.Guide.articleDetailTitle)
    }
}

private extension GuideFilterState {
    var homeSummaryParts: [String] {
        var parts: [String] = []

        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSearchText.isEmpty {
            parts.append(AppStrings.Guide.filterSummaryItem(AppStrings.Guide.filterSearchLabel, trimmedSearchText))
        }

        if let selectedCategory {
            parts.append(AppStrings.Guide.filterSummaryItem(AppStrings.Guide.filterCategoryLabel, selectedCategory.title))
        }

        if let selectedContentType {
            let title: String
            switch selectedContentType {
            case .guide:
                title = AppStrings.Guide.contentTypeGuide
            case .quickInfo:
                title = AppStrings.Guide.contentTypeQuickInfo
            case .checklist:
                title = AppStrings.Guide.contentTypeChecklist
            case .contact:
                title = AppStrings.Guide.contentTypeContact
            case .process:
                title = AppStrings.Guide.contentTypeProcess
            }
            parts.append(AppStrings.Guide.filterSummaryItem(AppStrings.Guide.filterTypeLabel, title))
        }

        if let selectedFederalState {
            parts.append(AppStrings.Guide.filterSummaryItem(AppStrings.Guide.filterRegionLabel, AppStrings.FederalStates.title(for: selectedFederalState)))
        }

        if let selectedAudience, !selectedAudience.isEmpty {
            parts.append(AppStrings.Guide.filterSummaryItem(AppStrings.Guide.filterAudienceLabel, selectedAudience))
        }

        return parts
    }
}

#Preview {
    NavigationStack {
        GuideHomeView(
            viewModel: GuideListViewModel(repository: MockGuideRepository()),
            featuredBannerRepository: MockFeaturedBannerRepository()
        )
    }
    .environmentObject(AuthState())
}
