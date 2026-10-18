import SwiftUI

private let directoryScrollTopID = "directoryScrollTop"
private let directoryCategoriesID = "directoryCategories"

struct DirectoryHomeView: View {
    @EnvironmentObject private var authState: AuthState
    @EnvironmentObject private var contentStore: DirectoryContentStore
    @AppStorage("selectedAppLanguage") private var languageCode = AppLanguage.stored.rawValue
    @Binding var selectedFederalState: AustrianFederalState?
    let onFeaturedBannerTap: (FeaturedBanner) -> Void
    let onFeaturedBannerMeasurement: (FeaturedBannerMeasurement) -> Void
    let scrollResetToken: Int
    let searchResetToken: Int
    let isActive: Bool
    let feedbackRepository: FeedbackRepository

    @StateObject private var featuredBannerViewModel: FeaturedBannerListViewModel
    @StateObject private var recentAdditions = DirectoryRecentAdditionsStore()
    @State private var isSearchPresented = false
    @State private var searchText = ""
    @State private var bannerViewport: CGRect = .zero

    init(
        featuredBannerRepository: FeaturedBannerRepository,
        featuredBannerCache: FeaturedBannerCache,
        selectedFederalState: Binding<AustrianFederalState?>,
        onFeaturedBannerTap: @escaping (FeaturedBanner) -> Void,
        onFeaturedBannerMeasurement: @escaping (FeaturedBannerMeasurement) -> Void = { _ in },
        scrollResetToken: Int,
        searchResetToken: Int,
        isActive: Bool,
        feedbackRepository: FeedbackRepository
    ) {
        _featuredBannerViewModel = StateObject(wrappedValue: FeaturedBannerListViewModel(
            repository: featuredBannerRepository, cache: featuredBannerCache
        ))
        _selectedFederalState = selectedFederalState
        self.onFeaturedBannerTap = onFeaturedBannerTap
        self.onFeaturedBannerMeasurement = onFeaturedBannerMeasurement
        self.scrollResetToken = scrollResetToken
        self.searchResetToken = searchResetToken
        self.isActive = isActive
        self.feedbackRepository = feedbackRepository
    }

    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? .german }
    private var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var searchMatches: [DirectorySearchMatch] {
        DirectorySearchIndex.search(
            query, language: language, categories: contentStore.categories,
            managedTopic: { contentStore.managedTopic(categoryID: $0, topicID: $1) }
        )
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
                        banner
                            .padding(.bottom, !featuredBannerViewModel.banners.isEmpty || featuredBannerViewModel.error != nil
                                ? AppTheme.homeSectionSpacing : 0)
                        introductoryContent
                    } else {
                        searchContent
                    }
                }
                .padding(.horizontal, AppTheme.pageHorizontal)
                .padding(.bottom, AppTheme.homeBottomContentPadding)
                .appCenteredContent(maxWidth: AppTheme.feedContentMaxWidth)
            }
            .featuredBannerViewport($bannerViewport)
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
        .task(id: isActive) {
            guard isActive else { return }
            await recentAdditions.loadIfNeeded()
        }
        .observesKeyboardDismissTaps()
    }

    @ViewBuilder private var banner: some View {
        if !featuredBannerViewModel.banners.isEmpty {
            FeaturedBannerCarouselView(
                banners: featuredBannerViewModel.banners,
                sizing: .responsiveHero,
                section: .directory,
                isActive: isActive && query.isEmpty,
                viewportFrame: bannerViewport,
                onBannerTap: onFeaturedBannerTap,
                onMeasurement: onFeaturedBannerMeasurement
            )
        } else if let error = featuredBannerViewModel.error {
            FeaturedBannerLoadFailureView(error: error) {
                await featuredBannerViewModel.refresh(for: .directory, federalState: selectedFederalState)
            }
        }
    }

    private var introductoryContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.homeSectionSpacing) {
            DirectorySyncNoticeView(language: language)
            HStack {
                Text(DirectoryStrings.categoriesHeading)
                    .font(.title2.bold())
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                if contentStore.canEdit {
                    NavigationLink(value: DirectoryRoute.manage) {
                        Label(DirectoryText(ukrainian: "Керувати", german: "Bearbeiten").value(for: language),
                              systemImage: "square.and.pencil")
                    }
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("directory.manage")
                }
            }
            .id(directoryCategoriesID)

            if let safety = contentStore.startCategories.first(where: { $0.id == "safety" }) {
                NavigationLink(value: DirectoryRoute.category(safety.id)) {
                    DirectorySafetyCard(category: safety, language: language)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("directory.category.safety")
            }

            DirectoryRecentAdditionsView(store: recentAdditions, language: language)

            categorySection(DirectoryStrings.startHeading, items: contentStore.startCategories.filter { $0.id != "safety" })
            categorySection(DirectoryStrings.lifeHeading, items: contentStore.lifeCategories)
            categorySection(DirectoryStrings.supportHeading, items: contentStore.supportCategories)
            DirectoryFeedbackView(kind: .question(categoryID: nil, title: DirectoryText(ukrainian: "Довідник", german: "Ratgeber").value(for: language)), repository: feedbackRepository)
        }
    }

    private var searchContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.homeSectionSpacing) {
            DirectorySyncNoticeView(language: language)
            if searchMatches.isEmpty {
                ContentUnavailableView(
                    DirectoryStrings.noResults,
                    systemImage: "magnifyingglass",
                    description: Text(DirectoryStrings.tryAnotherQuery)
                )
            } else {
                Text(DirectoryStrings.searchResults)
                    .font(.title3.bold())
                DirectorySearchResultsView(matches: searchMatches, language: language)
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
                NavigationLink(value: route(for: category)) {
                    DirectoryCategoryCard(category: category, language: language)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("directory.category.\(category.id)")
            }
        }
    }

    private func route(for category: DirectoryCategory) -> DirectoryRoute {
        if let onlyTopic = category.topics.first, category.topics.count == 1 {
            return .topic(categoryID: category.id, topicID: onlyTopic.id)
        }
        return .category(category.id)
    }

    @ViewBuilder private func destination(for route: DirectoryRoute) -> some View {
        switch route {
        case .recentList:
            ScrollView {
                DirectoryRecentAdditionsView(store: recentAdditions, language: language, isPreview: false)
                    .padding(.horizontal, AppTheme.pageHorizontal)
                    .padding(.bottom, AppTheme.homeBottomContentPadding)
                    .appCenteredContent(maxWidth: AppTheme.feedContentMaxWidth)
            }
            .background(AppBackgroundView())
            .navigationTitle(DirectoryText(ukrainian: "Останнє додане", german: "Zuletzt hinzugefügt").value(for: language))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
        case let .recent(item):
            DirectoryRecentDestinationView(item: item, feedbackRepository: feedbackRepository)
        case .manage:
            if contentStore.canEdit { DirectoryManagementView() }
        case let .edit(categoryID):
            if contentStore.canEdit, let category = contentStore.category(categoryID) {
                DirectoryCategoryEditorView(category: category,
                                            expectedRevision: contentStore.revision(categoryID))
            }
        case let .editTopic(categoryID, topicID):
            if contentStore.canEdit, let category = contentStore.category(categoryID),
               category.topics.contains(where: { $0.id == topicID }) {
                DirectoryCategoryEditorView(category: category,
                                            expectedRevision: contentStore.revision(categoryID),
                                            focusTopicID: topicID)
            }
        case let .create(placement):
            if contentStore.canEdit {
                DirectoryCategoryEditorView(category: nil, newPlacement: placement,
                                            newOrder: DirectoryEditorOrdering.nextOrder(
                                                in: placement, categories: contentStore.allManagedCategories))
            }
        case let .category(id):
            if let category = contentStore.categories.first(where: { $0.id == id }) {
                if contentStore.published[id] != nil || DirectoryTopicGroups.isComplete(categoryID: id) {
                    DirectoryGuideCategoryView(category: category)
                } else {
                    DirectoryCategoryView(category: category)
                }
            }
        case let .topic(categoryID, topicID):
            if let topic = contentStore.categories.first(where: { $0.id == categoryID })?.topics.first(where: { $0.id == topicID }) {
                if let managed = contentStore.managedTopic(categoryID: categoryID, topicID: topicID) {
                    DirectoryManagedTopicView(categoryID: categoryID, topic: managed,
                                              selectedFederalState: $selectedFederalState,
                                              feedbackRepository: feedbackRepository)
                } else if categoryID == "safety", let guide = DirectorySafetyContent.guides[topicID] {
                    DirectorySafetyTopicView(topic: topic, guide: guide,
                                             selectedFederalState: $selectedFederalState, feedbackRepository: feedbackRepository)
                } else if let guide = DirectoryGuideCatalog.guide(categoryID: categoryID, topicID: topicID) {
                    DirectoryGuideTopicView(categoryID: categoryID, topic: topic, guide: guide,
                                            selectedFederalState: $selectedFederalState, feedbackRepository: feedbackRepository)
                } else {
                    DirectoryTopicView(topic: topic, categoryID: categoryID, feedbackRepository: feedbackRepository)
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
        async let banner: Void = featuredBannerViewModel.refresh(for: .directory, federalState: selectedFederalState)
        async let recent: Void = recentAdditions.load(reset: true)
        _ = await (banner, recent)
    }
}
