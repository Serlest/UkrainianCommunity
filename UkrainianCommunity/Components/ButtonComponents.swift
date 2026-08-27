import SwiftUI

enum AppGlassActionHierarchy {
    case regular
    case prominent
    case destructive
}

extension View {
    @ViewBuilder
    func appGlassActionSurface(
        _ hierarchy: AppGlassActionHierarchy,
        isEnabled: Bool = true,
        isInteractive: Bool = true
    ) -> some View {
        switch hierarchy {
        case .regular:
            foregroundStyle(AppTheme.accentPrimaryForeground)
                .appGlassSurface(
                    cornerRadius: AppTheme.iconButtonRadius,
                    isInteractive: isInteractive && isEnabled,
                    usesNativeGlass: false,
                    fallbackRole: .control,
                    shadowRadius: AppTheme.glassIconButtonShadowRadius,
                    shadowY: AppTheme.glassIconButtonShadowY
                )
                .opacity(isEnabled ? 1 : 0.58)
        case .prominent:
            foregroundStyle(isEnabled ? AppTheme.textOnHero : AppTheme.textSecondary)
                .appGlassSurface(
                    cornerRadius: AppTheme.iconButtonRadius,
                    tint: isEnabled ? AppTheme.accentPrimary : AppTheme.surfaceControl,
                    isInteractive: isInteractive && isEnabled,
                    usesNativeGlass: false,
                    fallbackSurface: isEnabled ? AppTheme.accentPrimary : AppTheme.surfaceControl,
                    fallbackUsesMaterial: false,
                    borderOpacity: 0.42,
                    shadowRadius: AppTheme.glassIconButtonShadowRadius,
                    shadowY: AppTheme.glassIconButtonShadowY
                )
        case .destructive:
            foregroundStyle(AppTheme.accentDestructiveForeground)
                .appGlassSurface(
                    cornerRadius: AppTheme.iconButtonRadius,
                    tint: AppTheme.accentDestructive.opacity(isEnabled ? 0.18 : 0.08),
                    isInteractive: isInteractive && isEnabled,
                    usesNativeGlass: false,
                    borderOpacity: 0.72,
                    shadowRadius: AppTheme.glassIconButtonShadowRadius,
                    shadowY: AppTheme.glassIconButtonShadowY
                )
                .opacity(isEnabled ? 1 : 0.58)
        }
    }
}

struct AppSearchClearButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(
                    width: AppTheme.minimumInteractiveTarget,
                    height: AppTheme.minimumInteractiveTarget
                )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityLabel(AppStrings.Search.clear)
    }
}

struct AppGlassIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let role: ButtonRole?
    let isPlaceholder: Bool
    let action: () -> Void
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
        Group {
            if #available(iOS 26.0, *), !reduceTransparency {
                nativeGlassButton
            } else {
                fallbackButton
            }
        }
        .contentShape(Rectangle())
        .disabled(isPlaceholder)
        .opacity(isPlaceholder ? AppTheme.glassIconButtonPlaceholderOpacity : 1)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(isPlaceholder ? AppStrings.Action.comingSoon : "")
    }

    @available(iOS 26.0, *)
    private var nativeGlassButton: some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(AppTheme.glassIconButtonIconFont)
                .foregroundStyle(role == .destructive ? AppTheme.accentDestructiveForeground : AppTheme.accentPrimaryForeground)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: AppTheme.glassIconButtonCornerRadius))
        .controlSize(.regular)
    }

    private var fallbackButton: some View {
        Button(role: role, action: action) {
            icon
                .appGlassSurface(
                    cornerRadius: AppTheme.glassIconButtonCornerRadius,
                    tint: role == .destructive ? AppTheme.accentDestructive.opacity(0.18) : nil,
                    isInteractive: false,
                    usesNativeGlass: false,
                    fallbackMaterial: AppTheme.glassIconButtonMaterial,
                    fallbackRole: .control,
                    shadowRadius: AppTheme.glassIconButtonShadowRadius,
                    shadowY: AppTheme.glassIconButtonShadowY
                )
        }
        .buttonStyle(.plain)
    }

    private var icon: some View {
        Image(systemName: systemImage)
            .font(AppTheme.glassIconButtonIconFont)
            .foregroundStyle(role == .destructive ? AppTheme.accentDestructiveForeground : AppTheme.accentPrimaryForeground)
            .frame(width: AppTheme.glassIconButtonSize, height: AppTheme.glassIconButtonSize)
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
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .frame(minHeight: AppTheme.iconButtonSize)
            .appGlassActionSurface(
                .prominent,
                isEnabled: isEnabled,
                isInteractive: !isLoading
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
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
                .foregroundStyle(isLiked ? AppTheme.accentDestructiveForeground : AppTheme.accentPrimaryForeground)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isLiked ? AppTheme.badgeRedFill : AppTheme.badgeBlueFill)
                )
        }
        .buttonStyle(AppPressFeedbackButtonStyle())
        .frame(minHeight: AppTheme.minimumInteractiveTarget)
        .contentShape(Rectangle())
        .accessibilityAddTraits(isLiked ? .isSelected : [])
    }
}

struct AppPressFeedbackButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
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
                .tint(AppTheme.accentPrimaryForeground)
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
