import SwiftUI

struct ProfileDestinationClearAction {
    let accessibilityLabel: String
    let isLoading: Bool
    let action: () -> Void
}

struct ProfileDestinationLayout<Content: View>: View {
    let title: String
    let introSubtitle: String
    let contentSpacing: CGFloat
    let clearAction: ProfileDestinationClearAction?
    @ViewBuilder let content: Content

    init(
        title: String,
        introSubtitle: String,
        contentSpacing: CGFloat = AppTheme.feedRowSpacing,
        clearAction: ProfileDestinationClearAction? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.introSubtitle = introSubtitle
        self.contentSpacing = contentSpacing
        self.clearAction = clearAction
        self.content = content()
    }

    var body: some View {
        PushedScreenShell(
            title: title,
            subtitle: introSubtitle
        ) {
            if let clearAction {
                if clearAction.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: AppTheme.minimumInteractiveTarget, height: AppTheme.minimumInteractiveTarget)
                        .accessibilityLabel(clearAction.accessibilityLabel)
                } else {
                    AppGlassIconButton(
                        systemImage: "trash",
                        accessibilityLabel: clearAction.accessibilityLabel,
                        role: .destructive,
                        action: clearAction.action
                    )
                }
            }
        } content: {
            AppGroupedContentPlane(spacing: contentSpacing) {
                content
            }
        }
    }
}

struct ProfileDestinationEmptyStateCard: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .center, spacing: 8) {
                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.accentPrimaryForeground)
                    .frame(width: 38, height: 38)
                    .background(AppTheme.accentPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(spacing: 4) {
                    Text(title)
                        .font(AppTheme.emptyStateTitleFont)
                        .foregroundStyle(AppTheme.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(message)
                        .font(AppTheme.emptyStateMessageFont)
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 128)
            .padding(.vertical, 4)
        }
    }
}
