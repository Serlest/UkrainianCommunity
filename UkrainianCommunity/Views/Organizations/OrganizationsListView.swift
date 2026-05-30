import Combine
import MapKit
import SwiftUI

struct OrganizationNavigationRoute: Hashable {
    let organizationID: String
}

enum OrganizationCategoryFilter: CaseIterable, Identifiable {
    case all
    case support
    case integration
    case culture
    case education
    case other

    var id: Self { self }

    static var selectableCases: [OrganizationCategoryFilter] {
        [.support, .integration, .culture, .education, .other]
    }

    var title: String {
        switch self {
        case .all:
            AppStrings.Home.filterAll
        case .support:
            AppStrings.Organizations.categorySupport
        case .integration:
            AppStrings.Organizations.categoryIntegration
        case .culture:
            AppStrings.Organizations.categoryCulture
        case .education:
            AppStrings.Organizations.categoryEducation
        case .other:
            AppStrings.Organizations.categoryOther
        }
    }

    var systemImage: String? {
        switch self {
        case .all:
            "square.grid.2x2"
        case .support:
            "hands.sparkles"
        case .integration:
            "person.2"
        case .culture:
            "paintpalette"
        case .education:
            "graduationcap"
        case .other:
            "ellipsis"
        }
    }

    func matches(_ organization: Organization) -> Bool {
        guard !organization.isSystemOrganization else {
            return self == .all
        }

        guard self != .all else { return true }
        return organization.organizationType == categoryRawValue
    }

    private var categoryRawValue: String? {
        switch self {
        case .all:
            nil
        case .support:
            "support"
        case .integration:
            "integration"
        case .culture:
            "culture"
        case .education:
            "education"
        case .other:
            "other"
        }
    }
}

private enum OrganizationSavedFilterMode {
    case none
    case subscribed
    case bookmarked
}

