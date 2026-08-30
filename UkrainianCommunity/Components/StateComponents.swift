import SwiftUI

private enum UnifiedEmptyStateMetrics {
    static let minHeight: CGFloat = 180
    static let verticalPadding: CGFloat = 24
    static let horizontalPadding: CGFloat = 18
    static let iconSize: CGFloat = 44
    static let iconFontSize: CGFloat = 22
    static let contentSpacing: CGFloat = 10
    static let textSpacing: CGFloat = 6
}

struct UnifiedEmptyStateCard<ActionContent: View>: View {
    let systemImage: String
    let title: String
    let message: String
    @ViewBuilder let actionContent: ActionContent
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        systemImage: String,
        title: String,
        message: String,
        @ViewBuilder actionContent: () -> ActionContent = { EmptyView() }
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionContent = actionContent()
    }

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .center, spacing: UnifiedEmptyStateMetrics.contentSpacing) {
                Image(systemName: systemImage)
                    .font(.system(size: UnifiedEmptyStateMetrics.iconFontSize, weight: .semibold))
                    .foregroundStyle(AppTheme.accentPrimaryForeground)
                    .frame(width: UnifiedEmptyStateMetrics.iconSize, height: UnifiedEmptyStateMetrics.iconSize)
                    .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous))

                VStack(spacing: UnifiedEmptyStateMetrics.textSpacing) {
                    Text(title)
                        .font(AppTheme.emptyStateTitleFont)
                        .foregroundStyle(AppTheme.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)

                    Text(message)
                        .font(AppTheme.emptyStateMessageFont)
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                actionContent
            }
            .padding(.horizontal, UnifiedEmptyStateMetrics.horizontalPadding)
            .padding(.vertical, UnifiedEmptyStateMetrics.verticalPadding)
            .frame(maxWidth: .infinity, minHeight: UnifiedEmptyStateMetrics.minHeight)
        }
    }
}

struct EmptyStateView: View {
    let title: String

    var body: some View {
        EmptyStateCard(
            systemImage: "tray",
            title: title,
            message: AppStrings.Common.noItems
        )
    }
}
struct LoadingStateCard: View {
    let title: String?

    var body: some View {
        CommunityCard {
            HStack(spacing: 12) {
                ProgressView()

                if let title, !title.isEmpty {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 6)
        }
    }
}

struct EmptyStateCard: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        UnifiedEmptyStateCard(
            systemImage: systemImage,
            title: title,
            message: message
        )
    }
}

struct ErrorStateCard: View {
    let systemImage: String
    let title: String
    let message: String
    let retryTitle: String?
    let retryAction: (() -> Void)?

    init(
        systemImage: String = "exclamationmark.triangle",
        title: String,
        message: String,
        retryTitle: String? = nil,
        retryAction: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.retryTitle = retryTitle
        self.retryAction = retryAction
    }

    var body: some View {
        CommunityCard {
            VStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 30))
                    .foregroundStyle(AppTheme.textSecondary)

                Text(title)
                    .font(AppTheme.emptyStateTitleFont)

                Text(message)
                    .font(AppTheme.emptyStateMessageFont)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)

                if let retryTitle, let retryAction {
                    Button(retryTitle, action: retryAction)
                        .buttonStyle(.borderedProminent)
                        .tint(AppTheme.accentPrimary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
    }
}

enum InlineMessageStyle {
    case info
    case success
    case error

    var tint: Color {
        switch self {
        case .info:
            return AppTheme.accentPrimaryForeground
        case .success:
            return AppTheme.accentSuccessForeground
        case .error:
            return AppTheme.accentDestructiveForeground
        }
    }

    var background: Color {
        switch self {
        case .info:
            return AppTheme.accentPrimarySoft
        case .success:
            return Color.green.opacity(0.12)
        case .error:
            return AppTheme.badgeRedFill
        }
    }

    var systemImage: String {
        switch self {
        case .info:
            return "info.circle.fill"
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }
}

struct InlineMessageCard: View {
    let style: InlineMessageStyle
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: style.systemImage)
                .font(.headline)
                .foregroundStyle(style.tint)

            Text(message)
                .font(.footnote)
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(style.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(style.tint.opacity(0.18))
        )
    }
}

struct ContentPlanningAttentionCard: View {
    let messages: [String]
    var compact = false

    private var visibleMessages: ArraySlice<String> {
        messages.prefix(compact ? 3 : messages.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(AppStrings.ContentPlanning.attentionTitle, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentWarningForeground)

            if !compact {
                Text(AppStrings.ContentPlanning.attentionEditorHint)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(Array(visibleMessages.enumerated()), id: \.offset) { index, message in
                HStack(alignment: .top, spacing: 9) {
                    Text("\(index + 1)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(AppTheme.accentWarningForeground)
                        .frame(width: 22, height: 22)
                        .background(AppTheme.accentWarningForeground.opacity(0.12), in: Circle())

                    Text(message)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if compact, messages.count > visibleMessages.count {
                Text(AppStrings.ContentPlanning.additionalAttentionFields(messages.count - visibleMessages.count))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.accentWarningForeground.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.accentWarningForeground.opacity(0.22))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("contentPlanning.attentionDetails")
    }
}
