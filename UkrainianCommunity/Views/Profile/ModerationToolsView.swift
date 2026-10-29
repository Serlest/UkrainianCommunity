import Combine
import FirebaseFirestore
import SwiftUI

extension Notification.Name {
    static let moderationStatusDidChange = Notification.Name("moderationStatusDidChange")
}

enum ModerationToolsScope: Hashable {
    case all
    case organizationRequests
}

enum ModeratedContentType: String {
    case news
    case event
    case organization

    var title: String {
        switch self {
        case .news:
            AppStrings.Moderation.typeNews
        case .event:
            AppStrings.Moderation.typeEvent
        case .organization:
            AppStrings.Moderation.typeOrganization
        }
    }
}

struct ModerationQueueItem: Identifiable {
    let contentID: String
    let type: ModeratedContentType
    let title: String
    let summary: String
    let createdAt: Date
    let expectedRevision: String
    let submittedBy: String?
    let organization: Organization?
    var contentStatus: ModerationStatus = .pendingReview

    var id: String {
        "\(type.rawValue)-\(contentID)"
    }

    var canReview: Bool {
        guard let organization else { return contentStatus == .pendingReview }
        return organization.moderationStatus == .pendingReview
    }
}

@MainActor
final class ModerationQueueViewModel: ObservableObject {
    @Published private(set) var hasMoreRequests = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var history: [OrganizationReviewHistoryEntry] = []
    @Published private(set) var isLoadingHistory = false
    @Published private(set) var historyError: AppError?
    @Published private(set) var hasMoreHistory = false
    private var requestCursor: OrganizationPageCursor?
    private var historyCursor: OrganizationReviewHistoryCursor?
    private var generation = 0
    @Published private(set) var items: [ModerationQueueItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: AppError?
    @Published private(set) var actionError: AppError?
    @Published private(set) var processingItemIDs = Set<String>()

    private let newsRepository: NewsRepository
    private let eventRepository: EventRepository
    private let organizationRepository: OrganizationRepository
    private let listenerBag = RealtimeListenerBag()
    private let organizationID: String?
    private let requestedOrganizationID: String?
    private var loadTask: Task<Void, Never>?
    @Published private(set) var hasLoaded = false
    private var hasLoadedHistory = false
    private var allowedSections: Set<AppSection> = []
    private var pendingContentOperationIDs: [String: String] = [:]

    init(
        newsRepository: NewsRepository,
        eventRepository: EventRepository,
        organizationRepository: OrganizationRepository,
        organizationID: String? = nil,
        requestedOrganizationID: String? = nil
    ) {
        self.newsRepository = newsRepository
        self.eventRepository = eventRepository
        self.organizationRepository = organizationRepository
        self.organizationID = organizationID
        self.requestedOrganizationID = requestedOrganizationID
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await startLoad(force: false)
    }

    func refresh() async {
        await startLoad(force: true)
    }

    func reload() {
        Task {
            await refresh()
        }
    }

    func setAllowedSections(_ sections: Set<AppSection>) {
        let normalizedSections = sections.intersection([.news, .events, .organizations])
        if allowedSections != normalizedSections {
            generation += 1
            history = []
            hasLoadedHistory = false
            historyCursor = nil
            historyError = nil
            isLoadingHistory = false
            isLoadingMore = false
            processingItemIDs = []
            allowedSections = normalizedSections
            loadTask?.cancel()
            loadTask = nil
            items = []
            error = nil
            if !normalizedSections.contains(.organizations) {
                listenerBag.remove("pendingOrganizationRequests")
            }
            hasLoaded = false
        }
    }

    @discardableResult
    func updateStatus(for item: ModerationQueueItem, to newStatus: ModerationStatus, reviewerID: String?) async -> Bool {
        guard !processingItemIDs.contains(item.id) else { return false }
        processingItemIDs.insert(item.id)
        actionError = nil
        defer { processingItemIDs.remove(item.id) }

        do {
            switch item.type {
            case .news:
                let operationKey = "\(item.id):\(newStatus.rawValue)"
                let operationID = pendingContentOperationIDs[operationKey] ?? UUID().uuidString
                pendingContentOperationIDs[operationKey] = operationID
                try await newsRepository.updateModerationStatus(
                    id: item.contentID, newStatus: newStatus,
                    expectedRevision: item.expectedRevision, operationID: operationID
                )
                pendingContentOperationIDs[operationKey] = nil
            case .event:
                let operationKey = "\(item.id):\(newStatus.rawValue)"
                let operationID = pendingContentOperationIDs[operationKey] ?? UUID().uuidString
                pendingContentOperationIDs[operationKey] = operationID
                try await eventRepository.updateModerationStatus(
                    id: item.contentID, newStatus: newStatus,
                    expectedRevision: item.expectedRevision, operationID: operationID
                )
                pendingContentOperationIDs[operationKey] = nil
            case .organization:
                guard allowedSections.contains(.organizations), item.canReview, newStatus == .approved, let reviewerID else { throw AppError.permissionDenied }
                try await organizationRepository.reviewOrganizationRequest(id: item.contentID, reviewerID: reviewerID,
                    expectedRevision: item.expectedRevision, decision: .approve, message: "")
                AppContentChangeBus.postOrganizationsChanged(organizationID: item.contentID)
            }

            items.removeAll { $0.id == item.id }
            hasLoadedHistory = false
            actionError = nil
            NotificationCenter.default.post(name: .moderationStatusDidChange, object: nil)
            return true
        } catch let appError as AppError {
            actionError = appError
        } catch {
            actionError = .unknown
        }
        return false
    }

    @discardableResult
    func requestRevision(for item: ModerationQueueItem, message: String, reviewerID: String?) async -> Bool {
        guard allowedSections.contains(.organizations), item.canReview, item.type == .organization, let reviewerID else {
            actionError = .permissionDenied
            return false
        }
        guard !processingItemIDs.contains(item.id) else { return false }
        processingItemIDs.insert(item.id)
        actionError = nil
        defer { processingItemIDs.remove(item.id) }

        do {
            try await organizationRepository.reviewOrganizationRequest(id: item.contentID, reviewerID: reviewerID,
                expectedRevision: item.expectedRevision, decision: .requestRevision, message: message)
            items.removeAll { $0.id == item.id }
            hasLoadedHistory = false
            actionError = nil
            AppContentChangeBus.postOrganizationsChanged(organizationID: item.contentID)
            NotificationCenter.default.post(name: .moderationStatusDidChange, object: nil)
            return true
        } catch let appError as AppError {
            actionError = appError
        } catch {
            actionError = .unknown
        }
        return false
    }

    @discardableResult
    func rejectOrganizationRequest(for item: ModerationQueueItem, reason: String, reviewerID: String?) async -> Bool {
        guard allowedSections.contains(.organizations), item.canReview, item.type == .organization, let reviewerID else {
            actionError = .permissionDenied
            return false
        }
        guard !processingItemIDs.contains(item.id) else { return false }
        processingItemIDs.insert(item.id)
        actionError = nil
        defer { processingItemIDs.remove(item.id) }

        do {
            try await organizationRepository.reviewOrganizationRequest(id: item.contentID, reviewerID: reviewerID,
                expectedRevision: item.expectedRevision, decision: .reject, message: reason)
            items.removeAll { $0.id == item.id }
            hasLoadedHistory = false
            actionError = nil
            AppContentChangeBus.postOrganizationsChanged(organizationID: item.contentID)
            NotificationCenter.default.post(name: .moderationStatusDidChange, object: nil)
            return true
        } catch let appError as AppError {
            actionError = appError
        } catch {
            actionError = .unknown
        }
        return false
    }

    private func startLoad(force: Bool) async {
        guard force || !hasLoaded else { return }
        if !force, let loadTask { await loadTask.value; return }
        generation += 1
        let expected = generation
        isLoadingMore = false
        requestCursor = nil
        hasMoreRequests = false
        loadTask?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoad()
        }
        loadTask = task
        await task.value
        if generation == expected { loadTask = nil }
    }

