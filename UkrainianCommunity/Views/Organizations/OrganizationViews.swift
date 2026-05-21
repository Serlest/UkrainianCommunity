import Combine
import PhotosUI
import SwiftUI

enum OrganizationPresentationMode {
    case `public`
    case management

    var allowsManagementControls: Bool {
        self == .management
    }
}

private func organizationActivityDateText(for item: OrganizationActivityItem) -> String {
    LocalizationStore.dateString(from: item.publishedAt, dateStyle: .medium, timeStyle: .short)
}

private func organizationActivityEventText(for item: OrganizationActivityItem) -> String? {
    guard let eventStartDate = item.eventStartDate else { return nil }
    return LocalizationStore.dateString(from: eventStartDate, dateStyle: .medium, timeStyle: .short)
}

private func organizationActivityLocationText(for item: OrganizationActivityItem) -> String? {
    if let city = item.city, !city.isEmpty {
        if let venue = item.eventVenue, !venue.isEmpty {
            return "\(city) • \(venue)"
        }
        return city
    }
    return nil
}

private func organizationContactText(for organization: Organization) -> String? {
    guard let contactEmail = organization.contactEmail, !contactEmail.isEmpty else { return nil }
    return contactEmail
}

private func organizationWebsiteText(for organization: Organization) -> String? {
    guard let website = organization.website, !website.isEmpty else { return nil }
    return website
}

private enum OrganizationCategoryFilter: CaseIterable, Identifiable {
    case all
    case support
    case education
    case culture
    case work
    case children
    case other

    var id: Self { self }

    var title: String {
        switch self {
        case .all:
            AppStrings.Home.filterAll
        case .support:
            AppStrings.Organizations.categorySupport
        case .education:
            AppStrings.Organizations.categoryEducation
        case .culture:
            AppStrings.Organizations.categoryCulture
        case .work:
            AppStrings.Organizations.categoryWork
        case .children:
            AppStrings.Organizations.categoryChildren
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
        case .education:
            "graduationcap"
        case .culture:
            "paintpalette"
        case .work:
            "briefcase"
        case .children:
            "figure.2.and.child.holdinghands"
        case .other:
            "ellipsis"
        }
    }
}

@MainActor
private final class OrganizationActivityViewModel: ObservableObject {
    @Published private(set) var items: [OrganizationActivityItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: AppError?

    private let organizationID: String
    private let organizationName: String
    private let newsRepository: NewsRepository
    private let eventRepository: EventRepository
    private var hasLoaded = false
    private var loadTask: Task<Void, Never>?

    init(
        organizationID: String,
        organizationName: String,
        newsRepository: NewsRepository,
        eventRepository: EventRepository
    ) {
        self.organizationID = organizationID
        self.organizationName = organizationName
        self.newsRepository = newsRepository
        self.eventRepository = eventRepository
    }

    func loadIfNeeded(for organization: Organization) async {
        guard !hasLoaded else { return }
        await startLoad(for: organization, force: false)
    }

    func refresh(for organization: Organization) async {
        await startLoad(for: organization, force: true)
    }

    private func startLoad(for organization: Organization, force: Bool) async {
        guard force || !hasLoaded else { return }

        if let loadTask {
            await loadTask.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoad(for: organization)
        }
        loadTask = task
        await task.value
        self.loadTask = nil
    }

    private func performLoad(for organization: Organization) async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let newsLoad = newsRepository.fetchNews()
            async let eventsLoad = eventRepository.fetchEvents()

            let filteredNews = try await newsLoad
                .filter { $0.source.organizationId == organizationID }
                .map(OrganizationActivityItem.init(post:))
            let filteredEvents = try await eventsLoad
                .filter { $0.source.organizationId == organizationID }
                .map(OrganizationActivityItem.init(event:))

            guard !Task.isCancelled else { return }

            let profileItem = OrganizationActivityItem(profile: organization)
            items = ([profileItem] + filteredNews + filteredEvents)
                .sorted { $0.publishedAt > $1.publishedAt }
            error = nil
            hasLoaded = true
        } catch is CancellationError {
        } catch let appError as AppError {
            guard !Task.isCancelled else { return }
            error = appError
        } catch {
            guard !Task.isCancelled else { return }
            self.error = .unknown
        }
    }

    var isEmptyStateWithoutProfile: Bool {
        items.filter { $0.itemType != .organizationProfile }.isEmpty
    }
}

