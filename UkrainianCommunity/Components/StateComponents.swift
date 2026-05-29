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
                    .foregroundStyle(AppTheme.accentPrimary)
                    .frame(width: UnifiedEmptyStateMetrics.iconSize, height: UnifiedEmptyStateMetrics.iconSize)
                    .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous))

                VStack(spacing: UnifiedEmptyStateMetrics.textSpacing) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
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
                    .font(.title3.weight(.semibold))

                Text(message)
                    .font(.subheadline)
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
            return AppTheme.accentPrimary
        case .success:
            return .green
        case .error:
            return AppTheme.accentDestructive
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
