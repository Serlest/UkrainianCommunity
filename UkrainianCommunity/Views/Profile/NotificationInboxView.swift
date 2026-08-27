import SwiftUI

struct NotificationInboxView: View {
    @ObservedObject var viewModel: NotificationInboxViewModel
    let onNotificationTap: (AppNotification) -> Void
    @State private var isShowingClearConfirmation = false
    @State private var selectedNotification: AppNotification?
    @State private var pendingDestination: AppNotification?

    init(
        viewModel: NotificationInboxViewModel,
        onNotificationTap: @escaping (AppNotification) -> Void = { _ in }
    ) {
        self.viewModel = viewModel
        self.onNotificationTap = onNotificationTap
    }

    var body: some View {
        PushedScreenShell(
            title: AppStrings.NotificationInbox.title,
            subtitle: AppStrings.NotificationInbox.subtitle,
            tabBarHidden: true
        ) {
            if viewModel.isClearing {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: AppTheme.minimumInteractiveTarget, height: AppTheme.minimumInteractiveTarget)
                    .accessibilityLabel(AppStrings.NotificationInbox.clearAll)
            } else if !viewModel.notifications.isEmpty {
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
            inboxContent
        }
        .appRefreshable {
            await viewModel.refresh()
        }
        .navigationTitle(AppStrings.NotificationInbox.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $selectedNotification, onDismiss: openPendingDestination) { notification in
            NotificationDetailView(notification: notification, viewModel: viewModel) { destination in
                pendingDestination = destination
            }
        }
        .onChange(of: viewModel.sessionVersion) { _, _ in
            pendingDestination = nil
            selectedNotification = nil
        }
        .confirmationDialog(
            AppStrings.NotificationInbox.clearConfirmationTitle,
            isPresented: $isShowingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button(AppStrings.NotificationInbox.clearAll, role: .destructive) {
                Task { await viewModel.clearAll() }
            }
            Button(AppStrings.Common.cancel, role: .cancel) {}
        } message: {
            Text(AppStrings.NotificationInbox.clearConfirmationMessage)
        }
    }

    private var headerControls: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                Picker(AppStrings.NotificationInbox.title, selection: $viewModel.selectedFilter) {
                    Text(AppStrings.NotificationInbox.filterAll).tag(NotificationInboxFilter.all)
                    Text(AppStrings.NotificationInbox.filterUnread).tag(NotificationInboxFilter.unread)
                }
                .pickerStyle(.segmented)

                if viewModel.unreadCount > 0 {
                    Button {
                        Task { await viewModel.markAllRead() }
                    } label: {
                        Label(AppStrings.NotificationInbox.markAllRead, systemImage: "checkmark.circle")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    @ViewBuilder
    private var inboxContent: some View {
        if viewModel.isLoading && viewModel.notifications.isEmpty {
            LoadingStateCard(title: AppStrings.NotificationInbox.title)
        } else if let error = viewModel.error, viewModel.notifications.isEmpty {
            UnifiedEmptyStateCard(
                systemImage: "exclamationmark.triangle",
                title: AppStrings.NotificationInbox.title,
                message: error.localizedDescription
            ) {
                Button(AppStrings.Action.retry) {
                    Task { await viewModel.refresh() }
                }
                .buttonStyle(.borderedProminent)
            }
        } else if viewModel.filteredNotifications.isEmpty {
            UnifiedEmptyStateCard(
                systemImage: viewModel.selectedFilter == .unread ? "checkmark.circle" : "bell",
                title: emptyTitle,
                message: emptyMessage
            )
        } else {
            VStack(spacing: AppTheme.eventsMetadataSpacing) {
                if let error = viewModel.error {
                    InlineMessageCard(style: .error, message: error.localizedDescription)
                }

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
                            Task { await viewModel.archive(notification) }
                        },
                        deleteAction: {
                            Task { await viewModel.delete(notification) }
                        }
                    )
                }
            }
        }
    }

    private var emptyTitle: String {
        viewModel.selectedFilter == .unread
            ? AppStrings.NotificationInbox.unreadEmptyTitle
            : AppStrings.NotificationInbox.emptyTitle
    }

    private func openPendingDestination() {
        guard let notification = pendingDestination else { return }
        pendingDestination = nil
        // Wait for the detail sheet to finish dismissing before changing tabs
        // or dismissing the inbox's own full-screen presentation.
        onNotificationTap(notification)
    }

    private var emptyMessage: String {
        viewModel.selectedFilter == .unread
            ? AppStrings.NotificationInbox.unreadEmptyMessage
            : AppStrings.NotificationInbox.emptyMessage
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
                                    disclosureIndicator
                                }
                                textContent
                            }
                        } else {
                            HStack(alignment: .top, spacing: AppTheme.eventsMetadataSpacing) {
                                notificationIcon
                                textContent
                                Spacer(minLength: 0)
                                disclosureIndicator
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(title). \(bodyText). \(dateText)")
                .accessibilityValue(notification.isRead ? "" : AppStrings.NotificationInbox.filterUnread)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(AppStrings.NotificationInbox.viewDetails)
                .accessibilityIdentifier("notificationInbox.open.\(notification.id)")

                Menu {
                    Button(action: notification.isRead ? markUnreadAction : markReadAction) {
                        Label(
                            notification.isRead ? AppStrings.NotificationInbox.markUnread : AppStrings.NotificationInbox.markRead,
                            systemImage: notification.isRead ? "envelope.badge" : "envelope.open"
                        )
                    }

                    Button(action: archiveAction) {
                        Label(AppStrings.NotificationInbox.archive, systemImage: "archivebox")
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
                .accessibilityLabel(AppStrings.NotificationInbox.moreActions)
                .accessibilityIdentifier("notificationInbox.actions.\(notification.id)")
            }
        }
        .accessibilityAction(named: AppStrings.NotificationInbox.delete, deleteAction)
    }

    private var notificationIcon: some View {
        ZStack(alignment: .topTrailing) {
            Circle()
                .fill(iconTint.opacity(notification.isRead ? 0.10 : 0.16))
                .frame(width: 42, height: 42)

            Image(systemName: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(iconTint)
                .frame(width: 42, height: 42)

            if !notification.isRead {
                Circle()
                    .fill(AppTheme.accentDestructive)
                    .frame(width: 9, height: 9)
                    .offset(x: -1, y: 2)
            }
        }
    }

    private var textContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.headline.weight(notification.isRead ? .regular : .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .multilineTextAlignment(.leading)

                severityLabel
            }

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

    private var disclosureIndicator: some View {
        Image(systemName: "chevron.forward")
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.textSecondary)
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
            return notification.isRead ? AppTheme.textSecondary : AppTheme.accentPrimaryForeground
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