struct OrganizationsListView: View {
    @EnvironmentObject private var authState: AuthState
    @ObservedObject var viewModel: OrganizationsViewModel
    @StateObject private var heroBannerViewModel: AppHeroBannerViewModel
    let onOrganizationSaved: @MainActor () async -> Void
    let onOrganizationDeleted: @MainActor () -> Void
    let presentationMode: OrganizationPresentationMode
    @State private var pendingDeleteOrganizationID: String?
    @State private var deleteErrorMessage: String?
    @State private var isShowingDeleteError = false
    @State private var isShowingCreateSheet = false
    @State private var selectedCategory: OrganizationCategoryFilter = .all
    @State private var selectedBannerPhoto: PhotosPickerItem?

    init(
        viewModel: OrganizationsViewModel,
        bannerService: HomeBannerServiceProtocol = FirestoreHomeBannerService(),
        onOrganizationSaved: @escaping @MainActor () async -> Void = {},
        onOrganizationDeleted: @escaping @MainActor () -> Void = {},
        presentationMode: OrganizationPresentationMode = .public
    ) {
        self.viewModel = viewModel
        self.onOrganizationSaved = onOrganizationSaved
        self.onOrganizationDeleted = onOrganizationDeleted
        self.presentationMode = presentationMode
        _heroBannerViewModel = StateObject(wrappedValue: AppHeroBannerViewModel(
            section: .organizations,
            bannerService: bannerService
        ))
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

    private var canCreateOrganization: Bool {
        presentationMode.allowsManagementControls && PermissionService.canCreateOrganization(user: authState.user)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.eventsHeaderContentSpacing) {
                organizationsHeader

                organizationsHero

                OrganizationCategoriesSection(selectedCategory: $selectedCategory)

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
                await updateOrganizationsBanner(from: newItem)
                selectedBannerPhoto = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .organizationsChanged).debounce(for: .milliseconds(250), scheduler: RunLoop.main)) { _ in
            Task {
                await viewModel.refresh()
            }
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
        .sheet(isPresented: $isShowingCreateSheet) {
            NavigationStack {
                OrganizationEditorView(
                    organizationsViewModel: viewModel,
                    onSaved: onOrganizationSaved
                )
            }
            .environmentObject(authState)
        }
    }

    private var organizationsHeader: some View {
        AppBrandHeader {
            HStack(spacing: 8) {
                if canCreateOrganization {
                    AppIconControlButton(systemImage: "plus", accessibilityLabel: AppStrings.Action.create) {
                        isShowingCreateSheet = true
                    }
                    .accessibilityHint(AppStrings.Organizations.title)
                }

                AppNotificationBellButton()
            }
        }
    }

