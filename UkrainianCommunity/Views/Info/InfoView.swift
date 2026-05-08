import SwiftUI

private struct GuideScreenContent {
    let filteredArticles: [GuideArticle]
    let pinnedArticles: [GuideArticle]
    let regularArticles: [GuideArticle]
    let availableCategories: [GuideCategory]
}

struct InfoView: View {
    @ObservedObject var viewModel: InfoViewModel
    @State private var searchText = ""
    @State private var selectedCategory: GuideCategory?

    private var screenContent: GuideScreenContent {
        let normalizedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredArticles = viewModel.articles.filter { article in
            let matchesCategory = selectedCategory == nil || article.category == selectedCategory
            let matchesSearch = normalizedSearchText.isEmpty
                || article.title.localizedCaseInsensitiveContains(normalizedSearchText)
                || article.summary.localizedCaseInsensitiveContains(normalizedSearchText)
                || article.body.localizedCaseInsensitiveContains(normalizedSearchText)
            return matchesCategory && matchesSearch
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

        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.feedSpacing) {
                GradientHeroCard(title: AppStrings.Info.title, subtitle: AppStrings.Info.subtitle) {
                    if let selectedCategory {
                        ContentMetadataPill(systemImage: selectedCategory.systemImage, text: selectedCategory.title)
                    }
                }

                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    SectionHeaderBlock(title: AppStrings.Info.categoriesTitle)
                    GuideCategoryChips(
                        categories: content.availableCategories,
                        selectedCategory: $selectedCategory
                    )
                }

                if !content.pinnedArticles.isEmpty {
                    VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                        SectionHeaderBlock(title: AppStrings.Info.pinnedTitle)

                        ForEach(content.pinnedArticles) { article in
                            NavigationLink {
                                GuideArticleDetailView(article: article)
                            } label: {
                                GuideArticleCard(article: article, emphasized: true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(article.title)
                            .accessibilityHint(AppStrings.Info.articleDetailTitle)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    SectionHeaderBlock(title: AppStrings.Info.allArticlesTitle)

                    if content.filteredArticles.isEmpty {
                        EmptyStateCard(
                            systemImage: "book.closed",
                            title: AppStrings.Info.title,
                            message: AppStrings.Info.noResults
                        )
                    } else {
                        ForEach(content.regularArticles.isEmpty ? content.pinnedArticles : content.regularArticles) { article in
                            NavigationLink {
                                GuideArticleDetailView(article: article)
                            } label: {
                                GuideArticleCard(article: article, emphasized: false)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(article.title)
                            .accessibilityHint(AppStrings.Info.articleDetailTitle)
                        }
                    }
                }
            }
            .padding(.horizontal, AppTheme.pageHorizontal)
            .padding(.top, AppTheme.sectionSpacing)
            .padding(.bottom, 120)
        }
        .background(AppTheme.subtleGradient.ignoresSafeArea())
        .navigationTitle(AppStrings.Info.title)
        .searchable(text: $searchText, prompt: AppStrings.Info.searchPlaceholder)
        .task {
            await viewModel.loadIfNeeded()
            await viewModel.refreshIfStale()
        }
        .refreshable {
            await viewModel.refresh()
        }
    }
}

private struct GuideCategoryChips: View {
    let categories: [GuideCategory]
    @Binding var selectedCategory: GuideCategory?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                SelectableFilterChip(title: AppStrings.Info.allCategories, isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }

                ForEach(categories) { category in
                    SelectableFilterChip(title: category.title, isSelected: selectedCategory == category) {
                        selectedCategory = selectedCategory == category ? nil : category
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct GuideArticleCard: View {
    let article: GuideArticle
    let emphasized: Bool

    var body: some View {
        CommunityCard {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    ContentMetadataPill(systemImage: article.category.systemImage, text: article.category.title)
                    if article.isPinned {
                        ContentMetadataPill(systemImage: "pin.fill", text: AppStrings.Info.pinnedTitle)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    ContentMetadataPill(systemImage: article.category.systemImage, text: article.category.title)
                    if article.isPinned {
                        ContentMetadataPill(systemImage: "pin.fill", text: AppStrings.Info.pinnedTitle)
                    }
                }
            }

            Text(article.title)
                .font(emphasized ? .title3.weight(.bold) : .headline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(article.summary)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let sourceName = article.sourceName, !sourceName.isEmpty {
                ContentMetadataPill(systemImage: "link", text: sourceName)
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
