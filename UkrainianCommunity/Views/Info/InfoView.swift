import PhotosUI
import SwiftUI

private struct GuideScreenContent {
    let filteredArticles: [GuideArticle]
    let pinnedArticles: [GuideArticle]
    let regularArticles: [GuideArticle]
    let availableCategories: [GuideCategory]
}

struct InfoView: View {
    @EnvironmentObject private var authState: AuthState
    @ObservedObject var viewModel: InfoViewModel
    @StateObject private var heroBannerViewModel: AppHeroBannerViewModel
    @State private var selectedCategory: GuideCategory?
    @State private var selectedBannerPhoto: PhotosPickerItem?

    init(
        viewModel: InfoViewModel,
        bannerService: HomeBannerServiceProtocol = FirestoreHomeBannerService()
    ) {
        self.viewModel = viewModel
        _heroBannerViewModel = StateObject(wrappedValue: AppHeroBannerViewModel(
            section: .guide,
            bannerService: bannerService
        ))
    }

    private var screenContent: GuideScreenContent {
        let filteredArticles = viewModel.articles.filter { article in
            let matchesCategory = selectedCategory == nil || article.category == selectedCategory
            return matchesCategory
        }
        let pinnedArticles = filteredArticles
            .filter(\.isPinned)
            .sorted { $0.updatedAt > $1.updatedAt }
        let regularArticles = filteredArticles
            .filter { !$0.isPinned }
            .sorted { $0.updatedAt > $1.updatedAt }
        let categories = Set(viewModel.articles.map(\.category))
        let availableCategories = GuideCategory.allCases.filter { categories.contains($0) }

        return GuideScreenContent(
            filteredArticles: filteredArticles,
            pinnedArticles: pinnedArticles,
            regularArticles: regularArticles,
            availableCategories: availableCategories
        )
    }

    var body: some View {
        let content = screenContent

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.eventsHeaderContentSpacing) {
                guideHeader

                guideHero

                GuidePopularCategoriesSection(
                    categories: content.availableCategories,
                    selectedCategory: $selectedCategory
                )

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
            AppNotificationBellButton()
        }
    }

    private var guideHero: some View {
        ZStack(alignment: .bottomTrailing) {
            AppHeroBanner(
                title: AppStrings.Info.heroTitle,
                subtitle: AppStrings.Info.heroSubtitle,
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
            if !content.pinnedArticles.isEmpty {
                DashboardSectionHeader(title: AppStrings.Info.pinnedTitle)

                DashboardFeedContainer(items: content.pinnedArticles, spacing: AppTheme.feedRowSpacing) { article in
                    guideArticleLink(article, emphasized: true)
                }
            }

            DashboardSectionHeader(title: AppStrings.Info.allArticlesTitle)

            if content.filteredArticles.isEmpty {
                EmptyStateCard(
                    systemImage: "book.closed",
                    title: AppStrings.Info.title,
                    message: AppStrings.Info.noResults
                )
            } else {
                DashboardFeedContainer(
                    items: content.regularArticles.isEmpty ? content.pinnedArticles : content.regularArticles,
                    spacing: AppTheme.feedRowSpacing
                ) { article in
                    guideArticleLink(article, emphasized: false)
                }
            }
        }
    }

    private func guideArticleLink(_ article: GuideArticle, emphasized: Bool) -> some View {
        NavigationLink {
            GuideArticleDetailView(article: article)
        } label: {
            GuideArticleCard(article: article, emphasized: emphasized)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(article.title)
        .accessibilityHint(AppStrings.Info.articleDetailTitle)
    }
}

private struct GuidePopularCategoriesSection: View {
    let categories: [GuideCategory]
    @Binding var selectedCategory: GuideCategory?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeaderBlock(title: AppStrings.Info.popularCategoriesTitle)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.dashboardSpacing) {
                    GuideCategoryCard(
                        title: AppStrings.Info.allCategories,
                        systemImage: "square.grid.2x2",
                        isSelected: selectedCategory == nil
                    ) {
                        selectedCategory = nil
                    }

                    ForEach(categories) { category in
                        GuideCategoryCard(
                            title: category.title,
                            systemImage: category.systemImage,
                            isSelected: selectedCategory == category
                        ) {
                            selectedCategory = selectedCategory == category ? nil : category
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct GuideCategoryCard: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SoftContentCard(padding: AppTheme.organizationsCardPadding) {
                VStack(alignment: .leading, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: AppTheme.feedThumbnailRadius, style: .continuous)
                            .fill(isSelected ? AppTheme.accentPrimary : AppTheme.badgeBlueFill)

                        Image(systemName: systemImage)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(isSelected ? .white : AppTheme.accentPrimary)
                    }
                    .frame(width: 44, height: 44)

                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .frame(
                    width: AppTheme.organizationsCategoryCardWidth,
                    height: AppTheme.organizationsCategoryCardHeight,
                    alignment: .leading
                )
            }
        }
        .buttonStyle(.plain)
    }
}