    private var organizationsHero: some View {
        ZStack(alignment: .bottomTrailing) {
            AppHeroBanner(
                title: AppStrings.Organizations.heroTitle,
                subtitle: AppStrings.Organizations.heroSubtitle,
                imageSource: heroBannerViewModel.imageSource,
                height: AppTheme.organizationsHeroHeight,
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

    private func updateOrganizationsBanner(from item: PhotosPickerItem?) async {
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
    private var organizationsPlaneContent: some View {
        if viewModel.organizations.isEmpty && viewModel.isLoading {
            LoadingStateCard(title: nil)
                .frame(maxWidth: .infinity, minHeight: 320)
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
            .frame(maxWidth: .infinity, minHeight: 320)
        } else if viewModel.organizations.isEmpty {
            EmptyStateCard(
                systemImage: "building.2",
                title: AppStrings.Organizations.title,
                message: AppStrings.Organizations.empty
            )
            .frame(maxWidth: .infinity, minHeight: 320)
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

                DashboardFeedContainer(items: viewModel.organizations, spacing: AppTheme.feedRowSpacing) { organization in
                    organizationLink(for: organization)
                }
            }
        }
    }

    private func organizationLink(for organization: Organization) -> some View {
        NavigationLink {
            OrganizationDetailView(
                viewModel: viewModel,
                organizationID: organization.id,
                onOrganizationSaved: onOrganizationSaved,
                onOrganizationDeleted: onOrganizationDeleted
            )
            .environment(\.organizationPresentationMode, presentationMode)
        } label: {
            OrganizationCard(organization: organization)
        }
        .buttonStyle(.plain)
        .modifier(OrganizationDeleteSwipeActions(
            isEnabled: presentationMode.allowsManagementControls && PermissionService.canDeleteOrganization(user: authState.user),
            onDelete: {
                pendingDeleteOrganizationID = organization.id
            }
        ))
    }
}

private func readableOrganizationErrorText(_ error: AppError?) -> String {
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
                    size: AppTheme.organizationsThumbnailSize,
                    cornerRadius: AppTheme.feedThumbnailRadius,
                    source: "OrganizationCard"
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(organization.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)

                    Text(organization.description)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary.opacity(0.82))
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        AppInfoChip(
                            title: organization.city,
                            systemImage: "mappin.and.ellipse",
                            tint: AppTheme.textSecondary,
                            fill: AppTheme.surfaceControl.opacity(0.62),
                            size: .small
                        )

                        AppInfoChip(
                            title: organization.moderationStatus.title,
                            systemImage: "checkmark.shield",
                            tint: AppTheme.textSecondary,
                            fill: AppTheme.surfaceControl.opacity(0.62),
                            size: .small
                        )
                    }
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 14) {
                    Image(systemName: "bookmark")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary.opacity(0.72))

                    HStack(spacing: 4) {
                        Image(systemName: "person.2")
                            .font(.caption.weight(.medium))

                        Text(compactLikeCount)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                    }
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.82))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        [
            organization.name,
            organization.description,
            organization.city,
            organization.moderationStatus.title,
            "\(organization.likeCount) \(AppStrings.Common.likes)"
        ]
        .filter { !$0.isEmpty }
        .joined(separator: ", ")
    }

    private var compactLikeCount: String {
        if organization.likeCount >= 1_000 {
            String(format: "%.1fK", Double(organization.likeCount) / 1_000)
        } else {
            "\(organization.likeCount)"
        }
    }
}

private struct OrganizationCategoriesSection: View {
    @Binding var selectedCategory: OrganizationCategoryFilter

    var body: some View {
        AppHorizontalFilterRow {
            ForEach(OrganizationCategoryFilter.allCases) { category in
                Button {
                    selectedCategory = category
                } label: {
                    AppFilterChip(
                        title: category.title,
                        systemImage: category.systemImage,
                        isSelected: selectedCategory == category
                    )
                }
                .buttonStyle(.plain)

                if category == .all {
                    AppFilterChip(
                        title: AppStrings.Home.regionAllAustria,
                        systemImage: "mappin.and.ellipse",
                        trailingSystemImage: "chevron.down"
                    )
                }
            }
        }
    }
}

