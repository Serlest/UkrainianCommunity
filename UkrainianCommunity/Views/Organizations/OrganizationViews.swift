import Combine
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
    let onOrganizationSaved: @MainActor () async -> Void
    let onOrganizationDeleted: @MainActor () -> Void
    let presentationMode: OrganizationPresentationMode
    @State private var pendingDeleteOrganizationID: String?
    @State private var deleteErrorMessage: String?
    @State private var isShowingDeleteError = false
    @State private var isShowingCreateSheet = false

    init(
        viewModel: OrganizationsViewModel,
        onOrganizationSaved: @escaping @MainActor () async -> Void = {},
        onOrganizationDeleted: @escaping @MainActor () -> Void = {},
        presentationMode: OrganizationPresentationMode = .public
    ) {
        self.viewModel = viewModel
        self.onOrganizationSaved = onOrganizationSaved
        self.onOrganizationDeleted = onOrganizationDeleted
        self.presentationMode = presentationMode
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
        ScrollView {
            if viewModel.organizations.isEmpty && viewModel.isLoading {
                VStack {
                    LoadingStateCard(title: nil)
                }
                .frame(maxWidth: .infinity, minHeight: 420)
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
                .frame(maxWidth: .infinity, minHeight: 420)
            } else if viewModel.organizations.isEmpty {
                EmptyStateCard(
                    systemImage: "building.2",
                    title: AppStrings.Organizations.title,
                    message: AppStrings.Organizations.empty
                )
                .frame(maxWidth: .infinity, minHeight: 420)
            } else {
                VStack(spacing: AppTheme.sectionSpacing) {
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
                        .padding(.horizontal, AppTheme.pageHorizontal)
                    }

                    AdaptiveCardGrid(items: viewModel.organizations) { organization in
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
                    .padding(.horizontal, AppTheme.pageHorizontal)
                    .padding(.bottom, AppTheme.sectionSpacing)
                }
            }
        }
        .background(AppTheme.groupedBackground.ignoresSafeArea())
        .navigationTitle(AppStrings.Organizations.title)
        .task {
            await viewModel.loadIfNeeded()
            await viewModel.refreshIfStale()
        }
        .refreshable {
            await viewModel.refresh()
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
        .toolbar {
            if presentationMode.allowsManagementControls && PermissionService.canCreateOrganization(user: authState.user) {
                Button {
                    isShowingCreateSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(AppStrings.Action.create)
                .accessibilityHint(AppStrings.Organizations.title)
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
        CommunityCard {
            RemoteCardImage(imageURL: organization.imageURL, height: 220, source: "OrganizationCard", isDecorative: true)

            VStack(alignment: .leading, spacing: 12) {
                Text(organization.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(organization.description)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        ContentMetadataPill(systemImage: "mappin.and.ellipse", text: organization.city)
                        ContentMetadataPill(systemImage: "checkmark.shield", text: organization.moderationStatus.title)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ContentMetadataPill(systemImage: "mappin.and.ellipse", text: organization.city)
                        ContentMetadataPill(systemImage: "checkmark.shield", text: organization.moderationStatus.title)
                    }
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
}

struct OrganizationDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.organizationPresentationMode) private var presentationMode
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
        presentationMode.allowsManagementControls && PermissionService.canCreateEvent(for: organizationID, user: authState.user)
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
                DetailPageContainer {
                    DetailHeaderCard(title: organization.name, subtitle: organization.description) {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) {
                                ContentMetadataPill(systemImage: "mappin.and.ellipse", text: organization.city)
                                ContentMetadataPill(systemImage: "checkmark.shield", text: organization.moderationStatus.title)

                                if let contactEmail = organizationContactText(for: organization) {
                                    ContentMetadataPill(systemImage: "envelope", text: contactEmail)
                                }
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                ContentMetadataPill(systemImage: "mappin.and.ellipse", text: organization.city)
                                ContentMetadataPill(systemImage: "checkmark.shield", text: organization.moderationStatus.title)

                                if let contactEmail = organizationContactText(for: organization) {
                                    ContentMetadataPill(systemImage: "envelope", text: contactEmail)
                                }
                            }
                        }
                    }

                    if organization.imageURL != nil {
                        DetailImageCard(
                            imageURL: organization.imageURL,
                            height: 260,
                            source: "OrganizationDetailView"
                        )
                    }

                    DetailCard {
                        MetadataRow(label: AppStrings.Common.city, value: organization.city, systemImage: "mappin")

                        if let contactEmail = organizationContactText(for: organization) {
                            MetadataRow(label: AppStrings.Common.contact, value: contactEmail, systemImage: "envelope")
                        }

                        if let website = organizationWebsiteText(for: organization) {
                            MetadataRow(label: AppStrings.Common.website, value: website, systemImage: "link")
                        }
                    }

                    DetailCard {
                        DetailActionRow {
                            Text(AppStrings.Common.likes)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                        } trailingContent: {
                            LikeButton(isLiked: organization.likeState.isLiked, count: organization.likeCount) {
                                guard authState.isAuthenticated else {
                                    guestAccessAction = .likes
                                    return
                                }

                                viewModel.toggleLike(for: organization.id)
                            }
                            .disabled(viewModel.pendingOrganizationLikeIDs.contains(organization.id))
                            .accessibilityIdentifier("organization.like.\(organization.id)")
                            .accessibilityLabel(organization.likeState.isLiked ? AppStrings.Action.unlike : AppStrings.Action.like)
                            .accessibilityHint(AppStrings.Common.likes)
                        }
                    }

                    if canCreateOrganizationNews || canCreateOrganizationEvent {
                        DetailCard {
                            if canCreateOrganizationNews {
                                Button {
                                    isShowingCreateNewsSheet = true
                                } label: {
                                    DetailActionRow {
                                        Text(AppStrings.NewsEditor.title)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                    } trailingContent: {
                                        Image(systemName: "square.and.pencil")
                                            .foregroundStyle(AppTheme.accentPrimary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }

                            if canCreateOrganizationEvent {
                                Button {
                                    isShowingCreateEventSheet = true
                                } label: {
                                    DetailActionRow {
                                        Text(AppStrings.Events.editorTitle)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                    } trailingContent: {
                                        Image(systemName: "calendar.badge.plus")
                                            .foregroundStyle(AppTheme.accentPrimary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    DetailCard {
                        SectionHeaderBlock(title: AppStrings.Organizations.activityTitle)

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
                        } else if activityViewModel.isEmptyStateWithoutProfile {
                            EmptyStateCard(
                                systemImage: "building.2",
                                title: AppStrings.Organizations.activityTitle,
                                message: AppStrings.Organizations.empty
                            )
                        } else {
                            ForEach(activityViewModel.items) { item in
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
                .task(id: organization.id) {
                    await activityViewModel.loadIfNeeded(for: organization)
                }
            } else {
                EmptyStateView(title: AppStrings.Common.noItems)
            }
        }
        .navigationTitle(AppStrings.Organizations.detailTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canEditOrganization, viewModel.organization(for: organizationID) != nil {
                Button {
                    isShowingEditSheet = true
                } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityLabel(AppStrings.Action.edit)
                .accessibilityHint(AppStrings.Organizations.detailTitle)
            }

            if canDeleteOrganization {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(viewModel.pendingOrganizationDeleteIDs.contains(organizationID))
                .accessibilityLabel(AppStrings.Action.delete)
                .accessibilityHint(AppStrings.Organizations.detailTitle)
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
                        organizationImageURL: organization.imageURL
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
                        organizationImageURL: organization.imageURL
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
