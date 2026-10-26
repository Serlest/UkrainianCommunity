import SwiftUI

struct NotificationInboxView: View {
    @ObservedObject var viewModel: NotificationInboxViewModel
    let onNotificationTap: (AppNotification) -> Void
    let onClose: (() -> Void)?
    let subtitle: String?
    @State private var isShowingClearConfirmation = false
    @State private var selectedNotification: AppNotification?
    @State private var pendingDelete: AppNotification?
    @State private var pendingDestination: AppNotification?

    init(
        viewModel: NotificationInboxViewModel,
        onNotificationTap: @escaping (AppNotification) -> Void = { _ in },
        onClose: (() -> Void)? = nil,
        subtitle: String? = nil
    ) {
        self.viewModel = viewModel
        self.onNotificationTap = onNotificationTap
        self.onClose = onClose
        self.subtitle = subtitle
    }

    var body: some View {
        PushedScreenShell(
            title: AppStrings.NotificationInbox.title,
            subtitle: subtitle ?? AppStrings.NotificationInbox.subtitle,
            tabBarHidden: true,
            backAction: onClose
        ) {
            if viewModel.isClearing {
                ProgressView()
                    .controlSize(.small)
                    .disabled(viewModel.isBusy)
                    .accessibilityIdentifier("notificationInbox.clearing")
                    .frame(width: AppTheme.minimumInteractiveTarget, height: AppTheme.minimumInteractiveTarget)
                    .accessibilityLabel(AppStrings.NotificationInbox.clearAll)
            } else if viewModel.canClear {
                AppGlassIconButton(
                    systemImage: "trash",
                    accessibilityLabel: AppStrings.NotificationInbox.clearAll,
                    role: .destructive
                ) {
                    isShowingClearConfirmation = true
                }
                .accessibilityIdentifier("notificationInbox.clearAll")
            }
        } content: {
            headerControls
            if !viewModel.failedLoadMore { retryState }
            inboxContent
            if viewModel.failedLoadMore { retryState }
            if viewModel.isLoadingMore || viewModel.isFilterLoading {
                ProgressView().frame(maxWidth: .infinity)
                    .accessibilityLabel(AppStrings.Common.loading)
            } else if viewModel.hasMoreNotifications {
                Button(AppStrings.NotificationInbox.loadMore) { Task { await viewModel.loadMore() } }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                    .disabled(viewModel.isBusy)
                    .accessibilityIdentifier("notificationInbox.loadMore")
            }
        }
        .accessibilityIdentifier("screen.notificationInbox")
        .appRefreshable {
            await viewModel.refresh()
        }
        .navigationTitle(AppStrings.NotificationInbox.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: Binding(
            get: { selectedNotification != nil },
            set: { if !$0 { selectedNotification = nil } }
        )) {
            if let notification = selectedNotification {
                NotificationDetailView(notification: notification, viewModel: viewModel) { destination in
                    pendingDestination = destination
                }
                .onDisappear(perform: openPendingDestination)
            }
        }
        .onChange(of: viewModel.sessionVersion) { _, _ in
            pendingDestination = nil
            selectedNotification = nil
            pendingDelete = nil
            isShowingClearConfirmation = false
        }
        .task(id: viewModel.selectedFilter) { await viewModel.loadInitialFilterIfNeeded() }
        .alert(AppStrings.NotificationInbox.deleteConfirmationTitle, isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        )) {
            Button(AppStrings.NotificationInbox.delete, role: .destructive) {
                if let notification = pendingDelete { Task { await viewModel.delete(notification) } }
                pendingDelete = nil
            }
            Button(AppStrings.Common.cancel, role: .cancel) { pendingDelete = nil }
        } message: { Text(AppStrings.NotificationInbox.deleteConfirmationMessage) }
        .sheet(isPresented: $isShowingClearConfirmation) {
            NotificationConfirmationSheet(title: AppStrings.NotificationInbox.clearConfirmationTitle,
                message: AppStrings.NotificationInbox.clearConfirmationMessage,
                cancel: { isShowingClearConfirmation = false }) {
                NotificationConfirmationAction(title: AppStrings.NotificationInbox.clearAll,
                    id: "notificationInbox.confirmClear", role: .destructive) {
                    isShowingClearConfirmation = false
                    Task { await viewModel.clearAll() }
                }
                NotificationConfirmationAction(title: AppStrings.Common.cancel,
                    id: "notificationInbox.cancelClear", role: .cancel) { isShowingClearConfirmation = false }
            }
        }
    }

    @ViewBuilder
    private var retryState: some View {
        if let error = viewModel.error {
            InlineMessageCard(style: .error, message: error.localizedDescription)
                .accessibilityIdentifier("notificationInbox.error")
            PrimaryActionButton(title: AppStrings.Action.retry, systemImage: "arrow.clockwise") {
                Task { await viewModel.retry() }
            }
            .disabled(viewModel.isBusy || viewModel.isLoading || viewModel.isLoadingMore || viewModel.isFilterLoading)
            .accessibilityIdentifier("notificationInbox.retry")
        }
    }

    private var headerControls: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                Picker(AppStrings.NotificationInbox.title, selection: $viewModel.selectedFilter) {
                    Text(AppStrings.NotificationInbox.filterAll).tag(NotificationInboxFilter.all)
                    Text(AppStrings.NotificationInbox.filterUnread).tag(NotificationInboxFilter.unread)
                    Text(AppStrings.NotificationInbox.filterArchive).tag(NotificationInboxFilter.archived)
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("notificationInbox.filter")

                if viewModel.unreadCount > 0 {
                    Button {
                        Task { await viewModel.markAllRead() }
                    } label: {
                        HStack {
                            if viewModel.isMarkingAllRead { ProgressView() }
                            Label(AppStrings.NotificationInbox.markAllRead, systemImage: "checkmark.circle")
                                .fixedSize(horizontal: false, vertical: true)
                        }
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.isBusy)
                    .accessibilityIdentifier("notificationInbox.markAllRead")
                }
            }
            .tint(AppTheme.accentPrimaryForeground)
        }
    }

    @ViewBuilder
    private var inboxContent: some View {
        if viewModel.isLoading && viewModel.notifications.isEmpty {
            LoadingStateCard(title: AppStrings.NotificationInbox.title)
        } else if viewModel.isFilterLoading && viewModel.filteredNotifications.isEmpty {
            LoadingStateCard(title: AppStrings.NotificationInbox.title)
        } else if viewModel.filteredNotifications.isEmpty && viewModel.error == nil {
            UnifiedEmptyStateCard(
                systemImage: viewModel.selectedFilter == .archived ? "archivebox" : (viewModel.selectedFilter == .unread ? "checkmark.circle" : "bell"),
                title: emptyTitle,
                message: viewModel.hasMoreNotifications ? AppStrings.NotificationInbox.moreHistory : emptyMessage
            )
        } else {
            LazyVStack(spacing: AppTheme.eventsMetadataSpacing) {
                ForEach(viewModel.filteredNotifications) { notification in
                    NotificationInboxRow(
                        notification: notification,
                        tapAction: {
                            selectedNotification = notification
                        },
                        markReadAction: {
                            Task { await viewModel.markRead(notification) }
                        },
                        markUnreadAction: {
                            Task { await viewModel.markUnread(notification) }
                        },
                        archiveAction: {
                            Task {
                                if notification.isArchived { await viewModel.restore(notification) }
                                else { await viewModel.archive(notification) }
                            }
                        },
                        deleteAction: { pendingDelete = notification },
                        actionsDisabled: viewModel.isBusy
                    )
                    .task {
                        await viewModel.loadMoreIfNeeded(currentNotification: notification)
                    }
                }


            }
        }
    }

    private var emptyTitle: String {
        if viewModel.hasMoreNotifications { return AppStrings.NotificationInbox.historyTitle }
        return switch viewModel.selectedFilter {
        case .all: AppStrings.NotificationInbox.emptyTitle
        case .unread: AppStrings.NotificationInbox.unreadEmptyTitle
        case .archived: AppStrings.NotificationInbox.archiveEmptyTitle
        }
    }

    private func openPendingDestination() {
        guard let notification = pendingDestination else { return }
        pendingDestination = nil
        // Route only after leaving the detail screen, retaining the inbox
        // and its filter until a destination was explicitly requested.
        onNotificationTap(notification)
    }

    private var emptyMessage: String {
        switch viewModel.selectedFilter {
        case .all: AppStrings.NotificationInbox.emptyMessage
        case .unread: AppStrings.NotificationInbox.unreadEmptyMessage
        case .archived: AppStrings.NotificationInbox.archiveEmptyMessage
        }
    }
}