struct OrganizationDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.organizationPresentationMode) private var presentationMode
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var authState: AuthState
    @ObservedObject var viewModel: OrganizationsViewModel
    let organizationID: String
    let onOrganizationSaved: @MainActor () async -> Void
    let onOrganizationDeleted: @MainActor () -> Void
    @State private var showDeleteConfirmation = false
    @State private var deleteErrorMessage: String?
    @State private var isShowingEditSheet = false
    @State private var isShowingCreateNewsSheet = false
    @State private var isShowingCreateEventSheet = false
    @State private var pendingRemovalOrganizationID: String?
    @State private var guestAccessAction: GuestAccessAction?
    @State private var isAboutExpanded = false
    @StateObject private var activityViewModel: OrganizationActivityViewModel
    private let newsRepository: NewsRepository
    private let eventRepository: EventRepository

    init(
        viewModel: OrganizationsViewModel,
        organizationID: String,
        newsRepository: NewsRepository = FirestoreNewsRepository(),
        eventRepository: EventRepository = FirestoreEventRepository(),
        onOrganizationSaved: @escaping @MainActor () async -> Void = {},
        onOrganizationDeleted: @escaping @MainActor () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.organizationID = organizationID
        self.newsRepository = newsRepository
        self.eventRepository = eventRepository
        self.onOrganizationSaved = onOrganizationSaved
        self.onOrganizationDeleted = onOrganizationDeleted
        _activityViewModel = StateObject(wrappedValue: OrganizationActivityViewModel(
            organizationID: organizationID,
            organizationName: "",
            newsRepository: newsRepository,
            eventRepository: eventRepository
        ))
    }

    @ViewBuilder
    private var editSheetContent: some View {
        if let organization = viewModel.organization(for: organizationID) {
            NavigationStack {
                OrganizationEditorView(
                    organizationsViewModel: viewModel,
                    organization: organization,
                    onSaved: onOrganizationSaved
                )
            }
            .environmentObject(authState)
        }
    }

    private var canCreateOrganizationNews: Bool {
        presentationMode.allowsManagementControls && PermissionService.canCreateNews(for: organizationID, user: authState.user)
    }

    private var canCreateOrganizationEvent: Bool {
        PermissionService.canCreateEvent(for: organizationID, user: authState.user)
    }

    private var canEditOrganization: Bool {
        presentationMode.allowsManagementControls && PermissionService.canEditOrganization(organizationId: organizationID, user: authState.user)
    }

    private var canDeleteOrganization: Bool {
        presentationMode.allowsManagementControls && PermissionService.canDeleteOrganization(user: authState.user)
    }

    var body: some View {
        Group {
            if let organization = viewModel.organization(for: organizationID) {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                        detailHeader
                            .padding(.top, AppTheme.dashboardSpacing)

                        organizationHero(for: organization)
                        actionButtons(for: organization)
                        aboutCard(for: organization)
                        managementCard
                        organizationTabs
                        activitySection(for: organization)
                    }
                    .padding(.horizontal, AppTheme.pageHorizontal)
                    .padding(.bottom, AppTheme.homeBottomContentPadding)
                }
                .background(AppBackgroundView())
                .navigationBarBackButtonHidden(true)
                .toolbar(.hidden, for: .navigationBar)
                .task(id: organization.id) {
                    await activityViewModel.loadIfNeeded(for: organization)
                }
            } else {
                EmptyStateView(title: AppStrings.Common.noItems)
            }
        }
        .confirmationDialog(AppStrings.Organizations.deleteConfirmation, isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button(AppStrings.Organizations.delete, role: .destructive) {
                Task {
                    await deleteCurrentOrganization()
                }
            }
            Button(AppStrings.Organizations.cancel, role: .cancel) {}
        }
        .alert(AppStrings.Organizations.deleteFailed, isPresented: Binding(
            get: { deleteErrorMessage != nil },
            set: { if !$0 { deleteErrorMessage = nil } }
        )) {
            Button(AppStrings.Organizations.dismissError, role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "")
        }
        .sheet(isPresented: $isShowingEditSheet) {
            editSheetContent
        }
        .sheet(isPresented: $isShowingCreateNewsSheet) {
            if let organization = viewModel.organization(for: organizationID) {
                NavigationStack {
                    NewsEditorView(
                        repository: newsRepository,
                        organizationId: organization.id,
                        organizationName: organization.name,
                        organizationImageURL: organization.imageURL,
                        organizationFederalState: organization.federalState
                    ) {}
                }
                .environmentObject(authState)
            }
        }
        .sheet(isPresented: $isShowingCreateEventSheet) {
            if let organization = viewModel.organization(for: organizationID) {
                NavigationStack {
                    EventEditorView(
                        repository: eventRepository,
                        organizationId: organization.id,
                        organizationName: organization.name,
                        organizationImageURL: organization.imageURL,
                        organizationFederalState: organization.federalState
                    ) {}
                }
            }
        }
        .guestAccessAlert($guestAccessAction)
        .onReceive(NotificationCenter.default.publisher(for: .organizationsChanged).debounce(for: .milliseconds(250), scheduler: RunLoop.main)) { notification in
            guard AppContentChangeBus.organizationID(from: notification) == organizationID else { return }
            Task {
                await viewModel.refresh()
                if let organization = viewModel.organization(for: organizationID) {
                    await activityViewModel.refresh(for: organization)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newsChanged).debounce(for: .milliseconds(250), scheduler: RunLoop.main)) { notification in
            guard AppContentChangeBus.organizationID(from: notification) == organizationID else { return }
            guard let organization = viewModel.organization(for: organizationID) else { return }
            Task {
                await activityViewModel.refresh(for: organization)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .eventsChanged).debounce(for: .milliseconds(250), scheduler: RunLoop.main)) { notification in
            guard AppContentChangeBus.organizationID(from: notification) == organizationID else { return }
            guard let organization = viewModel.organization(for: organizationID) else { return }
            Task {
                await activityViewModel.refresh(for: organization)
            }
        }
        .onDisappear {
            guard let pendingRemovalOrganizationID else { return }
            withTransaction(Transaction(animation: nil)) {
                viewModel.removeDeletedOrganization(id: pendingRemovalOrganizationID)
            }
            self.pendingRemovalOrganizationID = nil
        }
    }

    private var detailHeader: some View {
        AppCenteredBrandHeader {
            AppGlassIconButton(systemImage: "chevron.left", accessibilityLabel: AppStrings.Common.back) {
                dismiss()
            }
        } trailingContent: {
            HStack(spacing: AppTheme.eventsControlGroupSpacing) {
                AppGlassIconButton(systemImage: "square.and.arrow.up", accessibilityLabel: AppStrings.Action.share, isPlaceholder: true)
                AppGlassIconButton(systemImage: "bookmark", accessibilityLabel: AppStrings.Action.save, isPlaceholder: true)
            }
        }
    }

    private func organizationHero(for organization: Organization) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: AppTheme.sectionSpacing) {
                organizationLogo(for: organization)
                    .frame(width: 132, height: 132)

                heroText(for: organization)
            }

            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                organizationLogo(for: organization)
                    .frame(width: 132, height: 132)

                heroText(for: organization)
            }
        }
    }

    private func organizationLogo(for organization: Organization) -> some View {
        Group {
            if organization.imageURL != nil {
                RemoteImageView(
                    imageURL: organization.imageURL,
                    height: 132,
                    cornerRadius: AppTheme.imageRadius,
                    source: "OrganizationDetailView",
                    placeholderStyle: .glassSkeleton
                )
            } else {
                RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous)
                    .fill(AppTheme.glassControlSurface(for: colorScheme))
                    .overlay(
                        Text(organizationInitials(for: organization))
                            .font(.title.weight(.bold))
                            .foregroundStyle(AppTheme.accentPrimary)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous)
                            .strokeBorder(AppTheme.glassBorder(for: colorScheme))
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous))
        .accessibilityLabel(AppStrings.Organizations.imageSectionTitle)
    }

    private func heroText(for organization: Organization) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
            AppInfoChip(
                title: AppStrings.Organizations.detailBadge.uppercased(),
                systemImage: "building.2",
                tint: Color.purple,
                fill: AppTheme.badgePurpleFill,
                size: .small
            )

            Text(organization.name)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Text(organization.description)
                .font(.body.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            metadataRow(for: organization)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metadataRow(for organization: Organization) -> some View {
        AppHorizontalFilterRow {
            ContentMetadataPill(systemImage: "mappin.and.ellipse", text: organization.city)

            if let website = organizationWebsiteText(for: organization) {
                ContentMetadataPill(systemImage: "globe", text: website)
            }

            if let contactEmail = organizationContactText(for: organization) {
                ContentMetadataPill(systemImage: "envelope", text: contactEmail)
            }
        }
    }

    private func actionButtons(for organization: Organization) -> some View {
        AppHorizontalFilterRow {
            organizationActionButton(
                title: AppStrings.Organizations.follow,
                systemImage: "person.2.badge.plus",
                isPlaceholder: true
            )

            organizationActionButton(
                title: AppStrings.Organizations.message,
                systemImage: "message",
                isPlaceholder: true
            )

            organizationActionButton(
                title: AppStrings.Organizations.share,
                systemImage: "square.and.arrow.up",
                isPlaceholder: true
            )

            organizationActionButton(
                title: AppStrings.Organizations.support,
                systemImage: organization.likeState.isLiked ? "heart.fill" : "heart",
                isPrimary: false,
                isDisabled: viewModel.pendingOrganizationLikeIDs.contains(organization.id)
            ) {
                guard authState.isAuthenticated else {
                    guestAccessAction = .likes
                    return
                }

                viewModel.toggleLike(for: organization.id)
            }
            .accessibilityIdentifier("organization.like.\(organization.id)")
            .accessibilityLabel(organization.likeState.isLiked ? AppStrings.Action.unlike : AppStrings.Action.like)
            .accessibilityHint(AppStrings.Common.likes)
        }
    }

    private func organizationActionButton(
        title: String,
        systemImage: String,
        isPrimary: Bool = false,
        isPlaceholder: Bool = false,
        isDisabled: Bool = false,
        action: @escaping () -> Void = {}
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isPrimary && !isPlaceholder ? .white : AppTheme.textPrimary)
                .padding(.horizontal, AppTheme.dashboardSpacing)
                .frame(height: AppTheme.iconButtonSize)
                .background(
                    isPrimary && !isPlaceholder ? AppTheme.accentPrimary : AppTheme.glassControlSurface(for: colorScheme),
                    in: RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
                        .strokeBorder(isPrimary && !isPlaceholder ? AppTheme.accentPrimary.opacity(0.15) : AppTheme.glassBorder(for: colorScheme))
                )
        }
        .buttonStyle(.plain)
        .disabled(isPlaceholder || isDisabled)
        .opacity(isPlaceholder || isDisabled ? 0.58 : 1)
        .accessibilityHint(isPlaceholder ? AppStrings.Action.comingSoon : "")
    }

    private func aboutCard(for organization: Organization) -> some View {
        AppEditorSectionCard {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: AppTheme.sectionSpacing) {
                    aboutText(for: organization)
                    organizationInfoBlock(for: organization)
                        .frame(width: 220)
                }

                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    aboutText(for: organization)
                    organizationInfoBlock(for: organization)
                }
            }
        }
    }

    private func aboutText(for organization: Organization) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
            AppEditorSectionTitle(title: AppStrings.Organizations.aboutSectionTitle)

            Text(organization.description)
                .font(.body)
                .foregroundStyle(AppTheme.textSecondary)
                .lineSpacing(4)
                .lineLimit(isAboutExpanded ? nil : 5)
                .fixedSize(horizontal: false, vertical: true)

            if organization.description.count > 180 {
                Button {
                    withAnimation(.snappy) {
                        isAboutExpanded.toggle()
                    }
                } label: {
                    Label(AppStrings.Organizations.showMore, systemImage: "chevron.down")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.accentPrimary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func organizationInfoBlock(for organization: Organization) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
            ContentMetadataPill(systemImage: "mappin.and.ellipse", text: organization.city)

            if let website = organizationWebsiteText(for: organization) {
                ContentMetadataPill(systemImage: "globe", text: website)
            }

            if let contactEmail = organizationContactText(for: organization) {
                ContentMetadataPill(systemImage: "envelope", text: contactEmail)
            }
        }
        .padding(AppTheme.dashboardSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.glassControlSurface(for: colorScheme), in: RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous))
    }

    @ViewBuilder
    private var managementCard: some View {
        if canEditOrganization || canDeleteOrganization || canCreateOrganizationNews || canCreateOrganizationEvent {
            AppEditorSectionCard {
                VStack(spacing: AppTheme.eventsMetadataSpacing) {
                    if canEditOrganization {
                        organizationManagementButton(title: AppStrings.Action.edit, systemImage: "pencil") {
                            isShowingEditSheet = true
                        }
                    }

                    if canCreateOrganizationNews {
                        organizationManagementButton(title: AppStrings.NewsEditor.title, systemImage: "newspaper") {
                            isShowingCreateNewsSheet = true
                        }
                    }

                    if canCreateOrganizationEvent {
                        organizationManagementButton(title: AppStrings.Events.editorTitle, systemImage: "calendar.badge.plus") {
                            isShowingCreateEventSheet = true
                        }
                    }

                    if canDeleteOrganization {
                        organizationManagementButton(title: AppStrings.Action.delete, systemImage: "trash", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                        .disabled(viewModel.pendingOrganizationDeleteIDs.contains(organizationID))
                    }
                }
            }
        }
    }

    private func organizationManagementButton(
        title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            DetailActionRow {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(role == .destructive ? AppTheme.accentDestructive : AppTheme.textPrimary)
            } trailingContent: {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var organizationTabs: some View {
        AppHorizontalFilterRow {
            AppFilterChip(title: AppStrings.Organizations.tabEvents, systemImage: "calendar", isSelected: true)
            disabledTab(title: AppStrings.Organizations.tabAbout, systemImage: "info.bubble")
            disabledTab(title: AppStrings.Organizations.tabNews, systemImage: "newspaper")
            disabledTab(title: AppStrings.Organizations.tabPhoto, systemImage: "photo")
            disabledTab(title: AppStrings.Organizations.tabTeam, systemImage: "person.2")
        }
    }

    private func disabledTab(title: String, systemImage: String) -> some View {
        AppFilterChip(title: title, systemImage: systemImage)
            .opacity(0.55)
            .accessibilityHint(AppStrings.Action.comingSoon)
    }

    private func activitySection(for organization: Organization) -> some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                HStack {
                    AppEditorSectionTitle(title: AppStrings.Organizations.upcomingEventsTitle)

                    Spacer(minLength: AppTheme.eventsMetadataSpacing)

                }

                if activityViewModel.isLoading && activityViewModel.items.isEmpty {
                    LoadingStateCard(title: nil)
                } else if activityViewModel.items.isEmpty && activityViewModel.error != nil {
                    ErrorStateCard(
                        systemImage: "building.2",
                        title: AppStrings.Organizations.activityTitle,
                        message: readableOrganizationErrorText(activityViewModel.error),
                        retryTitle: AppStrings.Organizations.retry
                    ) {
                        Task {
                            await activityViewModel.refresh(for: organization)
                        }
                    }
                } else {
                    let eventItems = activityViewModel.items.filter { $0.itemType == .event }

                    if eventItems.isEmpty {
                        EmptyStateCard(
                            systemImage: "calendar",
                            title: AppStrings.Organizations.upcomingEventsTitle,
                            message: AppStrings.Organizations.empty
                        )
                    } else {
                        ForEach(eventItems) { item in
                            if let destination = item.destination {
                                NavigationLink {
                                    activityDestinationView(for: destination)
                                } label: {
                                    OrganizationActivityCard(item: item)
                                }
                                .buttonStyle(.plain)
                            } else {
                                OrganizationActivityCard(item: item)
                            }
                        }
                    }
                }
            }
        }
    }

    private func organizationInitials(for organization: Organization) -> String {
        let words = organization.name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        let initials = String(words).uppercased()
        return initials.isEmpty ? "UC" : initials
    }

    @MainActor
    private func deleteCurrentOrganization() async {
        do {
            try await viewModel.deleteOrganization(id: organizationID, user: authState.user)
            pendingRemovalOrganizationID = organizationID
            dismiss()
            onOrganizationDeleted()
        } catch let appError as AppError {
            deleteErrorMessage = readableOrganizationErrorText(appError)
        } catch {
            deleteErrorMessage = readableOrganizationErrorText(.unknown)
        }
    }

    @ViewBuilder
    private func activityDestinationView(for destination: HomeFeedDestinationReference) -> some View {
        switch destination {
        case let .news(id):
            NewsDetailView(
                viewModel: NewsViewModel(repository: FirestoreNewsRepository()),
                postID: id,
                onNewsDeleted: {}
            )
        case let .event(id):
            EventDetailView(
                viewModel: EventsViewModel(repository: FirestoreEventRepository()),
                eventID: id,
                onEventDeleted: {}
            )
        case let .organization(id):
            OrganizationDetailView(
                viewModel: viewModel,
                organizationID: id,
                onOrganizationSaved: onOrganizationSaved,
                onOrganizationDeleted: onOrganizationDeleted
            )
            .environment(\.organizationPresentationMode, presentationMode)
        }
    }
}

