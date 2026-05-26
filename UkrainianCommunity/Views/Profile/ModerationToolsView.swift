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
    let submittedBy: String?
    let organization: Organization?

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

    func updateStatus(for item: ModerationQueueItem, to newStatus: ModerationStatus, reviewerID: String?) async {
        processingItemIDs.insert(item.id)
        defer { processingItemIDs.remove(item.id) }

        do {
            switch item.type {
            case .news:
                try await newsRepository.updateModerationStatus(id: item.contentID, newStatus: newStatus)
            case .event:
                try await eventRepository.updateModerationStatus(id: item.contentID, newStatus: newStatus)
            case .organization:
                guard newStatus == .approved, let reviewerID else { throw AppError.permissionDenied }
                try await organizationRepository.approveOrganizationRequest(id: item.contentID, reviewerID: reviewerID)
                AppContentChangeBus.postOrganizationsChanged(organizationID: item.contentID)
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

    func requestRevision(for item: ModerationQueueItem, message: String, reviewerID: String?) async {
        guard item.type == .organization, let reviewerID else { return }
        processingItemIDs.insert(item.id)
        defer { processingItemIDs.remove(item.id) }

        do {
            try await organizationRepository.requestOrganizationRevision(id: item.contentID, message: message, reviewerID: reviewerID)
            items.removeAll { $0.id == item.id }
            error = nil
            AppContentChangeBus.postOrganizationsChanged(organizationID: item.contentID)
            NotificationCenter.default.post(name: .moderationStatusDidChange, object: nil)
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    func rejectOrganizationRequest(for item: ModerationQueueItem, reason: String, reviewerID: String?) async {
        guard item.type == .organization, let reviewerID else { return }
        processingItemIDs.insert(item.id)
        defer { processingItemIDs.remove(item.id) }

        do {
            try await organizationRepository.rejectOrganizationRequest(id: item.contentID, reason: reason, reviewerID: reviewerID)
            items.removeAll { $0.id == item.id }
            error = nil
            AppContentChangeBus.postOrganizationsChanged(organizationID: item.contentID)
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
                createdAt: $0.createdAt,
                submittedBy: nil,
                organization: nil
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
                submittedBy: nil,
                organization: nil
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
                createdAt: $0.createdAt,
                submittedBy: $0.submittedByDisplayName ?? $0.submittedByUserId,
                organization: $0
            )
        }
    }

}

struct ModerationToolsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel: ModerationQueueViewModel
    @State private var selectedOrganizationRequest: ModerationQueueItem?
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
        organizationID == nil ? AppStrings.Moderation.title : AppStrings.Moderation.organizationTitle
    }

    private var emptyMessage: String {
        organizationID == nil ? AppStrings.Moderation.empty : AppStrings.Moderation.organizationEmpty
    }

    var body: some View {
        ZStack {
            AppBackgroundView()
                .allowsHitTesting(false)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    AppCenteredBrandHeader {
                        AppGlassIconButton(systemImage: "chevron.left", accessibilityLabel: AppStrings.Common.back) {
                            dismiss()
                        }
                    } trailingContent: {
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
            .refreshable {
                await viewModel.refresh()
            }
        }
        .tint(AppTheme.accentPrimary)
        .navigationTitle(screenTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            viewModel.setAllowedSections(allowedSections)
            await viewModel.loadIfNeeded()
        }
        .onChange(of: allowedSections) { _, newSections in
            viewModel.setAllowedSections(newSections)
            viewModel.reload()
        }
        .sheet(item: $selectedOrganizationRequest) { item in
            ModerationOrganizationRequestSheet(
                item: item,
                isProcessing: viewModel.processingItemIDs.contains(item.id),
                approveAction: {
                    await viewModel.updateStatus(for: item, to: .approved, reviewerID: authState.user?.id)
                    selectedOrganizationRequest = nil
                },
                revisionAction: { message in
                    await viewModel.requestRevision(for: item, message: message, reviewerID: authState.user?.id)
                    selectedOrganizationRequest = nil
                },
                rejectAction: { reason in
                    await viewModel.rejectOrganizationRequest(for: item, reason: reason, reviewerID: authState.user?.id)
                    selectedOrganizationRequest = nil
                }
            )
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
                                await viewModel.updateStatus(for: item, to: .approved, reviewerID: authState.user?.id)
                            },
                            rejectAction: {
                                if item.type == .organization {
                                    selectedOrganizationRequest = item
                                } else {
                                    await viewModel.updateStatus(for: item, to: .rejected, reviewerID: authState.user?.id)
                                }
                            },
                            detailsAction: item.type == .organization ? {
                                selectedOrganizationRequest = item
                            } : nil
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
    let detailsAction: (() -> Void)?

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

            if let submittedBy = item.submittedBy {
                Text("\(AppStrings.Moderation.submittedBy): \(submittedBy)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            HStack(spacing: 12) {
                if let detailsAction {
                    Button(action: detailsAction) {
                        Label(AppStrings.Moderation.openRequest, systemImage: "doc.text.magnifyingglass")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: AppTheme.iconButtonSize)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isProcessing)
                }

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

private struct ModerationOrganizationRequestSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: ModerationQueueItem
    let isProcessing: Bool
    let approveAction: () async -> Void
    let revisionAction: (String) async -> Void
    let rejectAction: (String) async -> Void
    @State private var reviewMessage = ""
    @State private var rejectionReason = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    if let organization = item.organization {
                        requestSummaryCard(for: organization)
                        mainInformationCard(for: organization)
                        descriptionCard(for: organization)
                        contactsCard(for: organization)
                        applicantCard(for: organization)
                    } else {
                        requestFallbackCard
                    }

                    AppEditorSectionCard {
                        VStack(alignment: .leading, spacing: 10) {
                            AppEditorSectionTitle(title: AppStrings.Moderation.revisionMessage)
                            TextField(AppStrings.Moderation.revisionMessage, text: $reviewMessage, axis: .vertical)
                                .lineLimit(3...6)
                                .textFieldStyle(.roundedBorder)
                            PrimaryActionButton(
                                title: AppStrings.Moderation.requestRevision,
                                isEnabled: !isProcessing && !reviewMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                isLoading: isProcessing,
                                systemImage: "arrow.uturn.backward"
                            ) {
                                Task { await revisionAction(reviewMessage) }
                            }
                        }
                    }

                    AppEditorSectionCard {
                        VStack(alignment: .leading, spacing: 10) {
                            AppEditorSectionTitle(title: AppStrings.Moderation.rejectionReason)
                            TextField(AppStrings.Moderation.rejectionReason, text: $rejectionReason, axis: .vertical)
                                .lineLimit(3...6)
                                .textFieldStyle(.roundedBorder)
                            Button(role: .destructive) {
                                Task { await rejectAction(rejectionReason) }
                            } label: {
                                Label(AppStrings.Moderation.reject, systemImage: "trash")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: AppTheme.iconButtonSize)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isProcessing || rejectionReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }

                    PrimaryActionButton(
                        title: AppStrings.Moderation.approve,
                        isEnabled: !isProcessing,
                        isLoading: isProcessing,
                        systemImage: "checkmark.seal"
                    ) {
                        Task { await approveAction() }
                    }
                }
                .padding(AppTheme.pageHorizontal)
            }
            .background(AppBackgroundView())
            .navigationTitle(AppStrings.Moderation.organizationRequest)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.Common.cancel) {
                        dismiss()
                    }
                }
            }
        }
    }

    private func requestSummaryCard(for organization: Organization) -> some View {
        AppEditorSectionCard {
            HStack(alignment: .top, spacing: 12) {
                AppFeedThumbnail(
                    imageURL: organization.coverURL ?? organization.imageURL,
                    fallbackSystemImage: "building.2",
                    tint: AppTheme.accentPrimary,
                    fill: AppTheme.accentPrimary.opacity(0.10),
                    size: 64,
                    source: "ModerationOrganizationRequestSheet.cover"
                )

                if let logoURL = organization.logoURL, logoURL != organization.coverURL {
                    AppFeedThumbnail(
                        imageURL: logoURL,
                        fallbackSystemImage: "photo",
                        tint: AppTheme.accentPrimary,
                        fill: AppTheme.accentPrimary.opacity(0.10),
                        size: 48,
                        source: "ModerationOrganizationRequestSheet.logo"
                    )
                }

                VStack(alignment: .leading, spacing: 7) {
                    AppEditorSectionTitle(title: organization.name)
                    Text(organization.shortDescription)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                    if let reviewMessage = organization.reviewMessage {
                        InlineMessageCard(style: .info, message: reviewMessage)
                    }
                    if let rejectionReason = organization.rejectionReason {
                        InlineMessageCard(style: .error, message: rejectionReason)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func mainInformationCard(for organization: Organization) -> some View {
        detailSection(title: AppStrings.Moderation.requestMainInformation) {
            detailRow(AppStrings.Organizations.categoryTitle, organization.organizationType)
            detailRow(AppStrings.Common.city, organization.city)
            detailRow(AppStrings.Moderation.federalState, organization.federalState?.rawValue)
            detailRow(AppStrings.Organizations.fieldAddress, organization.address)
            if !organization.languages.isEmpty {
                detailRow(AppStrings.Organizations.languagesTitle, organization.languages.joined(separator: ", "))
            }
        }
    }

    private func descriptionCard(for organization: Organization) -> some View {
        detailSection(title: AppStrings.Moderation.requestDescription) {
            detailRow(AppStrings.Moderation.shortDescription, organization.shortDescription)
            detailRow(AppStrings.Moderation.fullDescription, organization.fullDescription)
            detailRow(AppStrings.Organizations.fieldMissionStatement, organization.missionStatement)
        }
    }

    private func contactsCard(for organization: Organization) -> some View {
        detailSection(title: AppStrings.Moderation.requestContacts) {
            detailRow(AppStrings.Organizations.fieldContactEmail, organization.contactEmail ?? organization.email)
            detailRow(AppStrings.Organizations.phonePlaceholder, organization.phone)
            detailRow(AppStrings.Common.website, organization.website)
            detailRow(AppStrings.Organizations.fieldTelegramURL, organization.telegramURL)
            detailRow(AppStrings.Organizations.fieldDonationURL, organization.donationURL)
            detailRow(AppStrings.Organizations.fieldContactPersonDisplay, organization.contactPerson)
            if !organization.socialLinks.isEmpty {
                detailRow(
                    AppStrings.Moderation.socialLinks,
                    organization.socialLinks
                        .sorted { $0.key < $1.key }
                        .map { "\($0.key): \($0.value)" }
                        .joined(separator: "\n")
                )
            }
        }
    }

    private func applicantCard(for organization: Organization) -> some View {
        detailSection(title: AppStrings.Moderation.requestApplicant) {
            detailRow(AppStrings.Moderation.submittedBy, organization.submittedByDisplayName ?? item.submittedBy)
            detailRow(AppStrings.Moderation.submittedAt, organization.submittedAt.map { LocalizationStore.dateString(from: $0) })
            detailRow(AppStrings.Moderation.submittedByUserId, organization.submittedByUserId)
        }
    }

    private var requestFallbackCard: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: 10) {
                AppEditorSectionTitle(title: item.title)
                Text(item.summary)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                if let submittedBy = item.submittedBy {
                    Text("\(AppStrings.Moderation.submittedBy): \(submittedBy)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
    }

    private func detailSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: 10) {
                AppEditorSectionTitle(title: title)
                content()
            }
        }
    }

    @ViewBuilder
    private func detailRow(_ title: String, _ value: String?) -> some View {
        if let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
