import SwiftUI

struct ProfileDestinationLayout<Content: View>: View {
    let title: String
    let introSubtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        PushedScreenShell(
            title: title,
            subtitle: introSubtitle,
            tabBarHidden: true
        ) {
            AppGroupedContentPlane {
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
                    .foregroundStyle(AppTheme.accentPrimary)
                    .frame(width: 38, height: 38)
                    .background(AppTheme.accentPrimary.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(message)
                        .font(.caption)
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