    private func performLoad() async {
        guard !Task.isCancelled else { return }
        let expected = generation
        isLoading = true
        defer { if generation == expected { isLoading = false } }

        do {
            let allItems = try await RefreshRequest.run { [self] in try await loadAllowedItems() }

            guard generation == expected, !Task.isCancelled else { return }
            items = allItems
            error = nil
            hasLoaded = true
        } catch is CancellationError {
        } catch {
            guard generation == expected, !Task.isCancelled else { return }
            let appError = FirebaseReadErrorMapper.map(error)
            if requestedOrganizationID != nil, appError == .notFound || appError == .permissionDenied {
                items = []
            }
            self.error = appError
        }
    }

    private func loadAllowedItems() async throws -> [ModerationQueueItem] {
        var loadedItems: [ModerationQueueItem] = []

        if let requestedOrganizationID {
            guard allowedSections.contains(.organizations) else { throw AppError.permissionDenied }
            let snapshot = try await organizationRepository.fetchOrganizationReviewSnapshot(id: requestedOrganizationID)
            guard snapshot.organization.id == requestedOrganizationID else { throw AppError.validationFailed }
            return makeReviewItems(from: [snapshot])
        }

        if let organizationID {
            loadedItems.append(contentsOf: makeItems(from: try await newsRepository.fetchOrganizationModerationNews(organizationID: organizationID)))
            loadedItems.append(contentsOf: makeItems(from: try await eventRepository.fetchOrganizationModerationEvents(organizationID: organizationID)))
            return loadedItems.sorted {
                $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt
            }
        }

        if allowedSections.contains(.news) {
            loadedItems.append(contentsOf: makeItems(from: try await newsRepository.fetchPendingNews()))
        }
        if allowedSections.contains(.events) {
            loadedItems.append(contentsOf: makeItems(from: try await eventRepository.fetchPendingEvents()))
        }
        if allowedSections.contains(.organizations) {
            let expected = generation
            let page = try await organizationRepository.fetchOrganizationReviewPage(limit: 30, after: nil)
            guard generation == expected, !Task.isCancelled else { throw CancellationError() }
            requestCursor = page.nextCursor
            hasMoreRequests = page.hasMore
            loadedItems.append(contentsOf: makeReviewItems(from: page.items))
        }

        return loadedItems.sorted {
            $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt
        }
    }