struct OrganizationsListView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var authState: AuthState
    @ObservedObject var viewModel: OrganizationsViewModel
    @StateObject private var featuredBannerViewModel: FeaturedBannerListViewModel
    @Binding var navigationPath: [OrganizationNavigationRoute]
    let onOrganizationSaved: @MainActor () async -> Void
    let onOrganizationDeleted: @MainActor () -> Void
    let presentationMode: OrganizationPresentationMode
    @State private var pendingDeleteOrganizationID: String?
    @State private var deleteErrorMessage: String?
    @State private var isShowingDeleteError = false
    @State private var selectedCategory: OrganizationCategoryFilter = .all
    @State private var selectedFederalState: AustrianFederalState?
    @State private var savedFilterMode: OrganizationSavedFilterMode = .none
    @State private var didManuallyChangeRegion = false
    @State private var isRegionPickerPresented = false
    private let featuredBannerActionResolver = FeaturedBannerActionResolver()

    init(
        viewModel: OrganizationsViewModel,
        featuredBannerRepository: FeaturedBannerRepository = FirestoreFeaturedBannerRepository(),
        navigationPath: Binding<[OrganizationNavigationRoute]> = .constant([]),
        onOrganizationSaved: @escaping @MainActor () async -> Void = {},
        onOrganizationDeleted: @escaping @MainActor () -> Void = {},
        presentationMode: OrganizationPresentationMode = .public
    ) {
        self.viewModel = viewModel
        self.onOrganizationSaved = onOrganizationSaved
        self.onOrganizationDeleted = onOrganizationDeleted
        self.presentationMode = presentationMode
        _featuredBannerViewModel = StateObject(wrappedValue: FeaturedBannerListViewModel(repository: featuredBannerRepository))
        _navigationPath = navigationPath
    }

    private var featuredBannerLoadKey: String {
        authState.user?.selectedFederalState?.rawValue ?? "allAustria"
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
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                organizationsHeader
                    .padding(.bottom, AppTheme.homeHeaderHeroSpacing)

                organizationsHero
                    .padding(.bottom, featuredBannerViewModel.banners.isEmpty ? 0 : AppTheme.homeSectionSpacing)

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
        }
        .background(AppBackgroundView())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: OrganizationNavigationRoute.self) { route in
            OrganizationDetailView(
                viewModel: viewModel,
                organizationID: route.organizationID,
                onOrganizationSaved: onOrganizationSaved,
                onOrganizationDeleted: onOrganizationDeleted
            )
            .environment(\.organizationPresentationMode, presentationMode)
        }
        .task(id: featuredBannerLoadKey) {
            applyDefaultRegion()
            await viewModel.loadIfNeeded()
            await viewModel.refreshIfStale()
            await loadFeaturedBanners()
        }
        .refreshable {
            await viewModel.refresh()
            await loadFeaturedBanners()
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
        .confirmationDialog(AppStrings.Home.regionAllAustria, isPresented: $isRegionPickerPresented, titleVisibility: .visible) {
            Button(AppStrings.Home.regionAllAustria) {
                selectRegion(nil)
            }

            ForEach(AustrianFederalState.organizationFilterOrder, id: \.self) { federalState in
                Button(federalState.organizationFilterDisplayName) {
                    selectRegion(federalState)
                }
            }

            Button(AppStrings.Events.cancel, role: .cancel) {}
        }
        .confirmationDialog(
            AppStrings.Organizations.deleteConfirmation,
            isPresented: Binding(
                get: { pendingDeleteOrganizationID != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeleteOrganizationID = nil
                    }
                }
            )
        ) {
            Button(AppStrings.Organizations.delete, role: .destructive) {
                guard let organizationID = pendingDeleteOrganizationID else { return }
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
            Button(AppStrings.Organizations.cancel, role: .cancel) {
                pendingDeleteOrganizationID = nil
            }
        }
        .alert(AppStrings.Organizations.deleteFailed, isPresented: $isShowingDeleteError) {
            Button(AppStrings.Organizations.dismissError) {
                deleteErrorMessage = nil
            }
        } message: {
            Text(deleteErrorMessage ?? readableOrganizationErrorText(.unknown))
        }
    }

    private var organizationsHeader: some View {
        AppBrandHeader {
            EmptyView()
        }
    }

    @ViewBuilder
    private var organizationsHero: some View {
        if !featuredBannerViewModel.banners.isEmpty {
            FeaturedBannerCarouselView(
                banners: featuredBannerViewModel.banners,
                sizing: .responsiveHero,
                onBannerTap: handleFeaturedBannerTap
            )
        }
    }

    private func loadFeaturedBanners() async {
        await featuredBannerViewModel.loadActiveBanners(
            for: .organizations,
            federalState: authState.user?.selectedFederalState
        )
    }

    private func handleFeaturedBannerTap(_ banner: FeaturedBanner) {
        switch featuredBannerActionResolver.resolve(banner) {
        case .noAction, .openNews, .openEvent, .openGuide:
            return
        case let .openURL(url):
            openURL(url)
        case let .openOrganization(id):
            guard viewModel.organizations.contains(where: { $0.id == id }) else { return }
            navigationPath.append(OrganizationNavigationRoute(organizationID: id))
        }
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
        } else if filteredOrganizations.isEmpty {
            EmptyStateCard(
                systemImage: "line.3.horizontal.decrease.circle",
                title: AppStrings.Organizations.title,
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

                DashboardSectionHeader(title: AppStrings.Organizations.popularTitle)

                DashboardFeedContainer(items: filteredOrganizations, spacing: AppTheme.feedRowSpacing) { organization in
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
        }
    }

    private var filteredEmptyMessage: String {
        if savedFilterMode == .bookmarked {
            return AppStrings.Organizations.emptyBookmarked
        }
        if savedFilterMode == .subscribed {
            return AppStrings.Home.emptySubscribed
        }
        return AppStrings.Organizations.empty
    }

    private func matchesSelectedRegion(_ organization: Organization) -> Bool {
        guard let selectedFederalState else { return true }
        return organization.federalState == selectedFederalState
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

    var body: some View {
        SoftContentCard(padding: AppTheme.organizationsCardPadding) {
            HStack(alignment: .center, spacing: AppTheme.eventsCardHorizontalSpacing) {
                AppFeedThumbnail(
                    imageURL: organization.imageURL,
                    fallbackSystemImage: "building.2",
                    tint: AppTheme.accentPrimary,
                    fill: AppTheme.badgeBlueFill,
                    size: thumbnailSize,
                    cornerRadius: AppTheme.feedThumbnailRadius,
                    source: "OrganizationCard"
                )
                .frame(width: thumbnailSize, height: thumbnailSize, alignment: .center)

                VStack(alignment: .leading, spacing: AppTheme.eventsCardContentSpacing) {
                    Text(organization.name)
                        .font(AppTheme.cardTitleFont)
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)

                    Text(organization.shortDescription)
                        .font(AppTheme.cardSubtitleFont)
                        .foregroundStyle(AppTheme.textSecondary.opacity(0.82))
                        .lineLimit(2)

                    organizationMetadataChips
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var thumbnailSize: CGFloat {
        AppTheme.organizationsThumbnailSize
    }

    private var organizationMetadataChips: some View {
        AppHorizontalChipRow(spacing: AppTheme.eventsMetadataSpacing) {
            ForEach(metadataItems, id: \.title) { item in
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
    }

    private var metadataItems: [(title: String, systemImage: String)] {
        var items: [(title: String, systemImage: String)] = []

        if let region = regionText {
            items.append((region, "mappin.and.ellipse"))
        }

        items.append((organizationCategoryText, "building.2"))
        return items
    }

    private var accessibilitySummary: String {
        [
            organization.name,
            organization.shortDescription,
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

    var body: some View {
        AppHorizontalFilterRow {
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

            Button(action: onSelectRegion) {
                AppFilterChip(
                    title: selectedFederalState?.organizationFilterDisplayName ?? AppStrings.Home.regionAllAustria,
                    systemImage: "mappin.and.ellipse",
                    isSelected: selectedFederalState != nil,
                    trailingSystemImage: "chevron.down"
                )
            }
            .buttonStyle(.plain)

            Button(action: onToggleSubscribed) {
                AppFilterChip(
                    title: AppStrings.Home.filterSubscribed,
                    systemImage: "person.2.fill",
                    isSelected: savedFilterMode == .subscribed
                )
            }
            .buttonStyle(.plain)

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

    var organizationFilterDisplayName: String {
        switch self {
        case .tirol:
            "Tirol"
        case .wien:
            "Wien"
        case .niederoesterreich:
            "Niederösterreich"
        case .oberoesterreich:
            "Oberösterreich"
        case .salzburg:
            "Salzburg"
        case .steiermark:
            "Steiermark"
        case .kaernten:
            "Kärnten"
        case .vorarlberg:
            "Vorarlberg"
        case .burgenland:
            "Burgenland"
        }
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
