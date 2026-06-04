import SwiftUI

struct AccountStatusNoticeView: View {
    let notice: AccountStatusNotice
    let isAcknowledging: Bool
    let errorMessage: String?
    let acknowledge: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AppTheme.sectionSpacing) {
                    AppGlassCard(spacing: 16) {
                        header
                        messageText
                        detailRows

                        if let errorMessage {
                            InlineMessageCard(style: .error, message: errorMessage)
                        }

                        PrimaryActionButton(
                            title: AppStrings.AccountStatusAlert.acknowledgementButton,
                            loadingTitle: AppStrings.AccountStatusAlert.acknowledgementLoading,
                            isLoading: isAcknowledging,
                            systemImage: "checkmark.circle.fill",
                            action: acknowledge
                        )
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
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous))

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
    }

    @ViewBuilder
    private var detailRows: some View {
        VStack(spacing: 10) {
            if let reason = notice.reason ?? notice.message {
                AccountStatusNoticeDetailRow(
                    title: AppStrings.AccountStatusAlert.reasonTitle,
                    value: reason,
                    systemImage: "text.quote"
                )
            }

            if notice.kind == .suspended, let banExpiresAt = notice.banExpiresAt {
                AccountStatusNoticeDetailRow(
                    title: AppStrings.AccountStatusAlert.suspensionUntilTitle,
                    value: LocalizationStore.dateString(from: banExpiresAt, dateStyle: .medium, timeStyle: .short),
                    systemImage: "clock"
                )
            }
        }
    }

    private var title: String {
        switch notice.kind {
        case .warned:
            AppStrings.AccountStatusAlert.warnedTitle
        case .suspended:
            AppStrings.AccountStatusAlert.suspendedTitle
        case .banned:
            AppStrings.AccountStatusAlert.bannedTitle
        case .deactivated:
            AppStrings.AccountStatusAlert.deactivatedTitle
        case .restored:
            AppStrings.AccountStatusAlert.restoredTitle
        }
    }

    private var message: String {
        switch notice.kind {
        case .warned:
            AppStrings.AccountStatusAlert.warnedMessage
        case .suspended:
            AppStrings.AccountStatusAlert.suspendedMessage
        case .banned:
            AppStrings.AccountStatusAlert.bannedMessage
        case .deactivated:
            AppStrings.AccountStatusAlert.deactivatedMessage
        case .restored:
            AppStrings.AccountStatusAlert.restoredMessage
        }
    }

    private var systemImage: String {
        switch notice.kind {
        case .warned:
            "exclamationmark.triangle.fill"
        case .suspended:
            "clock.badge.exclamationmark.fill"
        case .banned:
            "hand.raised.fill"
        case .deactivated:
            "person.crop.circle.badge.xmark"
        case .restored:
            "checkmark.seal.fill"
        }
    }

    private var tint: Color {
        switch notice.kind {
        case .warned:
            Color.orange
        case .suspended, .banned, .deactivated:
            AppTheme.accentDestructive
        case .restored:
            Color.green
        }
    }
}

private struct AccountStatusNoticeDetailRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(width: 28, height: 28)
                .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)

                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(AppTheme.surfaceGlass, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