private struct NotificationInboxRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let notification: AppNotification
    let tapAction: () -> Void
    let markReadAction: () -> Void
    let markUnreadAction: () -> Void
    let archiveAction: () -> Void
    let deleteAction: () -> Void
    let actionsDisabled: Bool

    var body: some View {
        AppEditorSectionCard {
            HStack(alignment: .top, spacing: AppTheme.eventsMetadataSpacing) {
                Button(action: tapAction) {
                    Group {
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                                HStack {
                                    notificationIcon
                                    Spacer(minLength: 0)
                                }
                                textContent
                            }
                        } else {
                            HStack(alignment: .top, spacing: AppTheme.eventsMetadataSpacing) {
                                notificationIcon
                                textContent
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(title). \(bodyText). \(dateText)")
                .accessibilityValue(notification.countsAsUnread ? AppStrings.NotificationInbox.filterUnread : "")
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(AppStrings.NotificationInbox.viewDetails)
                .accessibilityIdentifier("notificationInbox.open.\(notification.id)")

                Menu {
                    Button(action: (notification.isRead || notification.isArchived) ? markUnreadAction : markReadAction) {
                        Label(
                            (notification.isRead || notification.isArchived) ? AppStrings.NotificationInbox.markUnread : AppStrings.NotificationInbox.markRead,
                            systemImage: (notification.isRead || notification.isArchived) ? "envelope.badge" : "envelope.open"
                        )
                    }

                    Button(action: archiveAction) {
                        Label(notification.isArchived ? AppStrings.NotificationInbox.restore : AppStrings.NotificationInbox.archive,
                              systemImage: notification.isArchived ? "tray.and.arrow.up" : "archivebox")
                    }

                    Button(role: .destructive, action: deleteAction) {
                        Label(AppStrings.NotificationInbox.delete, systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(
                            width: AppTheme.minimumInteractiveTarget,
                            height: AppTheme.minimumInteractiveTarget
                        )
                }
                .disabled(actionsDisabled)
                .accessibilityLabel(AppStrings.NotificationInbox.moreActions)
                .accessibilityIdentifier("notificationInbox.actions.\(notification.id)")
            }
        }
        .accessibilityAction(named: AppStrings.NotificationInbox.delete) { if !actionsDisabled { deleteAction() } }
    }

    private var notificationIcon: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(iconTint.opacity(notification.countsAsUnread ? 0.16 : 0.10))
                .frame(width: 42, height: 42)

            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(iconTint)
                .frame(width: 42, height: 42)

            if notification.countsAsUnread {
                Circle()
                    .fill(AppTheme.accentDestructive)
                    .frame(width: 9, height: 9)
                    .offset(x: -1, y: 2)
            }
        }
    }

    private var textContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.headline.weight(notification.countsAsUnread ? .semibold : .regular))
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            severityLabel

            Text(bodyText)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)

            Text(dateText)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
        }
    }


    @ViewBuilder
    private var severityLabel: some View {
        if notification.severity != .info {
            Text(severityText)
                .font(.caption2.weight(.bold))
                .foregroundStyle(iconTint)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(iconTint.opacity(0.10), in: Capsule())
                .lineLimit(1)
        }
    }

    private var title: String {
        notification.localizedDisplayContent.title
    }

    private var bodyText: String {
        notification.localizedDisplayContent.body
    }

    private var dateText: String {
        LocalizationStore.dateString(from: notification.createdAt, dateStyle: .medium, timeStyle: .short)
    }

    private var systemImage: String {
        switch notification.type {
        case .commentAdded, .feedbackSubmitted, .feedbackReply:
            return "bubble.left.and.bubble.right"
        case .organizationRequestSubmitted:
            return "building.2.crop.circle"
        case .contentModerationChanged:
            return "checkmark.shield"
        case .eventParticipationChanged:
            return "person.badge.plus"
        case .organizationRequestApproved:
            return "checkmark.seal"
        case .organizationRequestNeedsRevision:
            return "pencil.and.list.clipboard"
        case .organizationRequestRejected:
            return "xmark.seal"
        case .organizationRequestCleanupWarning:
            return "clock.badge.exclamationmark"
        case .organizationRequestExpired:
            return "trash.circle"
        case .accountStatusChanged:
            return "person.crop.circle.badge.exclamationmark"
        case .legalDocumentsUpdated:
            return "doc.text.magnifyingglass"
        case .roleChanged, .organizationRoleAssigned, .organizationRoleRemoved:
            return "person.badge.key"
        case .reportReviewed:
            return "checkmark.message"
        case .eventUpdated:
            return "calendar.badge.clock"
        case .eventCancelled:
            return "calendar.badge.exclamationmark"
        case .eventRegistrationConfirmed:
            return "calendar.badge.checkmark"
        case .organizationNewsPublished:
            return "newspaper"
        case .organizationEventPublished:
            return "calendar.badge.plus"
        case .contentDraftReady:
            return "doc.badge.plus"
        case .systemAnnouncement, .unknown:
            return "megaphone"
        }
    }

    private var iconTint: Color {
        switch notification.severity {
        case .info:
            return notification.countsAsUnread ? AppTheme.accentPrimaryForeground : AppTheme.textSecondary
        case .success:
            return AppTheme.accentSuccessForeground
        case .warning:
            return AppTheme.accentSupportForeground
        case .critical:
            return AppTheme.accentDestructiveForeground
        }
    }

    private var severityText: String {
        switch notification.severity {
        case .info:
            return AppStrings.NotificationInbox.severityInfo
        case .success:
            return AppStrings.NotificationInbox.severitySuccess
        case .warning:
            return AppStrings.NotificationInbox.severityWarning
        case .critical:
            return AppStrings.NotificationInbox.severityCritical
        }
    }
}

#Preview {
    NotificationInboxView(viewModel: NotificationInboxViewModel(repository: MockNotificationInboxRepository()))
}
