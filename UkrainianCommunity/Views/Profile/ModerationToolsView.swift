import Combine
import SwiftUI

extension Notification.Name {
    static let moderationStatusDidChange = Notification.Name("moderationStatusDidChange")
}

private enum ModeratedContentType: String {
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
    private let organizationID: String?
    private var loadTask: Task<Void, Never>?
    private var hasLoaded = false
    private var allowedSections: Set<AppSection> = []

    init(
        newsRepository: NewsRepository,
        eventRepository: EventRepository,
        organizationRepository: OrganizationRepository,
        organizationID: String? = nil
    ) {
        self.newsRepository = newsRepository
        self.eventRepository = eventRepository
        self.organizationRepository = organizationRepository
        self.organizationID = organizationID
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

        if let organizationID {
            loadedItems.append(contentsOf: makeItems(from: try await newsRepository.fetchOrganizationModerationNews(organizationID: organizationID)))
            loadedItems.append(contentsOf: makeItems(from: try await eventRepository.fetchOrganizationModerationEvents(organizationID: organizationID)))
            return loadedItems.sorted { $0.createdAt > $1.createdAt }
        }

        if allowedSections.contains(.news) {
            loadedItems.append(contentsOf: makeItems(from: try await newsRepository.fetchPendingNews()))
        }
        if allowedSections.contains(.events) {
            loadedItems.append(contentsOf: makeItems(from: try await eventRepository.fetchPendingEvents()))
        }
        if allowedSections.contains(.organizations) {
            loadedItems.append(contentsOf: makeItems(from: try await organizationRepository.fetchPendingOrganizations()))
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

}

struct ModerationToolsView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel: ModerationQueueViewModel
    private let organizationID: String?

    init(
        organizationID: String? = nil,
        newsRepository: NewsRepository = FirestoreNewsRepository(),
        eventRepository: EventRepository = FirestoreEventRepository(),
        organizationRepository: OrganizationRepository = FirestoreOrganizationRepository()
    ) {
        self.organizationID = organizationID
        _viewModel = StateObject(wrappedValue: ModerationQueueViewModel(
            newsRepository: newsRepository,
            eventRepository: eventRepository,
            organizationRepository: organizationRepository,
            organizationID: organizationID
        ))
    }

    private var canAccessModeration: Bool {
        guard let user = authState.user else { return false }
        if let organizationID {
            return PermissionService.canModerateOrganizationContent(organizationId: organizationID, user: user)
        }
        return PermissionService.canModerate(section: .news, user: user)
            || PermissionService.canModerate(section: .events, user: user)
            || PermissionService.canModerate(section: .organizations, user: user)
    }

    private var allowedSections: Set<AppSection> {
        guard let user = authState.user else { return [] }
        if organizationID != nil {
            return [.news, .events]
        }
        return PermissionService.moderatedSections(for: user)
            .intersection([.news, .events, .organizations])
    }

    private var screenTitle: String {
        organizationID == nil ? AppStrings.Moderation.title : "Модерація організації"
    }

    private var emptyMessage: String {
        organizationID == nil ? AppStrings.Moderation.empty : "Немає матеріалів організації на перевірці"
    }

    var body: some View {
        ZStack {
            AppBackgroundView()
                .allowsHitTesting(false)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    AppBrandHeader {
                        AppNotificationBellButton()
                    }

                    AppGroupedContentPlane {
                        moderationContent
                    }
                }
                .padding(.horizontal, AppTheme.pageHorizontal)
                .padding(.top, AppTheme.sectionSpacing)
                .padding(.bottom, AppTheme.homeBottomContentPadding)
            }
        }
        .tint(AppTheme.accentPrimary)
        .navigationTitle(screenTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.setAllowedSections(allowedSections)
            await viewModel.loadIfNeeded()
        }
        .onChange(of: allowedSections) { _, newSections in
            viewModel.setAllowedSections(newSections)
            viewModel.reload()
        }
    }

    @ViewBuilder
    private var moderationContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
            AppEditorSectionCard {
                SectionHeaderBlock(
                    title: screenTitle,
                    subtitle: AppStrings.Moderation.subtitle
                )
            }

            if !canAccessModeration {
                UnifiedEmptyStateCard(
                    systemImage: "lock.shield",
                    title: screenTitle,
                    message: AppStrings.Moderation.loadPermissionError
                )
            } else if viewModel.isLoading && viewModel.items.isEmpty {
                LoadingStateCard(title: AppStrings.Profile.reviewPendingContent)
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
            } else if viewModel.items.isEmpty {
                UnifiedEmptyStateCard(
                    systemImage: "checkmark.shield",
                    title: screenTitle,
                    message: emptyMessage
                )
            } else {
                if let error = viewModel.error {
                    InlineMessageCard(style: .error, message: errorMessage(for: error))
                }

                VStack(spacing: AppTheme.feedRowSpacing) {
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
            }
        }
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
        AppEditorSectionCard {
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
                        .foregroundStyle(AppTheme.accentDestructive)
                        .frame(maxWidth: .infinity)
                        .frame(height: AppTheme.iconButtonSize)
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
        }
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
