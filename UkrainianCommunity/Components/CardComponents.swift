import SwiftUI

struct AppGlassCardStyle: ViewModifier {
    let cornerRadius: CGFloat
    let material: Material
    let surface: Color?
    let borderOpacity: Double
    let shadowRadius: CGFloat
    let shadowY: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background {
                shape.fill(
                    reduceTransparency
                    ? AppTheme.glassFallbackSurface(for: colorScheme)
                    : (surface ?? AppTheme.glassSurface(for: colorScheme))
                )
            }
            .background {
                if !reduceTransparency {
                    shape.fill(material)
                }
            }
            .overlay {
                shape.strokeBorder(AppTheme.glassBorder(for: colorScheme).opacity(borderOpacity))
            }
            .shadow(color: AppTheme.glassShadow(for: colorScheme), radius: shadowRadius, y: shadowY)
    }
}

extension View {
    func appGlassCard(
        cornerRadius: CGFloat = AppTheme.cardRadius,
        material: Material = .ultraThinMaterial,
        surface: Color? = nil,
        borderOpacity: Double = AppTheme.glassCardBorderOpacity,
        shadowRadius: CGFloat = AppTheme.glassCardShadowRadius,
        shadowY: CGFloat = AppTheme.glassCardShadowY
    ) -> some View {
        modifier(
            AppGlassCardStyle(
                cornerRadius: cornerRadius,
                material: material,
                surface: surface,
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
    let shadowRadius: CGFloat
    let shadowY: CGFloat
    @ViewBuilder let content: Content

    init(
        padding: CGFloat = AppTheme.cardPadding,
        spacing: CGFloat = AppTheme.appGlassCardDefaultSpacing,
        cornerRadius: CGFloat = AppTheme.cardRadius,
        material: Material = AppTheme.appGlassCardMaterial,
        shadowRadius: CGFloat = AppTheme.glassCardShadowRadius,
        shadowY: CGFloat = AppTheme.glassCardShadowY,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.spacing = spacing
        self.cornerRadius = cornerRadius
        self.material = material
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
            shadowRadius: shadowRadius,
            shadowY: shadowY
        )
    }
}

struct SoftContentCard<Content: View>: View {
    let padding: CGFloat
    @ViewBuilder let content: Content

    init(padding: CGFloat = AppTheme.dashboardCardPadding, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        AppGlassCard(
            padding: padding,
            spacing: AppTheme.softContentCardSpacing,
            shadowRadius: AppTheme.softContentCardShadowRadius,
            shadowY: AppTheme.softContentCardShadowY
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

struct DetailPageContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: AppTheme.detailPageContentSpacing) {
                    content
                }
                .padding(.horizontal, AppTheme.detailPageHorizontalPadding)
                .padding(.top, AppTheme.detailPageTopPadding)
                .padding(.bottom, AppTheme.detailPageBottomPadding)
                .frame(width: proxy.size.width, alignment: .leading)
            }
            .frame(width: proxy.size.width)
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

    var body: some View {
        HStack(alignment: .center, spacing: AppTheme.detailActionRowSpacing) {
            leadingContent
            Spacer(minLength: 0)
            trailingContent
        }
    }
}
