import SwiftUI

struct GuideManagementNavigationHeader<TrailingContent: View>: View {
    @Environment(\.dismiss) private var dismiss
    @ViewBuilder let trailingContent: TrailingContent

    init(@ViewBuilder trailingContent: () -> TrailingContent) {
        self.trailingContent = trailingContent()
    }

    var body: some View {
        AppCenteredBrandHeader {
            AppGlassIconButton(systemImage: "chevron.left", accessibilityLabel: AppStrings.Common.back) {
                dismiss()
            }
        } trailingContent: {
            trailingContent
        }
    }
}

extension GuideManagementNavigationHeader where TrailingContent == EmptyView {
    init() {
        self.init {
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
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.accentPrimary)
            .frame(width: AppTheme.iconButtonSize, height: AppTheme.iconButtonSize)
            .background(
                reduceTransparency ? AppTheme.glassFallbackSurface(for: colorScheme) : AppTheme.glassControlSurface(for: colorScheme),
                in: RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
            )
            .background {
                if !reduceTransparency {
                    RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
                    .strokeBorder(AppTheme.glassBorder(for: colorScheme))
            )
            .shadow(color: AppTheme.glassShadow(for: colorScheme), radius: 5, y: 2)
    }
}
