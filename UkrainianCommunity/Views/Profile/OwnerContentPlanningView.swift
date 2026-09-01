import SwiftUI

struct OwnerContentPlanningView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel: OwnerContentPlanningViewModel
    @State private var selectedSection: OwnerContentPlanningSection = .drafts
    @State private var selectedDraft: OwnerContentDraft?
    @State private var selectedReceipt: OwnerContentDraft?
    @State private var pendingArchiveDraft: OwnerContentDraft?
    @State private var pendingDeleteDraft: OwnerContentDraft?
    @State private var handledDeepLinkID: String?

    private let initialDraftID: String?
    private let newsRepository: NewsRepository
    private let eventRepository: EventRepository
    private let organizationRepository: OrganizationRepository
    private let onDraftOpened: (OwnerContentDraft) -> Void
    private let onOpenPublishedContent: (OwnerContentDraftKind, String) -> Void

    init(
        draftRepository: OwnerContentDraftRepository,
        newsRepository: NewsRepository,
        eventRepository: EventRepository,
        organizationRepository: OrganizationRepository,
        initialDraftID: String? = nil,
        onDraftOpened: @escaping (OwnerContentDraft) -> Void = { _ in },
        onOpenPublishedContent: @escaping (OwnerContentDraftKind, String) -> Void = { _, _ in }
    ) {
        _viewModel = StateObject(wrappedValue: OwnerContentPlanningViewModel(repository: draftRepository))
        self.newsRepository = newsRepository
        self.eventRepository = eventRepository
        self.organizationRepository = organizationRepository
        self.initialDraftID = initialDraftID
        self.onDraftOpened = onDraftOpened
        self.onOpenPublishedContent = onOpenPublishedContent
    }

    var body: some View {
        PushedScreenShell(
            title: AppStrings.ContentPlanning.title,
            subtitle: AppStrings.ContentPlanning.subtitle
        ) {
            VStack(spacing: AppTheme.feedRowSpacing) {
                sectionPicker
                sectionContent
            }
            .padding(.bottom, AppTheme.homeBottomContentPadding)
        }
        .accessibilityIdentifier("screen.contentPlanning")
        .task(id: activeUserID) {
            guard let userID = activeUserID else {
                viewModel.stop()
                return
            }
            viewModel.start(userID: userID)
            await viewModel.load(selectedSection, userID: userID)
            await handleInitialDeepLinkIfNeeded()
        }
        .task(id: "\(activeUserID ?? "none")|\(selectedSection.rawValue)") {
            guard let userID = activeUserID else { return }
            await viewModel.load(selectedSection, userID: userID)
        }
        .appRefreshable { await viewModel.refresh(selectedSection) }
        .fullScreenCover(item: $selectedDraft) { draft in
            editor(for: draft)
                .environmentObject(authState)
        }
        .sheet(item: $selectedReceipt) { draft in
            OwnerContentHistoryReceiptView(
                draft: draft,
                openPublishedContent: openPublishedContent
            )
        }
        .confirmationDialog(
            AppStrings.ContentPlanning.archiveTitle,
            isPresented: Binding(
                get: { pendingArchiveDraft != nil },
                set: { if !$0 { pendingArchiveDraft = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(AppStrings.ContentPlanning.archive, role: .destructive) {
                guard let draft = pendingArchiveDraft else { return }
                pendingArchiveDraft = nil
                Task { _ = await viewModel.archive(draft) }
            }
            Button(AppStrings.Common.cancel, role: .cancel) { pendingArchiveDraft = nil }
        } message: {
            Text(AppStrings.ContentPlanning.archiveMessage)
        }
        .confirmationDialog(
            AppStrings.ContentPlanning.deleteTitle,
            isPresented: Binding(
                get: { pendingDeleteDraft != nil },
                set: { if !$0 { pendingDeleteDraft = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(AppStrings.ContentPlanning.delete, role: .destructive) {
                guard let draft = pendingDeleteDraft else { return }
                pendingDeleteDraft = nil
                Task { _ = await viewModel.delete(draft) }
            }
            Button(AppStrings.Common.cancel, role: .cancel) { pendingDeleteDraft = nil }
        } message: {
            Text(AppStrings.ContentPlanning.deleteMessage)
        }
    }

    private var activeUserID: String? {
        guard let user = authState.user, PermissionService.isAppOwner(user: user) else { return nil }
        return user.id
    }

    private var sectionSnapshot: OwnerContentPlanningSectionSnapshot {
        viewModel.snapshot(for: selectedSection)
    }

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(OwnerContentPlanningSection.allCases) { section in
                    Button {
                        selectedSection = section
                    } label: {
                        Text(sectionTitle(section))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(
                                selectedSection == section
                                    ? AppTheme.accentPrimaryForeground
                                    : AppTheme.textSecondary
                            )
                            .padding(.horizontal, 14)
                            .frame(minHeight: AppTheme.minimumInteractiveTarget)
                            .background(
                                selectedSection == section
                                    ? AppTheme.accentPrimary.opacity(0.14)
                                    : AppTheme.surfaceSecondary,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
                    .accessibilityIdentifier("contentPlanning.section.\(section.rawValue)")
                }
            }
            .padding(.horizontal, 1)
        }
        .accessibilityLabel(AppStrings.ContentPlanning.filter)
    }

    @ViewBuilder
    private var sectionContent: some View {
        if let actionErrorMessage = viewModel.actionErrorMessage {
            InlineMessageCard(style: .error, message: actionErrorMessage)
        }
        if let deepLinkError = viewModel.deepLinkError {
            deepLinkErrorCard(deepLinkError)
        }

        if sectionSnapshot.isLoading && sectionSnapshot.items.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 180)
                .accessibilityLabel(AppStrings.ContentPlanning.loading)
        } else if let error = sectionSnapshot.error, sectionSnapshot.items.isEmpty {
            planningErrorCard(error)
        } else if sectionSnapshot.items.isEmpty {
            ProfileDestinationEmptyStateCard(
                systemImage: emptySystemImage,
                title: emptyTitle,
                message: emptyMessage
            )
        } else {
            LazyVStack(spacing: AppTheme.feedRowSpacing) {
                ForEach(sectionSnapshot.items) { draft in
                    if selectedSection == .history {
                        OwnerContentHistoryCard(
                            draft: draft,
                            showReceipt: { selectedReceipt = draft },
                            openPublishedContent: openPublishedContent,
                            deleteAction: { pendingDeleteDraft = draft }
                        )
                    } else {
                        OwnerContentDraftCard(
                            draft: draft,
                            isPerformingAction: viewModel.isPerformingAction(on: draft.id),
                            openAction: { openDraft(draft) },
                            archiveAction: { pendingArchiveDraft = draft },
                            deleteAction: { pendingDeleteDraft = draft }
                        )
                    }
                }

                if sectionSnapshot.isLoadingNextPage {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel(AppStrings.ContentPlanning.loadingMore)
                } else if sectionSnapshot.hasMore, let lastID = sectionSnapshot.items.last?.id {
                    Color.clear
                        .frame(height: 1)
                        .task(id: lastID) {
                            await viewModel.loadNextPageIfNeeded(selectedSection, currentItemID: lastID)
                        }
                }

                if let error = sectionSnapshot.error, !sectionSnapshot.items.isEmpty {
                    planningErrorCard(error)
                }
            }
        }
    }

    private func planningErrorCard(_ error: AppError) -> some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(readableErrorText(error), systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.accentDestructiveForeground)
                    .fixedSize(horizontal: false, vertical: true)
                Button(AppStrings.ContentPlanning.retry) {
                    Task { await viewModel.refresh(selectedSection) }
                }
                .appActionButtonStyle(.secondary)
            }
        }
    }

    private func deepLinkErrorCard(_ error: AppError) -> some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: 12) {
                Label(readableErrorText(error), systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.accentDestructiveForeground)
                    .fixedSize(horizontal: false, vertical: true)
                Button(AppStrings.ContentPlanning.retry) {
                    Task { await handleInitialDeepLinkIfNeeded() }
                }
                .appActionButtonStyle(.secondary)
            }
        }
    }

    private func readableErrorText(_ error: AppError) -> String {
        switch error {
        case .notFound:
            AppStrings.ContentPlanning.deepLinkNotFound
        case .network:
            AppStrings.ContentPlanning.offline
        case .permissionDenied:
            AppStrings.ContentPlanning.accessDenied
        default:
            AppStrings.ContentPlanning.loadFailed
        }
    }

    private func sectionTitle(_ section: OwnerContentPlanningSection) -> String {
        switch section {
        case .drafts: AppStrings.ContentPlanning.drafts
        case .scheduled: AppStrings.ContentPlanning.scheduled
        case .attention: AppStrings.ContentPlanning.attention
        case .history: AppStrings.ContentPlanning.history
        }
    }

    private var emptySystemImage: String {
        switch selectedSection {
        case .drafts: "doc.badge.clock"
        case .scheduled: "calendar.badge.clock"
        case .attention: "checkmark.shield"
        case .history: "clock.arrow.circlepath"
        }
    }

    private var emptyTitle: String {
        switch selectedSection {
        case .drafts: AppStrings.ContentPlanning.emptyDraftsTitle
        case .scheduled: AppStrings.ContentPlanning.emptyScheduledTitle
        case .attention: AppStrings.ContentPlanning.emptyAttentionTitle
        case .history: AppStrings.ContentPlanning.emptyHistoryTitle
        }
    }

    private var emptyMessage: String {
        switch selectedSection {
        case .drafts: AppStrings.ContentPlanning.emptyDraftsMessage
        case .scheduled: AppStrings.ContentPlanning.emptyScheduledMessage
        case .attention: AppStrings.ContentPlanning.emptyAttentionMessage
        case .history: AppStrings.ContentPlanning.emptyHistoryMessage
        }
    }

    private func handleInitialDeepLinkIfNeeded() async {
        guard let initialDraftID, handledDeepLinkID != initialDraftID else { return }
        guard let draft = await viewModel.fetchDraftForDeepLink(initialDraftID) else { return }
        handledDeepLinkID = initialDraftID
        viewModel.reveal(draft)
        selectedSection = draft.planningSection
        onDraftOpened(draft)
        if draft.isEditableInPlanning {
            selectedDraft = draft
        } else {
            selectedReceipt = draft
        }
    }

    private func openDraft(_ draft: OwnerContentDraft) {
        guard draft.isEditableInPlanning else {
            selectedReceipt = draft
            return
        }
        onDraftOpened(draft)
        selectedDraft = draft
    }

    private func openPublishedContent(_ kind: OwnerContentDraftKind, _ contentID: String) {
        selectedReceipt = nil
        onOpenPublishedContent(kind, contentID)
    }

    @ViewBuilder
    private func editor(for draft: OwnerContentDraft) -> some View {
        let callbacks = OwnerContentPlanningPublicationCallbacks(
            begin: { await viewModel.beginPublishing(draft) },
            fail: { message in await viewModel.failPublishing(draft, message: message) }
        )
        switch draft.kind {
        case .news:
            NewsEditorView(
                repository: newsRepository,
                sourceDraft: draft,
                organizationRepository: organizationRepository,
                planningPublicationCallbacks: callbacks,
                onPublished: { publication in
                    await viewModel.finishPublishing(draft, publication: publication)
                }
            )
        case .event:
            EventEditorView(
                repository: eventRepository,
                sourceDraft: draft,
                organizationRepository: organizationRepository,
                planningPublicationCallbacks: callbacks,
                onPublished: { publication in
                    await viewModel.finishPublishing(draft, publication: publication)
                }
            )
        }
    }
}

