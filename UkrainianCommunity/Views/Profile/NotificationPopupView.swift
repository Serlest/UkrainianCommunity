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
        notification.title ?? AppStrings.NotificationInbox.systemAnnouncementTitle
    }

    private var message: String {
        notification.message
            ?? notification.metadata["message"]
            ?? notification.payload["message"]
            ?? AppStrings.NotificationInbox.genericBody
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
