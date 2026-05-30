import SwiftUI

private struct GuideScreenContent {
    let filteredArticles: [GuideArticle]
    let regularArticles: [GuideArticle]
    let smartCollections: GuideSmartCollectionSet
    let availableCategories: [GuideCategory]
}

struct GuideHomeView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var authState: AuthState
    @ObservedObject var viewModel: GuideListViewModel
    @StateObject private var featuredBannerViewModel: FeaturedBannerListViewModel
    @State private var routedGuideArticle: GuideArticle?
    @State private var routedGuideArticleID: String?
    private let featuredBannerActionResolver = FeaturedBannerActionResolver()

    init(
        viewModel: GuideListViewModel,
        featuredBannerRepository: FeaturedBannerRepository = FirestoreFeaturedBannerRepository()
    ) {
        self.viewModel = viewModel
        _featuredBannerViewModel = StateObject(wrappedValue: FeaturedBannerListViewModel(
            repository: featuredBannerRepository
        ))
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

        ScrollView(.vertical, showsIndicators: false) {
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
        .background(AppBackgroundView())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: featuredBannerLoadKey) {
            await viewModel.loadIfNeeded()
            await viewModel.refreshIfStale()
            await loadFeaturedBanners()
        }
        .refreshable {
            await viewModel.refresh()
            await loadFeaturedBanners()
        }
        .onReceive(NotificationCenter.default.publisher(for: .guideChanged)) { _ in
            Task {
                await viewModel.refresh()
            }
        }
        .navigationDestination(item: $routedGuideArticleID) { _ in
            if let routedGuideArticle {
                GuideDetailView(article: routedGuideArticle)
            }
        }
    }

    private var guideHeader: some View {
        AppBrandHeader {
            EmptyView()
        }
    }

    @ViewBuilder
    private var featuredGuideCarousel: some View {
        if !featuredBannerViewModel.banners.isEmpty {
            FeaturedBannerCarouselView(
                banners: featuredBannerViewModel.banners,
                sizing: .fixedHeight(AppTheme.guideHeroHeight),
                onBannerTap: handleFeaturedBannerTap
            )
        }
    }

    private func loadFeaturedBanners() async {
        await featuredBannerViewModel.loadActiveBanners(
            for: .guide,
            federalState: selectedFederalState
        )
    }

    private func handleFeaturedBannerTap(_ banner: FeaturedBanner) {
        switch featuredBannerActionResolver.resolve(banner, opensPartnerURL: false) {
        case .noAction, .openNews, .openEvent, .openOrganization:
            return
        case let .openURL(url):
            openURL(url)
        case let .openGuide(id):
            Task {
                guard let article = await viewModel.resolveArticle(id: id) else { return }
                routedGuideArticle = article
                routedGuideArticleID = article.id
            }
        }
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
        NavigationLink {
            GuideDetailView(article: article)
        } label: {
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
