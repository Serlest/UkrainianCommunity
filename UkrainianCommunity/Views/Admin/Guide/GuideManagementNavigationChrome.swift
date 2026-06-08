import SwiftUI

struct GuideManagementNavigationHeader<TrailingContent: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let trailingContent: TrailingContent

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder trailingContent: () -> TrailingContent
    ) {
        self.title = title
        self.subtitle = subtitle
        self.trailingContent = trailingContent()
    }

    var body: some View {
        PushedScreenHeader(title: title, subtitle: subtitle) {
            trailingContent
        }
    }
}

extension GuideManagementNavigationHeader where TrailingContent == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) {
            EmptyView()
        }
    }
}

struct GuideManagementHeaderGlassControl: View {
    let systemImage: String

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Image(systemName: systemImage)
            .font(AppTheme.glassIconButtonIconFont)
            .foregroundStyle(AppTheme.accentPrimary)
            .frame(width: AppTheme.glassIconButtonSize, height: AppTheme.glassIconButtonSize)
            .background(
                reduceTransparency ? AppTheme.glassFallbackSurface(for: colorScheme) : AppTheme.glassControlSurface(for: colorScheme),
                in: RoundedRectangle(cornerRadius: AppTheme.glassIconButtonCornerRadius, style: .continuous)
            )
            .background {
                if !reduceTransparency {
                    RoundedRectangle(cornerRadius: AppTheme.glassIconButtonCornerRadius, style: .continuous)
                        .fill(AppTheme.glassIconButtonMaterial)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.glassIconButtonCornerRadius, style: .continuous)
                    .strokeBorder(AppTheme.glassBorder(for: colorScheme))
            )
            .shadow(
                color: AppTheme.glassShadow(for: colorScheme),
                radius: AppTheme.glassIconButtonShadowRadius,
                y: AppTheme.glassIconButtonShadowY
            )
    }
}