    func freshReviewItem(_ item: ModerationQueueItem) async -> ModerationQueueItem? {
        guard allowedSections.contains(.organizations), !processingItemIDs.contains(item.id) else { return nil }
        let expected = generation
        processingItemIDs.insert(item.id)
        actionError = nil
        defer { processingItemIDs.remove(item.id) }
        do {
            let snapshot = try await organizationRepository.fetchOrganizationReviewSnapshot(id: item.contentID)
            guard expected == generation, !Task.isCancelled else { return nil }
            return makeReviewItems(from: [snapshot]).first
        } catch { if expected == generation { actionError = FirebaseReadErrorMapper.map(error) }; return nil }
    }

    func loadMoreRequests() async {
        guard hasMoreRequests, !isLoadingMore, allowedSections.contains(.organizations) else { return }
        let expected = generation
        isLoadingMore = true
        defer { if generation == expected { isLoadingMore = false } }
        do {
            let page = try await organizationRepository.fetchOrganizationReviewPage(limit: 30, after: requestCursor)
            guard generation == expected, !Task.isCancelled else { return }
            let ids = Set(items.map(\.id))
            items += makeReviewItems(from: page.items).filter { !ids.contains($0.id) }
            requestCursor = page.nextCursor
            hasMoreRequests = page.hasMore
            error = nil
        } catch { if generation == expected { self.error = FirebaseReadErrorMapper.map(error) } }
    }

    func loadHistoryIfNeeded() async {
        guard !hasLoadedHistory else { return }
        await loadHistory(reset: true)
    }

    func loadHistory(reset: Bool = false) async {
        guard allowedSections.contains(.organizations), !isLoadingHistory else { return }
        if !reset, !history.isEmpty, !hasMoreHistory { return }
        let expected = generation
        isLoadingHistory = true
        defer { if generation == expected { isLoadingHistory = false } }
        do {
            let requestedCursor = reset ? nil : historyCursor
            let page = try await RefreshRequest.run { [organizationRepository] in
                try await organizationRepository.fetchOrganizationReviewHistory(limit: 30, after: requestedCursor)
            }
            guard generation == expected, !Task.isCancelled else { return }
            let ids = reset ? Set<String>() : Set(history.map(\.id))
            history = (reset ? [] : history) + page.items.filter { !ids.contains($0.id) }
            historyCursor = page.nextCursor
            hasMoreHistory = page.nextCursor != nil
            historyError = nil
            hasLoadedHistory = true
        } catch { if generation == expected { historyError = FirebaseReadErrorMapper.map(error) } }
    }

    private func makeReviewItems(from snapshots: [OrganizationReviewSnapshot]) -> [ModerationQueueItem] {
        snapshots.map { snapshot in
            let organization = snapshot.organization
            return ModerationQueueItem(contentID: organization.id, type: .organization,
                title: organization.localizedName, summary: organization.localizedShortDescription,
                createdAt: organization.submittedAt ?? organization.createdAt, expectedRevision: snapshot.revision,
                submittedBy: snapshot.applicantDisplayName ?? organization.submittedByDisplayName.flatMap {
                    let name = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    return name.isEmpty || name == organization.submittedByUserId ? nil : name
                }, organization: organization)
        }
    }

    private func makeItems(from news: [NewsPost]) -> [ModerationQueueItem] {
        news.map {
            ModerationQueueItem(
                contentID: $0.id,
                type: .news,
                title: $0.title,
                summary: $0.subtitle,
                createdAt: $0.createdAt,
                expectedRevision: revision($0.updatedAt),
                submittedBy: nil,
                organization: nil, contentStatus: $0.moderationStatus
            )
        }
    }

    private func makeItems(from events: [Event]) -> [ModerationQueueItem] {
        events.map {
            ModerationQueueItem(
                contentID: $0.id,
                type: .event,
                title: $0.title,
                summary: $0.summary,
                createdAt: $0.createdAt,
                expectedRevision: revision($0.updatedAt),
                submittedBy: nil,
                organization: nil, contentStatus: $0.moderationStatus
            )
        }
    }

    private func revision(_ date: Date) -> String {
        let timestamp = Timestamp(date: date)
        return "\(timestamp.seconds):\(timestamp.nanoseconds)"
    }

}