private struct OwnerContentDraftCard: View {
    let draft: OwnerContentDraft
    let isPerformingAction: Bool
    let openAction: () -> Void
    let archiveAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: 12) {
                planningImage
                HStack(alignment: .top, spacing: 12) {
                    kindIcon
                    VStack(alignment: .leading, spacing: 4) {
                        Text(draft.kind == .news ? AppStrings.ContentPlanning.news : AppStrings.ContentPlanning.event)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(draft.requiresAttention ? AppTheme.accentWarningForeground : AppTheme.accentPrimaryForeground)
                        Text(draft.title)
                            .font(AppTheme.cardTitleFont)
                            .foregroundStyle(AppTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(draft.updatedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                        if let scheduledAt = draft.scheduledAt,
                           draft.state == .scheduled || draft.state == .publishing {
                            Label(
                                scheduledAt.formatted(date: .abbreviated, time: .shortened),
                                systemImage: "calendar.badge.clock"
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.accentPrimaryForeground)
                        }
                    }
                    Spacer(minLength: 0)
                    actionsMenu
                }

                if draft.requiresAttention {
                    ContentPlanningAttentionCard(messages: draft.attentionMessages, compact: true)
                }
                if let source = draft.sourceReferences.first {
                    Label(source.title ?? source.url, systemImage: "link")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)
                }
                if draft.isEditableInPlanning {
                    Button(action: openAction) {
                        Label(AppStrings.ContentPlanning.review, systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .appActionButtonStyle(.primary)
                    .disabled(isPerformingAction)
                } else if draft.state == .publishing {
                    Label(AppStrings.ContentPlanning.publishingInProgress, systemImage: "arrow.triangle.2.circlepath")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("contentPlanning.draft.\(draft.id)")
    }

    @ViewBuilder
    private var planningImage: some View {
        if let generatedImage = draft.generatedImage {
            RemoteImageView(
                imageURL: generatedImage.url,
                height: 180,
                cornerRadius: AppTheme.imageRadius,
                source: "OwnerContentDraftCard",
                placeholderStyle: .glassSkeleton
            )
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipped()
            .accessibilityLabel(generatedImage.alternativeText ?? draft.title)
        }
    }

    private var kindIcon: some View {
        Image(systemName: draft.kind == .news ? "newspaper.fill" : "calendar.badge.plus")
            .font(.headline.weight(.semibold))
            .foregroundStyle(AppTheme.accentPrimaryForeground)
            .frame(width: 42, height: 42)
            .background(AppTheme.accentPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var actionsMenu: some View {
        if draft.isEditableInPlanning {
            if isPerformingAction {
                ProgressView()
                    .frame(width: AppTheme.minimumInteractiveTarget, height: AppTheme.minimumInteractiveTarget)
            } else {
                Menu {
                    Button(action: archiveAction) {
                        Label(AppStrings.ContentPlanning.archive, systemImage: "archivebox")
                    }
                    Divider()
                    Button(role: .destructive, action: deleteAction) {
                        Label(AppStrings.ContentPlanning.delete, systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: AppTheme.minimumInteractiveTarget, height: AppTheme.minimumInteractiveTarget)
                }
                .accessibilityLabel(AppStrings.ContentPlanning.moreActions)
            }
        }
    }
}

private struct OwnerContentHistoryCard: View {
    let draft: OwnerContentDraft
    let showReceipt: () -> Void
    let openPublishedContent: (OwnerContentDraftKind, String) -> Void
    let deleteAction: () -> Void

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: statusIcon)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(statusColor)
                        .frame(width: 42, height: 42)
                        .background(statusColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(statusTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(statusColor)
                        Text(draft.title)
                            .font(AppTheme.cardTitleFont)
                            .foregroundStyle(AppTheme.textPrimary)
                        Text(draft.historyDate.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                        if let organizationName = draft.publishedOrganizationName {
                            Text(organizationName)
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 10) {
                    Button(AppStrings.ContentPlanning.viewReceipt, action: showReceipt)
                        .appActionButtonStyle(.secondary)
                    if let contentID = draft.publishedContentID,
                       let kind = draft.publishedContentKind {
                        Button(AppStrings.ContentPlanning.openPublished) {
                            openPublishedContent(kind, contentID)
                        }
                        .appActionButtonStyle(.primary)
                    } else if draft.state == .archived {
                        Button(role: .destructive, action: deleteAction) {
                            Label(AppStrings.ContentPlanning.delete, systemImage: "trash")
                        }
                        .appActionButtonStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityIdentifier("contentPlanning.history.\(draft.id)")
    }

    private var statusTitle: String {
        draft.state == .archived
            ? AppStrings.ContentPlanning.statusArchived
            : AppStrings.ContentPlanning.statusPublished
    }

    private var statusIcon: String {
        draft.state == .archived ? "archivebox.fill" : "checkmark.seal.fill"
    }

    private var statusColor: Color {
        draft.state == .archived ? AppTheme.textSecondary : AppTheme.accentSuccessForeground
    }
}

private struct OwnerContentHistoryReceiptView: View {
    @Environment(\.dismiss) private var dismiss
    let draft: OwnerContentDraft
    let openPublishedContent: (OwnerContentDraftKind, String) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                AppEditorSectionCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Label(statusTitle, systemImage: statusIcon)
                            .font(.headline)
                            .foregroundStyle(statusColor)
                        Text(draft.title)
                            .font(AppTheme.cardTitleFont)
                            .foregroundStyle(AppTheme.textPrimary)
                        receiptRow(AppStrings.ContentPlanning.receiptDate, draft.historyDate.formatted(date: .long, time: .shortened))
                        receiptRow(
                            AppStrings.ContentPlanning.receiptKind,
                            draft.kind == .news ? AppStrings.ContentPlanning.news : AppStrings.ContentPlanning.event
                        )
                        if let organizationName = draft.publishedOrganizationName {
                            receiptRow(AppStrings.ContentPlanning.receiptOrganization, organizationName)
                        }
                        if let outcome = draft.publicationOutcome {
                            receiptRow(AppStrings.ContentPlanning.receiptOutcome, outcomeTitle(outcome))
                        }
                        if let contentID = draft.publishedContentID,
                           let kind = draft.publishedContentKind {
                            Button(AppStrings.ContentPlanning.openPublished) {
                                dismiss()
                                openPublishedContent(kind, contentID)
                            }
                            .appActionButtonStyle(.primary)
                        } else if draft.state == .completed {
                            InlineMessageCard(
                                style: .info,
                                message: AppStrings.ContentPlanning.unresolvedHistoryLink
                            )
                        }
                    }
                }
                .padding()
            }
            .background(AppTheme.groupedBackground.ignoresSafeArea())
            .navigationTitle(AppStrings.ContentPlanning.receiptTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.Common.done) { dismiss() }
                }
            }
        }
    }

    private func receiptRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
            Text(value)
                .font(.body)
                .foregroundStyle(AppTheme.textPrimary)
        }
    }

    private var statusTitle: String {
        draft.state == .archived
            ? AppStrings.ContentPlanning.statusArchived
            : AppStrings.ContentPlanning.statusPublished
    }

    private var statusIcon: String {
        draft.state == .archived ? "archivebox.fill" : "checkmark.seal.fill"
    }

    private var statusColor: Color {
        draft.state == .archived ? AppTheme.textSecondary : AppTheme.accentSuccessForeground
    }

    private func outcomeTitle(_ outcome: OwnerContentPublicationOutcome) -> String {
        switch outcome {
        case .approved: AppStrings.ContentPlanning.outcomeApproved
        case .pendingReview: AppStrings.ContentPlanning.outcomePendingReview
        case .scheduled: AppStrings.ContentPlanning.outcomeScheduled
        case .archived: AppStrings.ContentPlanning.outcomeArchived
        case .unresolved: AppStrings.ContentPlanning.outcomeUnresolved
        }
    }
}
