import SwiftUI

private let directoryScrollTopID = "directoryScrollTop"
private let directoryCategoriesID = "directoryCategories"

struct DirectoryHomeView: View {
    @EnvironmentObject private var authState: AuthState
    @AppStorage("selectedAppLanguage") private var languageCode = AppLanguage.stored.rawValue
    @Binding var selectedFederalState: AustrianFederalState?
    let onFeaturedBannerTap: (FeaturedBanner) -> Void
    let scrollResetToken: Int
    let searchResetToken: Int
    let isActive: Bool

    @StateObject private var featuredBannerViewModel: FeaturedBannerListViewModel
    @State private var isSearchPresented = false
    @State private var searchText = ""

    init(
        featuredBannerRepository: FeaturedBannerRepository,
        featuredBannerCache: FeaturedBannerCache,
        selectedFederalState: Binding<AustrianFederalState?>,
        onFeaturedBannerTap: @escaping (FeaturedBanner) -> Void,
        scrollResetToken: Int,
        searchResetToken: Int,
        isActive: Bool
    ) {
        _featuredBannerViewModel = StateObject(wrappedValue: FeaturedBannerListViewModel(
            repository: featuredBannerRepository, cache: featuredBannerCache
        ))
        _selectedFederalState = selectedFederalState
        self.onFeaturedBannerTap = onFeaturedBannerTap
        self.scrollResetToken = scrollResetToken
        self.searchResetToken = searchResetToken
        self.isActive = isActive
    }

    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? .german }
    private var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var categories: [DirectoryCategory] {
        guard !query.isEmpty else { return DirectoryCatalog.categories }
        return DirectoryCatalog.categories.filter { $0.matches(query, language: language) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 0).id(directoryScrollTopID)

                    AppSearchableBrandHeader(
                        isSearchPresented: $isSearchPresented,
                        searchText: $searchText,
                        placeholder: DirectoryStrings.searchPlaceholder,
                        collapseToken: searchResetToken
                    )
                    .padding(.bottom, AppTheme.homeHeaderHeroSpacing)

                    if query.isEmpty {
                        banner {
                            withAnimation(.easeInOut) {
                                proxy.scrollTo(directoryCategoriesID, anchor: .top)
                            }
                        }
                        .padding(.bottom, AppTheme.homeSectionSpacing)
                        introductoryContent
                    } else {
                        searchContent
                    }
                }
                .padding(.horizontal, AppTheme.pageHorizontal)
                .padding(.bottom, AppTheme.homeBottomContentPadding)
                .appCenteredContent(maxWidth: AppTheme.feedContentMaxWidth)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: scrollResetToken) { _, _ in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { proxy.scrollTo(directoryScrollTopID, anchor: .top) }
            }
        }
        .background(AppBackgroundView())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: DirectoryRoute.self) { route in
            destination(for: route)
        }
        .appRefreshable { await refresh() }
        .task(id: bannerLoadKey) {
            guard isActive, isAuthBootstrapReady else { return }
            await featuredBannerViewModel.loadIfNeeded(for: .directory, federalState: selectedFederalState)
            await featuredBannerViewModel.refreshIfStale(for: .directory, federalState: selectedFederalState)
        }
        .observesKeyboardDismissTaps()
    }

    @ViewBuilder private func banner(onBrowse: @escaping () -> Void) -> some View {
        if !featuredBannerViewModel.banners.isEmpty {
            FeaturedBannerCarouselView(
                banners: featuredBannerViewModel.banners,
                sizing: .responsiveHero,
                onBannerTap: onFeaturedBannerTap
            )
        } else {
            DirectoryWelcomeBanner(onBrowse: onBrowse)
                .id(languageCode)
        }
    }

    private var introductoryContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.homeSectionSpacing) {
            Text(DirectoryStrings.categoriesHeading)
                .font(.title2.bold())
                .foregroundStyle(AppTheme.textPrimary)
                .id(directoryCategoriesID)

            if let safety = DirectoryCatalog.categories.first {
                NavigationLink(value: DirectoryRoute.category(safety.id)) {
                    DirectorySafetyCard(category: safety, language: language)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("directory.category.safety")
            }

            categorySection(DirectoryStrings.startHeading, items: Array(DirectoryCatalog.startCategories.dropFirst()))
            categorySection(DirectoryStrings.lifeHeading, items: DirectoryCatalog.lifeCategories)
            categorySection(DirectoryStrings.supportHeading, items: DirectoryCatalog.supportCategories)

            Text(DirectoryStrings.preparing)
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    private var searchContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.homeSectionSpacing) {
            if categories.isEmpty {
                ContentUnavailableView(
                    DirectoryStrings.noResults,
                    systemImage: "magnifyingglass",
                    description: Text(DirectoryStrings.tryAnotherQuery)
                )
            } else {
                Text(DirectoryStrings.categoriesHeading)
                    .font(.title3.bold())
                categoryList(categories)
            }
        }
    }

    private func categorySection(_ title: String, items: [DirectoryCategory]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
            categoryList(items)
        }
    }

    private func categoryList(_ items: [DirectoryCategory]) -> some View {
        LazyVStack(spacing: 9) {
            ForEach(items) { category in
                NavigationLink(value: DirectoryRoute.category(category.id)) {
                    DirectoryCategoryCard(category: category, language: language)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("directory.category.\(category.id)")
            }
        }
    }

    @ViewBuilder private func destination(for route: DirectoryRoute) -> some View {
        switch route {
        case let .category(id):
            if let category = DirectoryCatalog.categories.first(where: { $0.id == id }) {
                if id == "safety" {
                    DirectorySafetyOverviewView(category: category)
                } else if id == "first-steps" || id == "registration" {
                    DirectoryGuideCategoryView(category: category)
                } else {
                    DirectoryCategoryView(category: category)
                }
            }
        case let .topic(categoryID, topicID):
            if let topic = DirectoryCatalog.categories.first(where: { $0.id == categoryID })?.topics.first(where: { $0.id == topicID }) {
                if categoryID == "safety", let guide = DirectorySafetyContent.guides[topicID] {
                    DirectorySafetyTopicView(topic: topic, guide: guide)
                } else if let guide = DirectoryGuideCatalog.guide(categoryID: categoryID, topicID: topicID) {
                    DirectoryGuideTopicView(categoryID: categoryID, topic: topic, guide: guide)
                } else {
                    DirectoryTopicView(topic: topic)
                }
            }
        }
    }

    private var bannerLoadKey: String {
        "\(selectedFederalState?.rawValue ?? "allAustria"):\(isActive):\(authState.sessionState)"
    }

    private var isAuthBootstrapReady: Bool {
        authState.sessionState != .restoring && authState.sessionState != .authenticating
    }

    private func refresh() async {
        guard isAuthBootstrapReady else { return }
        await featuredBannerViewModel.refresh(for: .directory, federalState: selectedFederalState)
    }
}