struct ModerationToolsView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel: ModerationQueueViewModel
    @State private var selectedContent: ModerationQueueItem?
    @State private var selectedOrganizationRequest: ModerationQueueItem?
    @State private var pendingRejectedItem: ModerationQueueItem?
    @State private var isShowingRejectConfirmation = false
    @State private var permissionOrganization: Organization?
    @State private var showsHistory = false
    @State private var searchText = ""
    @State private var selectedContentType: ModeratedContentType?
    @State private var sortOption: AppListSortOption = .newest
    @State private var hasOpenedRequestedOrganization = false
    private let organizationID: String?
    private let requestedOrganizationID: String?
    private let scope: ModerationToolsScope
    private let organizationRepository: OrganizationRepository

    init(
        organizationID: String? = nil,
        scope: ModerationToolsScope = .all,
        requestedOrganizationID: String? = nil,
        newsRepository: NewsRepository = FirestoreNewsRepository(),
        eventRepository: EventRepository = FirestoreEventRepository(),
        organizationRepository: OrganizationRepository = FirestoreOrganizationRepository()
    ) {
        self.organizationID = organizationID
        self.scope = scope
        self.requestedOrganizationID = requestedOrganizationID
        self.organizationRepository = organizationRepository
        _viewModel = StateObject(wrappedValue: ModerationQueueViewModel(
            newsRepository: newsRepository,
            eventRepository: eventRepository,
            organizationRepository: organizationRepository,
            organizationID: organizationID,
            requestedOrganizationID: requestedOrganizationID
        ))
    }

    private var canAccessModeration: Bool {
        guard let user = authState.user else { return false }
        if organizationID != nil {
            guard let permissionOrganization else { return false }
            return PermissionService.canModerateOrganizationContent(permissionOrganization, user: user)
        }
        if scope == .organizationRequests {
            return PermissionService.canManageOrganizationRequests(user: user)
        }
        return PermissionService.canModerate(section: .news, user: user)
            || PermissionService.canModerate(section: .events, user: user)
    }

    private var allowedSections: Set<AppSection> {
        guard let user = authState.user else { return [] }
        if organizationID != nil {
            guard let permissionOrganization,
                  PermissionService.canModerateOrganizationContent(permissionOrganization, user: user) else {
                return []
            }
            return [.news, .events]
        }
        let sections = PermissionService.moderatedSections(for: user)
            .intersection([.news, .events])
        if scope == .organizationRequests {
            return PermissionService.canManageOrganizationRequests(user: user) ? [.organizations] : []
        }
        return sections
    }

    private var screenTitle: String {
        if organizationID != nil { return AppStrings.Moderation.organizationTitle }
        if scope == .organizationRequests { return AppStrings.Profile.ownerOrganizationRequests }
        return AppStrings.Moderation.title
    }

    private var emptyMessage: String {
        if organizationID != nil { return AppStrings.Moderation.organizationEmpty }
        if scope == .organizationRequests { return AppStrings.Moderation.organizationRequestsEmpty }
        return AppStrings.Moderation.empty
    }

    private var screenSubtitle: String {
        scope == .organizationRequests
            ? AppStrings.Profile.organizationRequestsReviewSubtitle
            : AppStrings.Moderation.subtitle
    }

    private var visibleItems: [ModerationQueueItem] {
        return viewModel.items.filter { item in
            let matchesType = selectedContentType == nil || item.type == selectedContentType
            let matchesSearch = LocalSearchMatcher.matches(
                query: searchText,
                values: [item.title, item.summary, item.submittedBy, item.id]
            )
            return matchesType && matchesSearch
        }.sorted(by: moderationSort)
    }

    var body: some View {
        AdminScreenShell(
            title: screenTitle,
            subtitle: screenSubtitle,
            tabBarHidden: false
        ) {
            if scope == .organizationRequests && requestedOrganizationID == nil && canAccessModeration {
                Picker(AppStrings.OrganizationReview.section, selection: $showsHistory) {
                    Text(AppStrings.OrganizationReview.pending).tag(false)
                    Text(AppStrings.OrganizationReview.history).tag(true)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("organization.requests.mode")
            }
            if showsHistory && canAccessModeration { historyContent } else { moderationContent }
        }
        .task(id: showsHistory) { if showsHistory { await viewModel.loadHistoryIfNeeded() } }
        .appRefreshable {
            guard viewModel.processingItemIDs.isEmpty else { return }
            if showsHistory { await viewModel.loadHistory(reset: true) } else { await viewModel.refresh() }
        }
        .task {
            await loadPermissionOrganizationIfNeeded()
            viewModel.setAllowedSections(allowedSections)
            await viewModel.loadIfNeeded()
            openRequestedOrganizationIfLoaded()
        }
        .onChange(of: viewModel.items.map(\.id)) { _, _ in
            openRequestedOrganizationIfLoaded()
        }
        .onChange(of: viewModel.error) { _, error in
            if error == .notFound || error == .permissionDenied { selectedOrganizationRequest = nil }
        }
        .onChange(of: allowedSections) { _, newSections in
            if !newSections.contains(.organizations) { selectedOrganizationRequest = nil }
            viewModel.setAllowedSections(newSections)
            viewModel.reload()
        }
        .confirmationDialog(
            AppStrings.Moderation.rejectConfirmationTitle,
            isPresented: $isShowingRejectConfirmation,
            presenting: pendingRejectedItem
        ) { item in
            Button(AppStrings.Moderation.confirmReject, role: .destructive) {
                Task {
                    await viewModel.updateStatus(for: item, to: .rejected, reviewerID: authState.user?.id)
                    pendingRejectedItem = nil
                }
            }
            Button(AppStrings.Common.cancel, role: .cancel) {
                pendingRejectedItem = nil
            }
        } message: { item in
            Text(AppStrings.Moderation.rejectConfirmationMessage(item.title))
        }
        .sheet(item: $selectedContent) { item in
            ContentModerationDetail(contentType: item.type.rawValue, contentID: item.contentID)
        }
        .sheet(item: $selectedOrganizationRequest) { item in
            ModerationOrganizationRequestSheet(
                item: item,
                isProcessing: viewModel.processingItemIDs.contains(item.id),
                actionErrorMessage: viewModel.actionError.map { $0 == .validationFailed ? AppStrings.OrganizationReview.changed : actionErrorMessage(for: $0) },
                approveAction: {
                    let succeeded = await viewModel.updateStatus(for: item, to: .approved, reviewerID: authState.user?.id)
                    if succeeded { selectedOrganizationRequest = nil }
                },
                revisionAction: { message in
                    let succeeded = await viewModel.requestRevision(for: item, message: message, reviewerID: authState.user?.id)
                    if succeeded { selectedOrganizationRequest = nil }
                },
                rejectAction: { reason in
                    let succeeded = await viewModel.rejectOrganizationRequest(for: item, reason: reason, reviewerID: authState.user?.id)
                    if succeeded { selectedOrganizationRequest = nil }
                }
            )
        }
    }

    private func loadPermissionOrganizationIfNeeded() async {
        guard permissionOrganization == nil, let organizationID else { return }
        permissionOrganization = try? await organizationRepository.fetchOrganization(id: organizationID)
    }

    private func openRequestedOrganizationIfLoaded() {
        guard canAccessModeration, !hasOpenedRequestedOrganization,
              let requestedOrganizationID,
              let item = viewModel.items.first(where: { $0.type == .organization && $0.contentID == requestedOrganizationID }) else {
            return
        }
        hasOpenedRequestedOrganization = true
        selectedOrganizationRequest = item
    }

    @ViewBuilder
    private var moderationContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
            if !canAccessModeration {
                UnifiedEmptyStateCard(
                    systemImage: "lock.shield",
                    title: screenTitle,
                    message: AppStrings.Moderation.loadPermissionError
                )
            } else if (viewModel.isLoading || !viewModel.hasLoaded && viewModel.error == nil) && viewModel.items.isEmpty {
                LoadingStateCard(title: AppStrings.Profile.reviewPendingContent)
                    .accessibilityIdentifier("organization.requests.loading")
            } else if let error = viewModel.error, viewModel.items.isEmpty {
                UnifiedEmptyStateCard(
                    systemImage: "exclamationmark.triangle",
                    title: screenTitle,
                    message: errorMessage(for: error)
                ) {
                    PrimaryActionButton(title: AppStrings.Moderation.retry, systemImage: "arrow.clockwise") {
                        viewModel.reload()
                    }
                }
                .accessibilityIdentifier("organization.requests.error")
            } else if viewModel.items.isEmpty {
                UnifiedEmptyStateCard(
                    systemImage: "checkmark.shield",
                    title: screenTitle,
                    message: emptyMessage
                )
                .accessibilityIdentifier("organization.requests.empty")
            } else {
                if let error = viewModel.error {
                    InlineMessageCard(style: .error, message: errorMessage(for: error))
                }
                if let actionError = viewModel.actionError {
                    InlineMessageCard(style: .error, message: actionErrorMessage(for: actionError))
                }

                moderationFilters

                if scope == .organizationRequests && !searchText.isEmpty && viewModel.hasMoreRequests {
                    InlineMessageCard(style: .info, message: AppStrings.OrganizationReview.loadedSearch)
                    if visibleItems.isEmpty {
                        Button(AppStrings.OrganizationReview.loadMore) { Task { await viewModel.loadMoreRequests() } }
                            .disabled(viewModel.isLoadingMore)
                    }
                }
                if visibleItems.isEmpty {
                    UnifiedEmptyStateCard(
                        systemImage: "line.3.horizontal.decrease.circle",
                        title: AppStrings.Moderation.filteredEmptyTitle,
                        message: AppStrings.Moderation.filteredEmptyMessage
                    ) {
                        Button(AppStrings.Moderation.clearFilters) {
                            searchText = ""
                            selectedContentType = nil
                        }
                        .buttonStyle(.bordered)
                        .tint(AppTheme.accentPrimaryForeground)
                    }
                } else {
                    LazyVStack(spacing: AppTheme.feedRowSpacing) {
                        ForEach(visibleItems) { item in
                            ModerationItemRow(
                                item: item,
                                isProcessing: viewModel.processingItemIDs.contains(item.id),
                                approveAction: {
                                    if item.type == .organization { selectedOrganizationRequest = item }
                                    else { await viewModel.updateStatus(for: item, to: .approved, reviewerID: authState.user?.id) }
                                },
                                rejectAction: {
                                    if item.type == .organization {
                                        selectedOrganizationRequest = item
                                    } else {
                                        pendingRejectedItem = item
                                        isShowingRejectConfirmation = true
                                    }
                                },
                                detailsAction: item.type == .organization ? {
                                    Task { selectedOrganizationRequest = await viewModel.freshReviewItem(item) }
                                } : { selectedContent = item }
                            )
                        }
                    }
                    if scope == .organizationRequests && viewModel.hasMoreRequests {
                        PrimaryActionButton(title: AppStrings.OrganizationReview.loadMore,
                            isEnabled: !viewModel.isLoadingMore, isLoading: viewModel.isLoadingMore,
                            systemImage: "arrow.down") { Task { await viewModel.loadMoreRequests() } }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var historyContent: some View {
        if let error = viewModel.historyError {
            InlineMessageCard(style: .error, message: errorMessage(for: error))
            Button(AppStrings.Moderation.retry) { Task { await viewModel.loadHistory(reset: true) } }
        }
        if viewModel.isLoadingHistory && viewModel.history.isEmpty {
            LoadingStateCard(title: AppStrings.OrganizationReview.history)
        } else if viewModel.history.isEmpty && viewModel.historyError == nil {
            UnifiedEmptyStateCard(systemImage: "clock.arrow.circlepath", title: AppStrings.OrganizationReview.history,
                message: AppStrings.OrganizationReview.historyEmpty)
        } else {
            LazyVStack(spacing: AppTheme.feedRowSpacing) {
                ForEach(viewModel.history) { entry in
                    AppEditorSectionCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(entry.organizationName.isEmpty ? AppStrings.Organizations.title : entry.organizationName)
                                .font(.headline)
                            Text(entry.status.title).foregroundStyle(AppTheme.accentPrimaryForeground)
                            if !entry.reviewerDisplayName.isEmpty {
                                Text(entry.reviewerDisplayName).font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                            }
                            Text(LocalizationStore.dateString(from: entry.createdAt, timeStyle: .short)).font(.caption).foregroundStyle(AppTheme.textSecondary)
                            if !entry.reason.isEmpty { Text(entry.reason).font(.subheadline).textSelection(.enabled) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if viewModel.hasMoreHistory {
                    PrimaryActionButton(title: AppStrings.OrganizationReview.loadMore,
                        isEnabled: !viewModel.isLoadingHistory, isLoading: viewModel.isLoadingHistory,
                        systemImage: "arrow.down") { Task { await viewModel.loadHistory() } }
                }
            }
        }
    }

    private var moderationFilters: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                AppSearchField(placeholder: AppStrings.Moderation.searchPlaceholder,
                               text: $searchText, fieldID: "organization.requests.search")

                AppHorizontalFilterRow {
                    if scope != .organizationRequests {
                    Button {
                        selectedContentType = nil
                    } label: {
                        AppFilterChip(
                            title: "\(AppStrings.Moderation.filterAll): \(viewModel.items.count)",
                            isSelected: selectedContentType == nil
                        )
                    }
                    .buttonStyle(.plain)

                    ForEach(availableContentTypes, id: \.rawValue) { type in
                        Button {
                            selectedContentType = type
                        } label: {
                            AppFilterChip(
                                title: "\(type.title): \(viewModel.items.filter { $0.type == type }.count)",
                                isSelected: selectedContentType == type
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    AppSortMenu(
                        selection: $sortOption,
                        options: [.newest, .oldest, .nameAscending, .nameDescending]
                    )
                    }
                }
            }
        }
    }

    private var availableContentTypes: [ModeratedContentType] {
        [.news, .event, .organization].filter { type in
            viewModel.items.contains { $0.type == type }
        }
    }

    private func moderationSort(_ lhs: ModerationQueueItem, _ rhs: ModerationQueueItem) -> Bool {
        switch sortOption {
        case .newest:
            lhs.createdAt == rhs.createdAt ? lhs.id < rhs.id : lhs.createdAt > rhs.createdAt
        case .oldest:
            lhs.createdAt == rhs.createdAt ? lhs.id < rhs.id : lhs.createdAt < rhs.createdAt
        case .nameAscending:
            compareModerationTitles(lhs, rhs, ascending: true)
        case .nameDescending:
            compareModerationTitles(lhs, rhs, ascending: false)
        case .popular:
            lhs.createdAt == rhs.createdAt ? lhs.id < rhs.id : lhs.createdAt > rhs.createdAt
        }
    }

    private func compareModerationTitles(
        _ lhs: ModerationQueueItem,
        _ rhs: ModerationQueueItem,
        ascending: Bool
    ) -> Bool {
        let result = LocalizationStore.compareForSorting(lhs.title, rhs.title)
        guard result != .orderedSame else { return lhs.id < rhs.id }
        return ascending ? result == .orderedAscending : result == .orderedDescending
    }

    private func errorMessage(for error: AppError) -> String {
        switch error {
        case .network:
            AppStrings.Moderation.loadNetworkError
        case .permissionDenied:
            AppStrings.Moderation.loadPermissionError
        case .notFound where requestedOrganizationID != nil:
            AppStrings.Moderation.organizationRequestUnavailable
        case .validationFailed, .notFound:
            AppStrings.Moderation.loadValidationError
        case .unknown:
            AppStrings.Moderation.loadUnknownError
        }
    }

    private func actionErrorMessage(for error: AppError) -> String {
        switch error {
        case .network:
            AppStrings.Moderation.actionNetworkError
        case .permissionDenied:
            AppStrings.Moderation.actionPermissionError
        case .validationFailed, .notFound:
            AppStrings.Moderation.actionValidationError
        case .unknown:
            AppStrings.Moderation.actionUnknownError
        }
    }
}

private struct ModerationItemRow: View {
    let item: ModerationQueueItem
    let isProcessing: Bool
    let approveAction: () async -> Void
    let rejectAction: () async -> Void
    let detailsAction: (() -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.type.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accentPrimaryForeground)
                    Spacer()
                    Text(LocalizationStore.dateString(from: item.createdAt))
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Text(item.title)
                    .font(.headline)

                Text(item.summary)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)

                if let submittedBy = item.submittedBy {
                    Text("\(AppStrings.Moderation.submittedBy): \(submittedBy)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                }

                if dynamicTypeSize.isAccessibilitySize || detailsAction != nil {
                    VStack(spacing: 12) {
                        actionButtons
                    }
                } else {
                    HStack(spacing: 12) {
                        actionButtons
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if let detailsAction {
            Button(action: detailsAction) {
                Label(item.type == .organization ? AppStrings.Moderation.openRequest : ContentModerationCopy.openMaterial, systemImage: "doc.text.magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: AppTheme.iconButtonSize)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("organization.requests.open.\(item.contentID)")
            .disabled(isProcessing)
        }

        if item.canReview && detailsAction == nil { reviewButtons }
    }

    @ViewBuilder
    private var reviewButtons: some View {
        PrimaryActionButton(
            title: AppStrings.Moderation.approve,
            isEnabled: !isProcessing,
            isLoading: isProcessing,
            systemImage: "checkmark"
        ) {
            Task {
                await approveAction()
            }
        }

        Button(role: .destructive) {
            Task {
                await rejectAction()
            }
        } label: {
            Label(AppStrings.Moderation.reject, systemImage: "xmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentDestructiveForeground)
                .multilineTextAlignment(.center)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .frame(minHeight: AppTheme.iconButtonSize)
                .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
                        .strokeBorder(AppTheme.accentDestructive.opacity(0.18))
                )
            }
        .buttonStyle(.plain)
        .disabled(isProcessing)
    }
}

private struct ModerationOrganizationRequestSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: ModerationQueueItem
    let isProcessing: Bool
    let actionErrorMessage: String?
    let approveAction: () async -> Void
    let revisionAction: (String) async -> Void
    let rejectAction: (String) async -> Void
    @State private var decision: OrganizationReviewDecision?
    @State private var reason = ""
    @State private var confirmsDecision = false

    private func title(for option: OrganizationReviewDecision) -> String {
        switch option {
        case .approve: AppStrings.Moderation.approveOrganization
        case .requestRevision: AppStrings.Moderation.requestRevision
        case .reject: AppStrings.Moderation.rejectRequest
        }
    }
    private var decisionTitle: String { decision.map(title(for:)) ?? AppStrings.OrganizationReview.chooseDecision }
    private var needsReason: Bool { decision == .requestRevision || decision == .reject }
    private var valid: Bool {
        decision != nil && (!needsReason || (!reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && reason.utf16.count <= 2000))
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                        if let organization = item.organization {
                            OrganizationRequestPreviewContent(organization: organization, item: item)
                        }
                        if let actionErrorMessage { InlineMessageCard(style: .error, message: actionErrorMessage) }
                        if item.canReview {
                            AppEditorSectionCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    AppEditorSectionTitle(title: AppStrings.OrganizationReview.decision)
                                    ForEach(OrganizationReviewDecision.allCases) { option in
                                        Button { decision = option } label: {
                                            HStack(spacing: 10) {
                                                Image(systemName: decision == option ? "checkmark.circle.fill" : "circle")
                                                    .foregroundStyle(AppTheme.accentPrimaryForeground)
                                                Text(title(for: option)).multilineTextAlignment(.leading)
                                                    .foregroundStyle(option == .reject ? AppTheme.accentDestructiveForeground : AppTheme.textPrimary)
                                                    .fixedSize(horizontal: false, vertical: true)
                                                Spacer(minLength: 0)
                                            }
                                            .padding(10).frame(maxWidth: .infinity, minHeight: 44)
                                            .background(decision == option ? AppTheme.accentPrimary.opacity(0.12) : AppTheme.surfaceControl.opacity(0.4),
                                                in: RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius))
                                        }
                                        .buttonStyle(.plain).disabled(isProcessing)
                                        .accessibilityAddTraits(decision == option ? .isSelected : [])
                                        .accessibilityIdentifier("organization.request.choice.\(option.rawValue)")
                                    }
                                    if needsReason {
                                        Text(AppStrings.OrganizationReview.reasonHelper).font(.footnote).foregroundStyle(AppTheme.textSecondary)
                                        TextField(AppStrings.Moderation.revisionMessage, text: $reason, axis: .vertical)
                                            .lineLimit(3...8).textFieldStyle(.roundedBorder)
                                            .disabled(isProcessing)
                                            .accessibilityIdentifier("organization.request.reason")
                                        Text("\(reason.utf16.count) / 2000").font(.caption)
                                            .foregroundStyle(reason.utf16.count > 2000 ? AppTheme.accentDestructiveForeground : AppTheme.textSecondary)
                                    }
                                }
                            }
                            .disabled(isProcessing)
                            .id("decision")
                        } else {
                            InlineMessageCard(style: .info, message: AppStrings.Moderation.organizationRequestAlreadyReviewed)
                        }
                    }
                    .padding(AppTheme.pageHorizontal).appCenteredContent()
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: decision) { _, _ in
                    Task { @MainActor in
                        await Task.yield()
                        withAnimation { proxy.scrollTo("decision", anchor: .bottom) }
                    }
                }
            }
            .background(AppBackgroundView())
            .navigationTitle(AppStrings.OrganizationReview.request)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if item.canReview {
                    PrimaryActionButton(title: AppStrings.OrganizationReview.confirmDecision,
                        isEnabled: !isProcessing && valid, isLoading: isProcessing, systemImage: "checkmark.shield") {
                        confirmsDecision = true
                    }
                    .accessibilityIdentifier("organization.request.confirm")
                    .padding(AppTheme.pageHorizontal).appCenteredContent().background(.regularMaterial)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.Common.cancel) { dismiss() }
                        .tint(AppTheme.accentPrimaryForeground).disabled(isProcessing)
                }
            }
            .interactiveDismissDisabled(isProcessing)
            .confirmationDialog(decisionTitle, isPresented: $confirmsDecision) {
                Button(decisionTitle, role: decision == .reject ? .destructive : nil) {
                    Task {
                        switch decision {
                        case .approve: await approveAction()
                        case .requestRevision: await revisionAction(reason)
                        case .reject: await rejectAction(reason)
                        case nil: break
                        }
                    }
                }
                .accessibilityIdentifier("organization.request.execute")
                Button(AppStrings.Common.cancel, role: .cancel) {}
            } message: { Text(AppStrings.OrganizationReview.confirmHelper) }
        }
    }
}

