import SwiftUI

private struct GuideScreenContent {
    let filteredArticles: [GuideArticle]
    let regularArticles: [GuideArticle]
    let smartCollections: GuideSmartCollectionSet
    let availableCategories: [GuideCategory]
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
        let regularArticles = filteredArticles
            .sorted { $0.updatedAt > $1.updatedAt }
        let categories = Set(viewModel.articles.map(\.category))
        let availableCategories = GuideCategory.allCases.filter { categories.contains($0) }

        return GuideScreenContent(
            filteredArticles: filteredArticles,
            regularArticles: regularArticles,
            smartCollections: viewModel.smartCollections,
            availableCategories: availableCategories
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
        smartSection(title: AppStrings.Guide.pinnedTitle, articles: content.smartCollections.importantNow, emphasized: true)
        smartSection(title: AppStrings.Guide.newcomersTitle, articles: content.smartCollections.newcomers, emphasized: false)
        smartSection(title: AppStrings.Guide.emergencyTitle, articles: content.smartCollections.emergency, emphasized: false)
        smartSection(title: AppStrings.Guide.featuredTitle, articles: content.smartCollections.popular, emphasized: false)
        smartSection(title: AppStrings.Guide.recentlyUpdatedTitle, articles: content.smartCollections.recentlyUpdated, emphasized: false)

        DashboardSectionHeader(title: AppStrings.Guide.allArticlesTitle)

        if content.filteredArticles.isEmpty && viewModel.filterState.hasActiveFilters {
            GuideEmptyStateView(kind: .noMatches)
        } else {
            DashboardFeedContainer(
                items: content.regularArticles,
                spacing: AppTheme.feedRowSpacing
            ) { article in
                guideArticleLink(article, emphasized: false)
            }
        }
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

#Preview {
    NavigationStack {
        GuideHomeView(
            viewModel: GuideListViewModel(repository: MockGuideRepository()),
            featuredBannerRepository: MockFeaturedBannerRepository()
        )
    }
    .environmentObject(AuthState())
}
