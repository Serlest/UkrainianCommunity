import SwiftUI

struct NotificationPopupView: View {
    let notification: AppNotification
    let errorMessage: String?
    let dismiss: () -> Void
    let performAction: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.sectionSpacing) {
                    AppGlassCard(spacing: 16) {
                        header
                        messageText

                        if let errorMessage {
                            InlineMessageCard(style: .error, message: errorMessage)
                        }

                        VStack(spacing: AppTheme.eventsMetadataSpacing) {
                            if notification.actionType != .none {
                                PrimaryActionButton(
                                    title: AppStrings.NotificationPopup.actionButton,
                                    loadingTitle: AppStrings.NotificationPopup.actionButton,
                                    isLoading: false,
                                    systemImage: "arrow.right.circle.fill",
                                    action: performAction
                                )
                            }

                            Button(AppStrings.Common.ok, action: dismiss)
                                .buttonStyle(.bordered)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(.horizontal, AppTheme.pageHorizontal)
                .padding(.vertical, AppTheme.sectionSpacing)
            }
            .background(AppTheme.groupedBackground.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 48, height: 48)
                .background(
                    tint.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
                )

            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var messageText: some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(AppTheme.textSecondary)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var title: String {
        if let title = notification.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }

        return fallbackTitle
    }

    private var message: String {
        if let message = notification.message?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
            return message
        }
        if let message = notification.metadata["message"]?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
            return message
        }
        if let message = notification.payload["message"]?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
            return message
        }

        return fallbackMessage
    }

    private var fallbackTitle: String {
        switch notification.type {
        case .feedbackReply:
            AppStrings.NotificationInbox.feedbackReplyTitle
        case .organizationRequestApproved:
            AppStrings.NotificationInbox.organizationApprovedTitle
        case .organizationRequestNeedsRevision:
            AppStrings.NotificationInbox.organizationNeedsRevisionTitle
        case .organizationRequestRejected:
            AppStrings.NotificationInbox.organizationRejectedTitle
        case .accountStatusChanged:
            AppStrings.NotificationInbox.accountStatusChangedTitle
        case .legalDocumentsUpdated:
            AppStrings.NotificationInbox.legalDocumentsUpdatedTitle
        case .roleChanged:
            AppStrings.NotificationInbox.roleChangedTitle
        case .organizationRoleAssigned:
            AppStrings.NotificationInbox.organizationRoleAssignedTitle
        case .organizationRoleRemoved:
            AppStrings.NotificationInbox.organizationRoleRemovedTitle
        case .reportReviewed:
            AppStrings.NotificationInbox.reportReviewedTitle
        case .eventUpdated:
            AppStrings.NotificationInbox.eventUpdatedTitle
        case .eventCancelled:
            AppStrings.NotificationInbox.eventCancelledTitle
        case .guideMaterialUpdated:
            AppStrings.NotificationInbox.guideMaterialUpdatedTitle
        case .systemAnnouncement:
            AppStrings.NotificationInbox.systemAnnouncementTitle
        }
    }

    private var fallbackMessage: String {
        switch notification.type {
        case .feedbackReply:
            notification.payload["subject"] ?? notification.payload["messagePreview"] ?? AppStrings.NotificationInbox.feedbackReplyBody
        case .organizationRequestApproved:
            AppStrings.NotificationInbox.organizationApprovedBody(organizationName)
        case .organizationRequestNeedsRevision:
            notification.payload["reviewMessage"] ?? AppStrings.NotificationInbox.organizationNeedsRevisionBody(organizationName)
        case .organizationRequestRejected:
            notification.payload["rejectionReason"] ?? AppStrings.NotificationInbox.organizationRejectedBody(organizationName)
        default:
            AppStrings.NotificationInbox.genericBody
        }
    }

    private var organizationName: String {
        notification.payload["organizationName"] ?? notification.metadata["organizationName"] ?? AppStrings.Common.notAvailable
    }

    private var systemImage: String {
        switch notification.severity {
        case .info:
            "bell.fill"
        case .success:
            "checkmark.seal.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .critical:
            "exclamationmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch notification.severity {
        case .info:
            AppTheme.accentPrimary
        case .success:
            Color.green
        case .warning:
            AppTheme.accentSupport
        case .critical:
            AppTheme.accentDestructive
        }
    }
}

#Preview {
    NotificationPopupView(
        notification: AppNotification(
            id: "preview",
            recipientUserId: "user",
            type: .systemAnnouncement,
            sourceType: .system,
            sourceId: "system",
            severity: .critical,
            actionType: .none,
            requiresPopup: true,
            title: "System announcement",
            message: "Important app-wide information.",
            payload: [:],
            isRead: false,
            readAt: nil,
            createdAt: .now
        ),
        errorMessage: nil,
        dismiss: {},
        performAction: {}
    )
}
