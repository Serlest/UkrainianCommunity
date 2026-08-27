import SwiftUI

private enum OwnerContentPlanningFilter: String, CaseIterable, Identifiable {
    case drafts
    case scheduled
    case attention

    var id: String { rawValue }

    var title: String {
        switch self {
        case .drafts: AppStrings.ContentPlanning.drafts
        case .scheduled: AppStrings.ContentPlanning.scheduled
        case .attention: AppStrings.ContentPlanning.attention
        }
    }
}

struct OwnerContentPlanningView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel: OwnerContentPlanningViewModel
    @State private var selectedFilter: OwnerContentPlanningFilter = .drafts
    @State private var selectedDraft: OwnerContentDraft?
    @State private var pendingArchiveDraft: OwnerContentDraft?
    @State private var pendingDeleteDraft: OwnerContentDraft?

    private let newsRepository: NewsRepository
    private let eventRepository: EventRepository
    private let organizationRepository: OrganizationRepository

    init(
        draftRepository: OwnerContentDraftRepository,
        newsRepository: NewsRepository,
        eventRepository: EventRepository,
        organizationRepository: OrganizationRepository
    ) {
        _viewModel = StateObject(wrappedValue: OwnerContentPlanningViewModel(repository: draftRepository))
        self.newsRepository = newsRepository
        self.eventRepository = eventRepository
        self.organizationRepository = organizationRepository
    }

    var body: some View {
        PushedScreenShell(
            title: AppStrings.ContentPlanning.title,
            subtitle: AppStrings.ContentPlanning.subtitle
        ) {
            VStack(spacing: AppTheme.feedRowSpacing) {
                Picker(AppStrings.ContentPlanning.filter, selection: $selectedFilter) {
                    ForEach(OwnerContentPlanningFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("contentPlanning.filter")

                if let errorMessage = viewModel.errorMessage {
                    InlineMessageCard(style: .error, message: errorMessage)
                }

                if viewModel.isLoading && viewModel.drafts.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else if filteredDrafts.isEmpty {
                    ProfileDestinationEmptyStateCard(
                        systemImage: emptySystemImage,
                        title: AppStrings.ContentPlanning.emptyTitle,
                        message: AppStrings.ContentPlanning.emptyMessage
                    )
                } else {
                    LazyVStack(spacing: AppTheme.feedRowSpacing) {
                        ForEach(filteredDrafts) { draft in
                            OwnerContentDraftCard(
                                draft: draft,
                                openAction: { selectedDraft = draft },
                                archiveAction: { pendingArchiveDraft = draft },
                                deleteAction: { pendingDeleteDraft = draft }
                            )
                        }
                    }
                }
            }
            .padding(.bottom, AppTheme.homeBottomContentPadding)
        }
        .task(id: authState.user?.id) {
            guard let user = authState.user, PermissionService.isAppOwner(user: user) else { return }
            viewModel.start(userID: user.id)
        }
        .appRefreshable { await viewModel.refresh() }
        .fullScreenCover(item: $selectedDraft) { draft in
            editor(for: draft)
                .environmentObject(authState)
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
                Task { await viewModel.archive(draft) }
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
                Task { await viewModel.delete(draft) }
            }
            Button(AppStrings.Common.cancel, role: .cancel) { pendingDeleteDraft = nil }
        } message: {
            Text(AppStrings.ContentPlanning.deleteMessage)
        }
    }

    private var filteredDrafts: [OwnerContentDraft] {
        viewModel.drafts.filter { draft in
            switch selectedFilter {
            case .drafts:
                return draft.state == .readyForReview && !draft.requiresAttention
            case .scheduled:
                return draft.state == .scheduled || draft.state == .publishing
            case .attention:
                return draft.requiresAttention
            }
        }
    }

    private var emptySystemImage: String {
        switch selectedFilter {
        case .drafts: "doc.badge.clock"
        case .scheduled: "calendar.badge.clock"
        case .attention: "checkmark.shield"
        }
    }

    @ViewBuilder
    private func editor(for draft: OwnerContentDraft) -> some View {
        switch draft.kind {
        case .news:
            NewsEditorView(
                repository: newsRepository,
                sourceDraft: draft,
                organizationRepository: organizationRepository,
                onPublished: { await finishPublishing(draft) }
            )
        case .event:
            EventEditorView(
                repository: eventRepository,
                sourceDraft: draft,
                organizationRepository: organizationRepository,
                onPublished: { await finishPublishing(draft) }
            )
        }
    }

    private func finishPublishing(_ draft: OwnerContentDraft) async {
        await viewModel.markCompleted(draft)
        selectedDraft = nil
    }
}

private struct OwnerContentDraftCard: View {
    let draft: OwnerContentDraft
    let openAction: () -> Void
    let archiveAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: 12) {
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

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: draft.kind == .news ? "newspaper.fill" : "calendar.badge.plus")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.accentPrimaryForeground)
                        .frame(width: 42, height: 42)
                        .background(AppTheme.accentPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

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
                    }

                    Spacer(minLength: 0)

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

                if !draft.missingFields.isEmpty {
                    Label(AppStrings.ContentPlanning.missingFields(draft.missingFields.count), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.accentWarningForeground)
                }

                if let source = draft.sourceReferences.first {
                    Label(source.title ?? source.url, systemImage: "link")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)
                }

                Button(action: openAction) {
                    Label(AppStrings.ContentPlanning.review, systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .appActionButtonStyle(.primary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("contentPlanning.draft.\(draft.id)")
    }
}