private struct OrganizationRequestPreviewContent: View {
    let organization: Organization
    let item: ModerationQueueItem

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
            OrganizationReadOnlyDetailContent(
                organization: organization,
                showsModerationStatus: true
            )
            requestDataCard
            applicantCard
        }
    }

    private var requestDataCard: some View {
        previewSection(title: AppStrings.Moderation.requestData, systemImage: "doc.text.magnifyingglass") {
            previewRow(AppStrings.Common.status, organization.moderationStatus.title, systemImage: "clock")
            if let reviewMessage = trimmed(organization.reviewMessage) {
                InlineMessageCard(style: .info, message: reviewMessage)
            }
            if let rejectionReason = trimmed(organization.rejectionReason) {
                InlineMessageCard(style: .error, message: rejectionReason)
            }
        }
    }

    private var applicantCard: some View {
        previewSection(title: AppStrings.Moderation.requestApplicant, systemImage: "person.text.rectangle") {
            previewRow(AppStrings.Moderation.submittedBy, item.submittedBy ?? AppStrings.OrganizationReview.applicant, systemImage: "person")
            previewRow(AppStrings.Moderation.submittedAt, organization.submittedAt.map { LocalizationStore.dateString(from: $0) }, systemImage: "calendar")
            if let uid = organization.submittedByUserId {
                DisclosureGroup(AppStrings.OrganizationReview.technicalDetails) {
                    Text(uid).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
        }
    }

    private func previewSection<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                content()
            }
        }
    }

    @ViewBuilder
    private func previewRow(_ title: String, _ value: String?, systemImage: String) -> some View {
        if let value = trimmed(value) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.accentPrimaryForeground)
                    .frame(width: 24, height: 24)
                    .background(AppTheme.accentPrimary.opacity(0.10), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                    Text(value)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textPrimary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func trimmed(_ value: String?) -> String? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        return text
    }

}

#Preview {
    NavigationStack {
        ModerationToolsView(
            newsRepository: MockNewsRepository(),
            eventRepository: MockEventRepository(),
            organizationRepository: MockOrganizationRepository()
        )
    }
    .environmentObject(AuthState())
}