private struct GuideArticleCard: View {
    let article: GuideArticle
    let emphasized: Bool

    var body: some View {
        SoftContentCard(padding: AppTheme.organizationsCardPadding) {
            HStack(alignment: .center, spacing: AppTheme.eventsCardHorizontalSpacing) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.feedThumbnailRadius, style: .continuous)
                        .fill(AppTheme.badgeBlueFill)

                    Image(systemName: article.category.systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.accentPrimary)
                }
                .frame(width: AppTheme.organizationsThumbnailSize, height: AppTheme.organizationsThumbnailSize)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        AppInfoChip(
                            title: article.category.title,
                            systemImage: article.category.systemImage,
                            tint: AppTheme.accentPrimary,
                            fill: AppTheme.badgeBlueFill,
                            size: .small
                        )

                        if article.isPinned {
                            AppInfoChip(
                                title: AppStrings.Info.pinnedTitle,
                                systemImage: "pin.fill",
                                tint: AppTheme.accentPrimary,
                                fill: AppTheme.badgeBlueFill,
                                size: .small
                            )
                        }
                    }

                    Text(article.title)
                        .font(emphasized ? .headline.weight(.semibold) : .subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)

                    Text(article.summary)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary.opacity(0.84))
                        .lineLimit(2)

                    if let sourceName = article.sourceName, !sourceName.isEmpty {
                        AppMetadataLine(title: sourceName, systemImage: "link")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.72))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        var parts = [article.title, article.summary, article.category.title]

        if article.isPinned {
            parts.append(AppStrings.Info.pinnedTitle)
        }

        if let sourceName = article.sourceName, !sourceName.isEmpty {
            parts.append(sourceName)
        }

        return parts.joined(separator: ", ")
    }
}

private struct GuideArticleDetailView: View {
    let article: GuideArticle

    var body: some View {
        DetailPageContainer {
            DetailHeaderCard(title: article.title, subtitle: nil) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        ContentMetadataPill(systemImage: article.category.systemImage, text: article.category.title)

                        if let sourceName = article.sourceName, !sourceName.isEmpty {
                            ContentMetadataPill(systemImage: "link", text: sourceName)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ContentMetadataPill(systemImage: article.category.systemImage, text: article.category.title)

                        if let sourceName = article.sourceName, !sourceName.isEmpty {
                            ContentMetadataPill(systemImage: "link", text: sourceName)
                        }
                    }
                }
            }

            DetailCard {
                Text(article.summary)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(article.body)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let officialSourceURL = article.officialSourceURL,
               let url = URL(string: officialSourceURL) {
                DetailCard {
                    Link(destination: url) {
                        DetailActionRow {
                            Text(AppStrings.Info.officialSource)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                        } trailingContent: {
                            Image(systemName: "arrow.up.right.square")
                                .foregroundStyle(AppTheme.accentPrimary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AppStrings.Info.officialSource)
                }
            }
        }
        .background(AppTheme.subtleGradient.ignoresSafeArea())
        .navigationTitle(AppStrings.Info.articleDetailTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        InfoView(viewModel: InfoViewModel(repository: MockInfoRepository()))
    }
}
