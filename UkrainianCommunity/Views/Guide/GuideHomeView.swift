import PhotosUI
import SwiftUI

private struct GuideScreenContent {
    let filteredArticles: [GuideArticle]
    let regularArticles: [GuideArticle]
    let smartCollections: GuideSmartCollectionSet
    let availableCategories: [GuideCategory]
}

struct GuideHomeView: View {
    @EnvironmentObject private var authState: AuthState
    @ObservedObject var viewModel: GuideListViewModel
    @StateObject private var heroBannerViewModel: AppHeroBannerViewModel
    @State private var selectedBannerPhoto: PhotosPickerItem?

    init(
        viewModel: GuideListViewModel,
        bannerService: HomeBannerServiceProtocol = FirestoreHomeBannerService()
    ) {
        self.viewModel = viewModel
        _heroBannerViewModel = StateObject(wrappedValue: AppHeroBannerViewModel(
            section: .guide,
            bannerService: bannerService
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

    var body: some View {
        let content = screenContent

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                guideHeader
                    .padding(.bottom, AppTheme.homeHeaderHeroSpacing)

                guideHero
                    .padding(.bottom, AppTheme.homeSectionSpacing)

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
        .task {
            await viewModel.loadIfNeeded()
            await viewModel.refreshIfStale()
            await heroBannerViewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.refresh()
            await heroBannerViewModel.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .guideChanged)) { _ in
            Task {
                await viewModel.refresh()
            }
        }
        .onChange(of: selectedBannerPhoto) { _, newItem in
            Task {
                await updateGuideBanner(from: newItem)
                selectedBannerPhoto = nil
            }
        }
        .alert(
            AppStrings.Home.bannerUploadFailed,
            isPresented: Binding(
                get: { heroBannerViewModel.error != nil },
                set: { isPresented in
                    if !isPresented {
                        heroBannerViewModel.clearError()
                    }
                }
            )
        ) {
            Button(AppStrings.News.dismissError, role: .cancel) {
                heroBannerViewModel.clearError()
            }
        }
    }

    private var guideHeader: some View {
        AppBrandHeader {
            EmptyView()
        }
    }

    private var guideHero: some View {
        ZStack(alignment: .bottomTrailing) {
            AppHeroBanner(
                title: AppStrings.Guide.heroTitle,
                subtitle: AppStrings.Guide.heroSubtitle,
                imageSource: heroBannerViewModel.imageSource,
                height: AppTheme.guideHeroHeight,
                displaysTextOverImage: true
            )

            if PermissionService.canManageHomeBanner(user: authState.user) {
                AppHeroBannerEditButton(
                    selectedItem: $selectedBannerPhoto,
                    isUploading: heroBannerViewModel.isUploading
                )
                .padding(10)
            }
        }
    }

    private func updateGuideBanner(from item: PhotosPickerItem?) async {
        guard let item else { return }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                heroBannerViewModel.setSelectionFailed()
                return
            }

            await heroBannerViewModel.updateImage(data: data, user: authState.user)
        } catch {
            heroBannerViewModel.setSelectionFailed()
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
        GuideHomeView(viewModel: GuideListViewModel(repository: MockGuideRepository()))
    }
    .environmentObject(AuthState())
}
