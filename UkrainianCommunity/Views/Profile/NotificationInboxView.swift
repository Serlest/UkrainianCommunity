import SwiftUI

struct NotificationInboxView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: NotificationInboxViewModel

    var body: some View {
        ZStack {
            AppBackgroundView()
                .allowsHitTesting(false)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    AppCenteredBrandHeader {
                        AppGlassIconButton(systemImage: "xmark", accessibilityLabel: AppStrings.Common.done) {
                            dismiss()
                        }
                    } trailingContent: {
                        EmptyView()
                    }

                    AppGroupedContentPlane {
                        VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                            headerCard
                            inboxContent
                        }
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
        .navigationTitle(AppStrings.NotificationInbox.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await viewModel.refresh()
        }
    }

    private var headerCard: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                SectionHeaderBlock(
                    title: AppStrings.NotificationInbox.title,
                    subtitle: AppStrings.NotificationInbox.subtitle
                )

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
        } else if viewModel.notifications.isEmpty {
            UnifiedEmptyStateCard(
                systemImage: "bell",
                title: AppStrings.NotificationInbox.emptyTitle,
                message: AppStrings.NotificationInbox.emptyMessage
            )
        } else {
            VStack(spacing: AppTheme.eventsMetadataSpacing) {
                ForEach(viewModel.notifications) { notification in
                    NotificationInboxRow(notification: notification) {
                        Task { await viewModel.markRead(notification) }
                    }
                }
            }
        }
    }
}

private struct NotificationInboxRow: View {
    let notification: AppNotification
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            AppEditorSectionCard {
                HStack(alignment: .top, spacing: AppTheme.eventsMetadataSpacing) {
                    ZStack {
                        Circle()
                            .fill(notification.isRead ? AppTheme.surfaceControl : AppTheme.accentPrimarySoft)
                            .frame(width: 40, height: 40)

                        Image(systemName: systemImage)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(notification.isRead ? AppTheme.textSecondary : AppTheme.accentPrimary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(title)
                                .font(.headline.weight(notification.isRead ? .regular : .semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                                .multilineTextAlignment(.leading)

                            if !notification.isRead {
                                Circle()
                                    .fill(AppTheme.accentDestructive)
                                    .frame(width: 7, height: 7)
                            }
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
    }

    private var title: String {
        switch notification.type {
        case .feedbackReply:
            AppStrings.NotificationInbox.feedbackReplyTitle
        case .organizationRequestApproved:
            AppStrings.NotificationInbox.organizationApprovedTitle
        case .organizationRequestNeedsRevision:
            AppStrings.NotificationInbox.organizationNeedsRevisionTitle
        case .organizationRequestRejected:
            AppStrings.NotificationInbox.organizationRejectedTitle
        }
    }

    private var bodyText: String {
        switch notification.type {
        case .feedbackReply:
            return notification.payload["subject"] ?? notification.payload["messagePreview"] ?? AppStrings.NotificationInbox.feedbackReplyBody
        case .organizationRequestApproved:
            return AppStrings.NotificationInbox.organizationApprovedBody(organizationName)
        case .organizationRequestNeedsRevision:
            return notification.payload["reviewMessage"] ?? AppStrings.NotificationInbox.organizationNeedsRevisionBody(organizationName)
        case .organizationRequestRejected:
            return notification.payload["rejectionReason"] ?? AppStrings.NotificationInbox.organizationRejectedBody(organizationName)
        }
    }

    private var organizationName: String {
        notification.payload["organizationName"] ?? AppStrings.Common.notAvailable
    }

    private var dateText: String {
        LocalizationStore.dateString(from: notification.createdAt, dateStyle: .medium, timeStyle: .short)
    }

    private var systemImage: String {
        switch notification.type {
        case .feedbackReply:
            return "bubble.left.and.bubble.right"
        case .organizationRequestApproved:
            return "checkmark.seal"
        case .organizationRequestNeedsRevision:
            return "pencil.and.list.clipboard"
        case .organizationRequestRejected:
            return "xmark.seal"
        }
    }
}

#Preview {
    NotificationInboxView(viewModel: NotificationInboxViewModel(repository: MockNotificationInboxRepository()))
}
