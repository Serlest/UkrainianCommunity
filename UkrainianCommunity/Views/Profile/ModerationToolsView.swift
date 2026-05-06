import Combine
import SwiftUI

extension Notification.Name {
    static let moderationStatusDidChange = Notification.Name("moderationStatusDidChange")
}

private enum ModeratedContentType: String {
    case news
    case event
    case organization
    case marketplace

    var title: String {
        switch self {
        case .news:
            AppStrings.Moderation.typeNews
        case .event:
            AppStrings.Moderation.typeEvent
        case .organization:
            AppStrings.Moderation.typeOrganization
        case .marketplace:
            AppStrings.Moderation.typeMarketplace
        }
    }
}

private struct ModerationQueueItem: Identifiable {
    let contentID: String
    let type: ModeratedContentType
    let title: String
    let summary: String
    let createdAt: Date

    var id: String {
        "\(type.rawValue)-\(contentID)"
    }
}

@MainActor
private final class ModerationQueueViewModel: ObservableObject {
    @Published private(set) var items: [ModerationQueueItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: AppError?
    @Published private(set) var processingItemIDs = Set<String>()

    private let newsRepository: NewsRepository
    private let eventRepository: EventRepository
    private let organizationRepository: OrganizationRepository
    private let marketplaceRepository: MarketplaceRepository
    private var loadTask: Task<Void, Never>?
    private var hasLoaded = false
    private var allowedSections: Set<AppSection> = []

    init(
        newsRepository: NewsRepository,
        eventRepository: EventRepository,
        organizationRepository: OrganizationRepository,
        marketplaceRepository: MarketplaceRepository
    ) {
        self.newsRepository = newsRepository
        self.eventRepository = eventRepository
        self.organizationRepository = organizationRepository
        self.marketplaceRepository = marketplaceRepository
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
        let normalizedSections = sections.intersection([.news, .events, .organizations, .marketplace])
        if allowedSections != normalizedSections {
            allowedSections = normalizedSections
            hasLoaded = false
        }
    }

    func updateStatus(for item: ModerationQueueItem, to newStatus: ModerationStatus) async {
        processingItemIDs.insert(item.id)
        defer { processingItemIDs.remove(item.id) }

        do {
            switch item.type {
            case .news:
                try await newsRepository.updateModerationStatus(id: item.contentID, newStatus: newStatus)
            case .event:
                try await eventRepository.updateModerationStatus(id: item.contentID, newStatus: newStatus)
            case .organization:
                try await organizationRepository.updateModerationStatus(id: item.contentID, newStatus: newStatus)
            case .marketplace:
                try await marketplaceRepository.updateModerationStatus(id: item.contentID, newStatus: newStatus)
            }

            items.removeAll { $0.id == item.id }
            error = nil
            NotificationCenter.default.post(name: .moderationStatusDidChange, object: nil)
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    private func startLoad(force: Bool) async {
        guard force || !hasLoaded else { return }

        loadTask?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoad()
        }
        loadTask = task
        await task.value
    }

    private func performLoad() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let allItems = try await loadAllowedItems()

            guard !Task.isCancelled else { return }
            items = allItems
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

    private func loadAllowedItems() async throws -> [ModerationQueueItem] {
        var loadedItems: [ModerationQueueItem] = []

        if allowedSections.contains(.news) {
            loadedItems.append(contentsOf: makeItems(from: try await newsRepository.fetchPendingNews()))
        }
        if allowedSections.contains(.events) {
            loadedItems.append(contentsOf: makeItems(from: try await eventRepository.fetchPendingEvents()))
        }
        if allowedSections.contains(.organizations) {
            loadedItems.append(contentsOf: makeItems(from: try await organizationRepository.fetchPendingOrganizations()))
        }
        if allowedSections.contains(.marketplace) {
            loadedItems.append(contentsOf: makeItems(from: try await marketplaceRepository.fetchPendingMarketplaceItems()))
        }

        return loadedItems.sorted { $0.createdAt > $1.createdAt }
    }

    private func makeItems(from news: [NewsPost]) -> [ModerationQueueItem] {
        news.map {
            ModerationQueueItem(
                contentID: $0.id,
                type: .news,
                title: $0.title,
                summary: $0.subtitle,
                createdAt: $0.createdAt
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
                createdAt: $0.createdAt
            )
        }
    }

    private func makeItems(from organizations: [Organization]) -> [ModerationQueueItem] {
        organizations.map {
            ModerationQueueItem(
                contentID: $0.id,
                type: .organization,
                title: $0.name,
                summary: $0.description,
                createdAt: $0.createdAt
            )
        }
    }

    private func makeItems(from marketplaceItems: [MarketplaceItem]) -> [ModerationQueueItem] {
        marketplaceItems.map {
            ModerationQueueItem(
                contentID: $0.id,
                type: .marketplace,
                title: $0.title,
                summary: $0.description,
                createdAt: $0.createdAt
            )
        }
    }
}

struct ModerationToolsView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel: ModerationQueueViewModel

    init(
        newsRepository: NewsRepository = FirestoreNewsRepository(),
        eventRepository: EventRepository = FirestoreEventRepository(),
        organizationRepository: OrganizationRepository = FirestoreOrganizationRepository(),
        marketplaceRepository: MarketplaceRepository = FirestoreMarketplaceRepository()
    ) {
        _viewModel = StateObject(wrappedValue: ModerationQueueViewModel(
            newsRepository: newsRepository,
            eventRepository: eventRepository,
            organizationRepository: organizationRepository,
            marketplaceRepository: marketplaceRepository
        ))
    }

    private var canAccessModeration: Bool {
        guard let user = authState.user else { return false }
        return PermissionService.canModerate(section: .news, user: user)
            || PermissionService.canModerate(section: .events, user: user)
            || PermissionService.canModerate(section: .organizations, user: user)
            || PermissionService.canModerate(section: .marketplace, user: user)
    }

    private var allowedSections: Set<AppSection> {
        guard let user = authState.user else { return [] }
        return PermissionService.moderatedSections(for: user)
            .intersection([.news, .events, .organizations, .marketplace])
    }

    var body: some View {
        Group {
            if !canAccessModeration {
                moderationStateView(message: AppStrings.Moderation.loadPermissionError)
            } else if viewModel.isLoading && viewModel.items.isEmpty {
                ProgressView(AppStrings.Profile.reviewPendingContent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = viewModel.error, viewModel.items.isEmpty {
                moderationErrorView(message: errorMessage(for: error))
            } else if viewModel.items.isEmpty {
                moderationStateView(message: AppStrings.Moderation.empty)
            } else {
                List {
                    Section {
                        Text(AppStrings.Moderation.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .listRowBackground(AppTheme.surfacePrimary)

                    if let error = viewModel.error {
                        Section {
                            Text(errorMessage(for: error))
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .listRowBackground(AppTheme.surfacePrimary)
                    }

                    Section {
                        ForEach(viewModel.items) { item in
                            ModerationItemRow(
                                item: item,
                                isProcessing: viewModel.processingItemIDs.contains(item.id),
                                approveAction: {
                                    await viewModel.updateStatus(for: item, to: .approved)
                                },
                                rejectAction: {
                                    await viewModel.updateStatus(for: item, to: .rejected)
                                }
                            )
                        }
                    }
                    .listRowBackground(AppTheme.surfacePrimary)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(AppTheme.pageBackground)
            }
        }
        .background(AppTheme.pageBackground)
        .tint(AppTheme.accentPrimary)
        .navigationTitle(AppStrings.Moderation.title)
        .task {
            viewModel.setAllowedSections(allowedSections)
            await viewModel.loadIfNeeded()
        }
        .onChange(of: allowedSections) { _, newSections in
            viewModel.setAllowedSections(newSections)
            viewModel.reload()
        }
    }

    private func moderationStateView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.shield")
                .font(.system(size: 30))
                .foregroundStyle(AppTheme.textSecondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(AppTheme.pageBackground)
    }

    private func moderationErrorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 30))
                .foregroundStyle(AppTheme.textSecondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button(AppStrings.Moderation.retry) {
                viewModel.reload()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func errorMessage(for error: AppError) -> String {
        switch error {
        case .network:
            AppStrings.Moderation.loadNetworkError
        case .permissionDenied:
            AppStrings.Moderation.loadPermissionError
        case .validationFailed, .notFound:
            AppStrings.Moderation.loadValidationError
        case .unknown:
            AppStrings.Moderation.loadUnknownError
        }
    }
}

private struct ModerationItemRow: View {
    let item: ModerationQueueItem
    let isProcessing: Bool
    let approveAction: () async -> Void
    let rejectAction: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.type.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accentPrimary)
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
                .lineLimit(3)

            HStack(spacing: 12) {
                Button(AppStrings.Moderation.approve) {
                    Task {
                        await approveAction()
                    }
                }
                .buttonStyle(.borderedProminent)

                Button(AppStrings.Moderation.reject) {
                    Task {
                        await rejectAction()
                    }
                }
                .buttonStyle(.bordered)
                .tint(AppTheme.accentDestructive)
            }
            .disabled(isProcessing)
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    NavigationStack {
        ModerationToolsView(
            newsRepository: MockNewsRepository(),
            eventRepository: MockEventRepository(),
            organizationRepository: MockOrganizationRepository(),
            marketplaceRepository: MockMarketplaceRepository()
        )
    }
    .environmentObject(AuthState())
}
