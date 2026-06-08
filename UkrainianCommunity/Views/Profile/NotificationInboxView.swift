import SwiftUI

struct NotificationInboxView: View {
    @ObservedObject var viewModel: NotificationInboxViewModel
    let onNotificationTap: (AppNotification) -> Void

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
            headerControls
            inboxContent
        }
        .refreshable {
            await viewModel.refresh()
        }
        .navigationTitle(AppStrings.NotificationInbox.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
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
                ForEach(viewModel.filteredNotifications) { notification in
                    NotificationInboxRow(
                        notification: notification,
                        tapAction: {
                            Task {
                                await viewModel.markRead(notification)
                                onNotificationTap(notification)
                            }
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

    private var emptyMessage: String {
        viewModel.selectedFilter == .unread
            ? AppStrings.NotificationInbox.unreadEmptyMessage
            : AppStrings.NotificationInbox.emptyMessage
    }
}

private struct NotificationInboxRow: View {
    let notification: AppNotification
    let tapAction: () -> Void
    let markReadAction: () -> Void
    let markUnreadAction: () -> Void
    let archiveAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        Button(action: tapAction) {
            AppEditorSectionCard {
                HStack(alignment: .top, spacing: AppTheme.eventsMetadataSpacing) {
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
                            .fixedSize(horizontal: false, vertical: true)

                        Text(dateText)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: deleteAction) {
                Label(AppStrings.NotificationInbox.delete, systemImage: "trash")
            }

            Button(action: archiveAction) {
                Label(AppStrings.NotificationInbox.archive, systemImage: "archivebox")
            }
            .tint(AppTheme.textSecondary)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(action: notification.isRead ? markUnreadAction : markReadAction) {
                Label(
                    notification.isRead ? AppStrings.NotificationInbox.markUnread : AppStrings.NotificationInbox.markRead,
                    systemImage: notification.isRead ? "envelope.badge" : "envelope.open"
                )
            }
            .tint(AppTheme.accentPrimary)
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
        case .feedbackSubmitted, .feedbackReply:
            return "bubble.left.and.bubble.right"
        case .organizationRequestApproved:
            return "checkmark.seal"
        case .organizationRequestNeedsRevision:
            return "pencil.and.list.clipboard"
        case .organizationRequestRejected:
            return "xmark.seal"
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
        case .guideMaterialUpdated:
            return "book.pages"
        case .systemAnnouncement, .unknown:
            return "megaphone"
        }
    }

    private var iconTint: Color {
        switch notification.severity {
        case .info:
            return notification.isRead ? AppTheme.textSecondary : AppTheme.accentPrimary
        case .success:
            return .green
        case .warning:
            return AppTheme.accentSupport
        case .critical:
            return AppTheme.accentDestructive
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
