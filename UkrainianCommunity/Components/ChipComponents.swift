import SwiftUI

struct AppInfoChip: View {
    enum Size {
        case small
        case regular

        var font: Font {
            switch self {
            case .small:
                .caption2.weight(.semibold)
            case .regular:
                .caption.weight(.medium)
            }
        }

        var iconFont: Font {
            switch self {
            case .small:
                .caption2.weight(.semibold)
            case .regular:
                .caption.weight(.medium)
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .small:
                8
            case .regular:
                10
            }
        }

        var verticalPadding: CGFloat {
            switch self {
            case .small:
                4
            case .regular:
                8
            }
        }
    }

    let title: String
    let systemImage: String?
    let tint: Color
    let fill: Color
    let border: Color?
    let trailingSystemImage: String?
    let size: Size
    let glassTint: Color?
    let isInteractive: Bool
    let usesNativeGlass: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        title: String,
        systemImage: String? = nil,
        tint: Color = AppTheme.accentPrimaryForeground,
        fill: Color = AppTheme.badgeBlueFill,
        border: Color? = nil,
        trailingSystemImage: String? = nil,
        size: Size = .regular,
        glassTint: Color? = nil,
        isInteractive: Bool = false,
        usesNativeGlass: Bool = false
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.fill = fill
        self.border = border
        self.trailingSystemImage = trailingSystemImage
        self.size = size
        self.glassTint = glassTint
        self.isInteractive = isInteractive
        self.usesNativeGlass = usesNativeGlass
    }

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(size.iconFont)
            }

            Text(title)
                .font(size.font)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .fixedSize(horizontal: false, vertical: true)

            if let trailingSystemImage {
                Image(systemName: trailingSystemImage)
                    .font(size.iconFont)
            }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
        .frame(minHeight: isInteractive ? AppTheme.minimumInteractiveTarget : nil)
        .appGlassSurface(
            cornerRadius: AppTheme.chipRadius,
            tint: glassTint,
            isInteractive: isInteractive,
            usesNativeGlass: usesNativeGlass,
            fallbackSurface: fill,
            fallbackBorder: border,
            borderOpacity: border == nil ? 0 : 1,
            shadowRadius: 5,
            shadowY: 2
        )
    }
}

struct AppFilterChip: View {
    let title: String
    let systemImage: String?
    let isSelected: Bool
    let trailingSystemImage: String?

    init(
        title: String,
        systemImage: String? = nil,
        isSelected: Bool = false,
        trailingSystemImage: String? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.trailingSystemImage = trailingSystemImage
    }

    var body: some View {
        AppInfoChip(
            title: title,
            systemImage: systemImage,
            tint: isSelected ? .white : AppTheme.textSecondary.opacity(0.92),
            fill: isSelected ? AppTheme.accentPrimary : AppTheme.surfaceGlass,
            border: isSelected ? AppTheme.accentPrimary.opacity(0.18) : AppTheme.borderSubtle,
            trailingSystemImage: trailingSystemImage,
            size: .regular,
            glassTint: isSelected ? AppTheme.accentPrimary : nil,
            isInteractive: true,
            usesNativeGlass: true
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct AppHorizontalChipRow<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: Content

    init(spacing: CGFloat = AppTheme.eventsMetadataSpacing, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            AppGlassEffectGroup(spacing: spacing) {
                HStack(spacing: spacing) {
                    content
                }
            }
            .padding(.horizontal, AppTheme.eventsMetadataSpacing)
            .padding(.vertical, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AppHorizontalFilterRow<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            AppGlassEffectGroup(spacing: AppTheme.eventsMetadataSpacing) {
                HStack(spacing: AppTheme.eventsMetadataSpacing) {
                    content
                }
            }
            .padding(.vertical, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