private struct OrganizationActivityCard: View {
    let item: OrganizationActivityItem

    var body: some View {
        CommunityCard {
            if item.imageURL != nil {
                RemoteCardImage(imageURL: item.imageURL, height: 160, source: "OrganizationActivityCard", isDecorative: true)
            }

            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        ContentMetadataPill(systemImage: itemTypeSystemImage, text: itemTypeTitle)
                        ContentMetadataPill(systemImage: "calendar", text: organizationActivityDateText(for: item))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ContentMetadataPill(systemImage: itemTypeSystemImage, text: itemTypeTitle)
                        ContentMetadataPill(systemImage: "calendar", text: organizationActivityDateText(for: item))
                    }
                }

                Text(item.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(item.summary)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let eventText = organizationActivityEventText(for: item) {
                    ContentMetadataPill(systemImage: "clock", text: eventText)
                }

                if let locationText = organizationActivityLocationText(for: item) {
                    ContentMetadataPill(systemImage: "mappin.and.ellipse", text: locationText)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var itemTypeTitle: String {
        switch item.itemType {
        case .news:
            AppStrings.News.title
        case .event:
            AppStrings.Tabs.events
        case .organizationProfile:
            AppStrings.Tabs.organizations
        }
    }

    private var itemTypeSystemImage: String {
        switch item.itemType {
        case .news:
            "newspaper"
        case .event:
            "calendar"
        case .organizationProfile:
            "building.2"
        }
    }

    private var accessibilitySummary: String {
        var parts = [itemTypeTitle, item.title, item.summary, organizationActivityDateText(for: item)]

        if let eventText = organizationActivityEventText(for: item) {
            parts.append(eventText)
        }

        if let locationText = organizationActivityLocationText(for: item) {
            parts.append(locationText)
        }

        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
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

private struct OrganizationPresentationModeKey: EnvironmentKey {
    static let defaultValue: OrganizationPresentationMode = .public
}

extension EnvironmentValues {
    var organizationPresentationMode: OrganizationPresentationMode {
        get { self[OrganizationPresentationModeKey.self] }
        set { self[OrganizationPresentationModeKey.self] = newValue }
    }
}

#Preview("Organizations List") {
    NavigationStack {
        OrganizationsListView(
            viewModel: OrganizationsViewModel(repository: MockOrganizationRepository()),
            presentationMode: .management
        )
    }
    .environmentObject(AuthState())
}

#Preview("Organization Detail") {
    NavigationStack {
        OrganizationDetailView(
            viewModel: OrganizationsViewModel(repository: MockOrganizationRepository()),
            organizationID: MockContentBuilder.organizations().first!.id,
            newsRepository: MockNewsRepository(),
            eventRepository: MockEventRepository()
        )
        .environment(\.organizationPresentationMode, .management)
    }
    .environmentObject(AuthState())
}
