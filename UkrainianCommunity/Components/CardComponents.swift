import SwiftUI

struct AppGlassCardStyle: ViewModifier {
    let cornerRadius: CGFloat
    let material: Material
    let surface: Color?
    let usesNativeGlass: Bool
    let fallbackUsesMaterial: Bool
    let borderOpacity: Double
    let shadowRadius: CGFloat
    let shadowY: CGFloat

    func body(content: Content) -> some View {
        content
            .appGlassSurface(
                cornerRadius: cornerRadius,
                usesNativeGlass: usesNativeGlass,
                fallbackMaterial: material,
                fallbackSurface: surface,
                fallbackUsesMaterial: fallbackUsesMaterial,
                borderOpacity: borderOpacity,
                shadowRadius: shadowRadius,
                shadowY: shadowY
            )
    }
}

extension View {
    func appGlassCard(
        cornerRadius: CGFloat = AppTheme.cardRadius,
        material: Material = .ultraThinMaterial,
        surface: Color? = nil,
        usesNativeGlass: Bool = false,
        fallbackUsesMaterial: Bool = true,
        borderOpacity: Double = AppTheme.glassCardBorderOpacity,
        shadowRadius: CGFloat = AppTheme.glassCardShadowRadius,
        shadowY: CGFloat = AppTheme.glassCardShadowY
    ) -> some View {
        modifier(
            AppGlassCardStyle(
                cornerRadius: cornerRadius,
                material: material,
                surface: surface,
                usesNativeGlass: usesNativeGlass,
                fallbackUsesMaterial: fallbackUsesMaterial,
                borderOpacity: borderOpacity,
                shadowRadius: shadowRadius,
                shadowY: shadowY
            )
        )
    }
}

struct AppGlassCard<Content: View>: View {
    let padding: CGFloat
    let spacing: CGFloat
    let cornerRadius: CGFloat
    let material: Material
    let surface: Color?
    let usesNativeGlass: Bool
    let fallbackUsesMaterial: Bool
    let shadowRadius: CGFloat
    let shadowY: CGFloat
    @ViewBuilder let content: Content

    init(
        padding: CGFloat = AppTheme.cardPadding,
        spacing: CGFloat = AppTheme.appGlassCardDefaultSpacing,
        cornerRadius: CGFloat = AppTheme.cardRadius,
        material: Material = AppTheme.appGlassCardMaterial,
        surface: Color? = nil,
        usesNativeGlass: Bool = false,
        fallbackUsesMaterial: Bool = true,
        shadowRadius: CGFloat = AppTheme.glassCardShadowRadius,
        shadowY: CGFloat = AppTheme.glassCardShadowY,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.spacing = spacing
        self.cornerRadius = cornerRadius
        self.material = material
        self.surface = surface
        self.usesNativeGlass = usesNativeGlass
        self.fallbackUsesMaterial = fallbackUsesMaterial
        self.shadowRadius = shadowRadius
        self.shadowY = shadowY
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appGlassCard(
            cornerRadius: cornerRadius,
            material: material,
            surface: surface,
            usesNativeGlass: usesNativeGlass,
            fallbackUsesMaterial: fallbackUsesMaterial,
            shadowRadius: shadowRadius,
            shadowY: shadowY
        )
    }
}

struct SoftContentCard<Content: View>: View {
    let padding: CGFloat
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(padding: CGFloat = AppTheme.dashboardCardPadding, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        AppGlassCard(
            padding: padding,
            spacing: AppTheme.softContentCardSpacing,
            surface: AppTheme.glassFallbackSurface(for: colorScheme),
            usesNativeGlass: false,
            fallbackUsesMaterial: false,
            shadowRadius: AppTheme.localCardShadowSmallRadius,
            shadowY: AppTheme.localCardShadowSmallY
        ) {
            content
        }
    }
}

struct CommunityCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        AppGlassCard(padding: AppTheme.cardPadding, spacing: 12) {
            content
        }
    }
}

struct DetailCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        AppGlassCard(
            padding: AppTheme.detailCardPadding,
            spacing: AppTheme.dashboardSpacing,
            shadowRadius: AppTheme.detailCardShadowRadius,
            shadowY: AppTheme.detailCardShadowY
        ) {
            content
        }
    }
}

struct DetailHeaderCard<MetadataContent: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let metadataContent: MetadataContent

    var body: some View {
        DetailCard {
            Text(title)
                .font(AppTheme.detailHeaderCardTitleFont)
                .foregroundStyle(AppTheme.textPrimary)
                .lineSpacing(AppTheme.detailHeaderCardLineSpacing)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(AppTheme.detailHeaderCardSubtitleFont)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineSpacing(AppTheme.detailHeaderCardLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }

            metadataContent
        }
    }
}

struct DetailActionRow<LeadingContent: View, TrailingContent: View>: View {
    @ViewBuilder let leadingContent: LeadingContent
    @ViewBuilder let trailingContent: TrailingContent
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: AppTheme.detailActionRowSpacing) {
                    leadingContent
                    trailingContent
                }
            } else {
                HStack(alignment: .center, spacing: AppTheme.detailActionRowSpacing) {
                    leadingContent
                    Spacer(minLength: 0)
                    trailingContent
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
