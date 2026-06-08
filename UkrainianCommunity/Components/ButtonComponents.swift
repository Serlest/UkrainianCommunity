import SwiftUI

struct AppIconControlButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    init(systemImage: String, accessibilityLabel: String, action: @escaping () -> Void = {}) {
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    var body: some View {
        AppGlassIconButton(systemImage: systemImage, accessibilityLabel: accessibilityLabel) {
            action()
        }
    }
}

struct AppGlassIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let role: ButtonRole?
    let isPlaceholder: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        systemImage: String,
        accessibilityLabel: String,
        role: ButtonRole? = nil,
        isPlaceholder: Bool = false,
        action: @escaping () -> Void = {}
    ) {
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.role = role
        self.isPlaceholder = isPlaceholder
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(AppTheme.glassIconButtonIconFont)
                .foregroundStyle(role == .destructive ? AppTheme.accentDestructive : AppTheme.accentPrimary)
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
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .disabled(isPlaceholder)
        .opacity(isPlaceholder ? AppTheme.glassIconButtonPlaceholderOpacity : 1)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(isPlaceholder ? AppStrings.Action.comingSoon : "")
    }
}

struct PrimaryActionButton: View {
    let title: String
    let loadingTitle: String
    let isEnabled: Bool
    let isLoading: Bool
    let systemImage: String?
    let action: () -> Void

    init(
        title: String,
        loadingTitle: String? = nil,
        isEnabled: Bool = true,
        isLoading: Bool = false,
        systemImage: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.loadingTitle = loadingTitle ?? title
        self.isEnabled = isEnabled
        self.isLoading = isLoading
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.eventsMetadataSpacing) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.subheadline.weight(.semibold))
                }

                Text(isLoading ? loadingTitle : title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: AppTheme.iconButtonSize)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
                    .fill(isEnabled ? AppTheme.accentPrimary : AppTheme.accentPrimary.opacity(0.36))
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
        .accessibilityLabel(title)
    }
}

struct LikeButton: View {
    let isLiked: Bool
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("\(count)", systemImage: isLiked ? "heart.fill" : "heart")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isLiked ? AppTheme.accentDestructive : AppTheme.accentPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isLiked ? AppTheme.badgeRedFill : AppTheme.badgeBlueFill)
                )
        }
        .buttonStyle(.plain)
    }
}

enum AppActionButtonHierarchy {
    case primary
    case secondary
}

extension View {
    @ViewBuilder
    func appActionButtonStyle(_ hierarchy: AppActionButtonHierarchy) -> some View {
        switch hierarchy {
        case .primary:
            self
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(AppTheme.accentPrimary)
        case .secondary:
            self
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(AppTheme.accentPrimary)
        }
    }

    func appEditorInputStyle(minHeight: CGFloat = AppTheme.newsEditorInputHeight) -> some View {
        self
            .font(.body)
            .foregroundStyle(AppTheme.textPrimary)
            .padding(.horizontal, AppTheme.eventsControlGroupSpacing)
            .frame(minHeight: minHeight, alignment: .leading)
            .background(AppTheme.surfaceControl.opacity(0.42), in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                    .strokeBorder(AppTheme.borderSubtle)
            )
    }
}
