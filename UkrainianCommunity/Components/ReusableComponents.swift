import SwiftUI
import UIKit
import PhotosUI

private enum RemoteImageCache {
    static let shared: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 100
        cache.totalCostLimit = 75 * 1024 * 1024
        return cache
    }()
}

struct BrandMarkView: View {
    enum ContentMode {
        case fit
        case fill
    }

    let size: CGFloat
    let width: CGFloat
    let assetName: String?
    let contentMode: ContentMode

    init(size: CGFloat, width: CGFloat? = nil, assetName: String? = nil, contentMode: ContentMode = .fit) {
        self.size = size
        self.width = width ?? size
        self.assetName = assetName
        self.contentMode = contentMode
    }

    var body: some View {
        Group {
            if let assetName {
                Image(assetName)
                    .resizable()
                    .aspectRatio(contentMode: contentMode == .fill ? .fill : .fit)
            } else {
                generatedMark
            }
        }
        .frame(width: width, height: size, alignment: .leading)
        .clipped()
        .accessibilityHidden(true)
    }

    private var generatedMark: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: size * 0.20, style: .continuous)
                .fill(AppTheme.surfaceElevated)
                .shadow(color: AppTheme.shadowSoft, radius: 10, y: 5)

            HStack(spacing: size * 0.08) {
                Capsule()
                    .fill(AppTheme.accentPrimary)
                Capsule()
                    .fill(AppTheme.accentSupport)
            }
            .frame(width: size * 0.56, height: size * 0.70)
            .offset(y: -size * 0.10)

            CurvedFlagStripe()
                .fill(AppTheme.accentDestructive)
                .frame(width: size * 0.72, height: size * 0.20)
                .offset(y: -size * 0.12)
        }
    }
}

private struct CurvedFlagStripe: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control: CGPoint(x: rect.midX, y: rect.maxY * 1.35)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY * 0.62),
            control: CGPoint(x: rect.midX, y: rect.maxY * 1.55)
        )
        path.closeSubpath()
        return path
    }
}

struct BrandedScreenHeader<TrailingContent: View>: View {
    let title: String
    let subtitle: String?
    let brandAssetName: String?
    let showsBrandText: Bool
    let brandSize: CGSize
    let brandContentMode: BrandMarkView.ContentMode
    @ViewBuilder let trailingContent: TrailingContent

    init(
        title: String,
        subtitle: String? = nil,
        brandAssetName: String? = nil,
        showsBrandText: Bool = true,
        brandSize: CGSize = CGSize(width: 52, height: 52),
        brandContentMode: BrandMarkView.ContentMode = .fit,
        @ViewBuilder trailingContent: () -> TrailingContent
    ) {
        self.title = title
        self.subtitle = subtitle
        self.brandAssetName = brandAssetName
        self.showsBrandText = showsBrandText
        self.brandSize = brandSize
        self.brandContentMode = brandContentMode
        self.trailingContent = trailingContent()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            BrandMarkView(
                size: brandSize.height,
                width: brandSize.width,
                assetName: brandAssetName,
                contentMode: brandContentMode
            )

            if showsBrandText {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(2)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(2)
                    }
                }
            }

            Spacer(minLength: 12)

            trailingContent
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension BrandedScreenHeader where TrailingContent == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) {
            EmptyView()
        }
    }
}

struct AppBrandHeader<TrailingContent: View>: View {
    @ViewBuilder let trailingContent: TrailingContent

    init(@ViewBuilder trailingContent: () -> TrailingContent) {
        self.trailingContent = trailingContent()
    }

    var body: some View {
        BrandedScreenHeader(
            title: AppStrings.Home.brandTitle,
            subtitle: AppStrings.Home.brandSubtitle,
            brandAssetName: "logo1",
            showsBrandText: false,
            brandSize: AppTheme.appHeaderLogoSize,
            brandContentMode: .fit
        ) {
            trailingContent
        }
        .padding(.leading, AppTheme.appHeaderLeadingAdjustment)
    }
}


struct AppBackgroundView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            Image("background")
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .overlay(readabilityOverlay)
        }
        .ignoresSafeArea()
    }

    private var readabilityOverlay: some View {
        LinearGradient(
            colors: colorScheme == .dark ? darkOverlayColors : lightOverlayColors,
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var lightOverlayColors: [Color] {
        [
            Color.white.opacity(0.12),
            Color.white.opacity(0.08),
            AppTheme.accentSupport.opacity(0.06)
        ]
    }

    private var darkOverlayColors: [Color] {
        [
            Color(red: 0.015, green: 0.022, blue: 0.040).opacity(0.52),
            Color(red: 0.020, green: 0.030, blue: 0.055).opacity(0.58),
            Color(red: 0.010, green: 0.016, blue: 0.032).opacity(0.66)
        ]
    }
}

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
        borderOpacity: Double = 1,
        shadowRadius: CGFloat = 12,
        shadowY: CGFloat = 6
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
        spacing: CGFloat = 12,
        cornerRadius: CGFloat = AppTheme.cardRadius,
        material: Material = .ultraThinMaterial,
        shadowRadius: CGFloat = 12,
        shadowY: CGFloat = 6,
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

struct AppGroupedContentPlane<Content: View>: View {
    let padding: CGFloat
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(padding: CGFloat = AppTheme.contentPlanePadding, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appGlassCard(
            cornerRadius: AppTheme.contentPlaneRadius,
            material: .ultraThinMaterial,
            surface: AppTheme.groupedPlaneSurface(for: colorScheme),
            borderOpacity: 0.34,
            shadowRadius: 6,
            shadowY: 3
        )
    }
}

enum AppHeroBannerImageSource: Equatable {
    case remoteURL(String)
    case localAsset(String)
    case none
}

struct AppHeroBanner<FooterContent: View>: View {
    let title: String
    let subtitle: String
    let imageSource: AppHeroBannerImageSource
    let height: CGFloat
    let displaysTextOverImage: Bool
    @ViewBuilder let footerContent: FooterContent
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        title: String,
        subtitle: String,
        imageSource: AppHeroBannerImageSource = .none,
        height: CGFloat = AppTheme.heroBannerHeight,
        displaysTextOverImage: Bool = false,
        @ViewBuilder footerContent: () -> FooterContent
    ) {
        self.title = title
        self.subtitle = subtitle
        self.imageSource = imageSource
        self.height = height
        self.displaysTextOverImage = displaysTextOverImage
        self.footerContent = footerContent()
    }

    var body: some View {
        Group {
            if imageSource.isRemoteBanner || (imageSource.isImageOnlyBanner && !displaysTextOverImage) {
                GeometryReader { proxy in
                    bannerArtwork
                        .frame(width: proxy.size.width, height: height)
                        .clipped()
                }
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.heroRadius, style: .continuous))
            } else {
                ZStack(alignment: .bottomLeading) {
                    bannerArtwork
                        .frame(maxWidth: .infinity)
                        .frame(height: height)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.heroRadius, style: .continuous))

                    LinearGradient(
                        colors: [
                            AppTheme.surfaceElevated.opacity(0.98),
                            AppTheme.surfaceElevated.opacity(0.84),
                            AppTheme.surfaceElevated.opacity(0.18)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.heroRadius, style: .continuous))

                    VStack(alignment: .leading, spacing: 9) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(title)
                                .font(.title2.weight(.bold))
                                .foregroundStyle(AppTheme.accentPrimary)
                                .lineLimit(2)

                            Text(subtitle)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(AppTheme.textPrimary.opacity(0.78))
                                .lineLimit(3)
                        }

                        footerContent
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .background(
            reduceTransparency ? AppTheme.glassFallbackSurface(for: colorScheme) : AppTheme.glassSurface(for: colorScheme),
            in: RoundedRectangle(cornerRadius: AppTheme.heroRadius, style: .continuous)
        )
        .background {
            if !reduceTransparency {
                RoundedRectangle(cornerRadius: AppTheme.heroRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.heroRadius, style: .continuous)
                .strokeBorder(AppTheme.glassBorder(for: colorScheme))
        )
        .shadow(color: AppTheme.glassShadow(for: colorScheme), radius: 14, y: 7)
    }

    @ViewBuilder
    private var bannerArtwork: some View {
        switch imageSource {
        case let .remoteURL(imageURL):
            RemoteCardImage(
                imageURL: imageURL,
                height: height,
                cornerRadius: AppTheme.heroRadius,
                source: "AppHeroBanner",
                isDecorative: true,
                placeholderStyle: .glassSkeleton
            )
        case let .localAsset(assetName):
            Image(assetName)
                .resizable()
                .scaledToFill()
        case .none:
            AppHeroFallbackSurface()
        }
    }
}

private extension AppHeroBannerImageSource {
    var isRemoteBanner: Bool {
        switch self {
        case .remoteURL:
            true
        case .localAsset, .none:
            false
        }
    }

    var isImageOnlyBanner: Bool {
        switch self {
        case .remoteURL, .localAsset:
            true
        case .none:
            false
        }
    }
}

extension AppHeroBanner where FooterContent == EmptyView {
    init(
        title: String,
        subtitle: String,
        imageSource: AppHeroBannerImageSource = .none,
        height: CGFloat = AppTheme.heroBannerHeight,
        displaysTextOverImage: Bool = false
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            imageSource: imageSource,
            height: height,
            displaysTextOverImage: displaysTextOverImage
        ) {
            EmptyView()
        }
    }
}

private struct AppHeroFallbackSurface: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: [
                AppTheme.glassControlSurface(for: colorScheme),
                AppTheme.glassSurface(for: colorScheme),
                AppTheme.groupedPlaneSurface(for: colorScheme)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
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
        AppGlassCard(padding: padding, spacing: 12, shadowRadius: 13, shadowY: 6) {
            content
        }
    }
}

struct DashboardSectionHeader<TrailingContent: View>: View {
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
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            SectionHeaderBlock(title: title, subtitle: subtitle)

            trailingContent
        }
    }
}

extension DashboardSectionHeader where TrailingContent == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) {
            EmptyView()
        }
    }
}

struct DashboardFeedContainer<Data: RandomAccessCollection, RowContent: View>: View where Data.Element: Identifiable {
    let items: Data
    let spacing: CGFloat
    @ViewBuilder let rowContent: (Data.Element) -> RowContent

    init(
        items: Data,
        spacing: CGFloat = 14,
        @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
    ) {
        self.items = items
        self.spacing = spacing
        self.rowContent = rowContent
    }

    var body: some View {
        LazyVStack(spacing: spacing) {
            ForEach(items) { item in
                rowContent(item)
            }
        }
    }
}

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
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(role == .destructive ? AppTheme.accentDestructive : AppTheme.accentPrimary)
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
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .disabled(isPlaceholder)
        .opacity(isPlaceholder ? 0.58 : 1)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(isPlaceholder ? AppStrings.Action.comingSoon : "")
    }
}

struct AppCenteredBrandHeader<LeadingContent: View, TrailingContent: View>: View {
    @ViewBuilder let leadingContent: LeadingContent
    @ViewBuilder let trailingContent: TrailingContent

    init(
        @ViewBuilder leadingContent: () -> LeadingContent,
        @ViewBuilder trailingContent: () -> TrailingContent
    ) {
        self.leadingContent = leadingContent()
        self.trailingContent = trailingContent()
    }

    var body: some View {
        ZStack {
            HStack(spacing: AppTheme.eventsControlGroupSpacing) {
                leadingContent

                Spacer(minLength: 0)

                trailingContent
            }

            BrandMarkView(
                size: AppTheme.appHeaderLogoSize.height,
                width: AppTheme.appHeaderLogoSize.width,
                assetName: "logo1",
                contentMode: .fit
            )
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, minHeight: AppTheme.appHeaderLogoSize.height)
        .accessibilityElement(children: .contain)
    }
}

struct AppEditorSectionCard<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        SoftContentCard(padding: AppTheme.detailCardPadding) {
            content
        }
    }
}

struct AppEditorSectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline.weight(.semibold))
            .foregroundStyle(AppTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AppEditorField<Content: View>: View {
    let title: String
    let counterText: String?
    @ViewBuilder let content: Content

    init(title: String, counterText: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.counterText = counterText
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                if let counterText {
                    Spacer(minLength: AppTheme.eventsMetadataSpacing)

                    Text(counterText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .monospacedDigit()
                }
            }

            content
        }
    }
}

struct AppEditorSubmitButton: View {
    let title: String
    let isEnabled: Bool
    let isLoading: Bool
    let loadingTitle: String
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppTheme.eventsMetadataSpacing) {
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white)
                }

                Text(isLoading ? loadingTitle : title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, AppTheme.sectionSpacing)
            .frame(height: AppTheme.iconButtonSize)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
                    .fill(isEnabled ? AppTheme.accentPrimary : AppTheme.accentPrimary.opacity(0.38))
            )
            .shadow(color: isEnabled ? AppTheme.glassShadow(for: colorScheme) : .clear, radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(title)
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

struct EditorTextField: View {
    let title: String
    @Binding var text: String
    let systemImage: String
    let keyboardType: UIKeyboardType
    let textContentType: UITextContentType?
    let autocapitalization: TextInputAutocapitalization
    let autocorrectionDisabled: Bool

    init(
        _ title: String,
        text: Binding<String>,
        systemImage: String,
        keyboardType: UIKeyboardType = .default,
        textContentType: UITextContentType? = nil,
        autocapitalization: TextInputAutocapitalization = .sentences,
        autocorrectionDisabled: Bool = false
    ) {
        self.title = title
        self._text = text
        self.systemImage = systemImage
        self.keyboardType = keyboardType
        self.textContentType = textContentType
        self.autocapitalization = autocapitalization
        self.autocorrectionDisabled = autocorrectionDisabled
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(width: AppTheme.metadataIconSize)

            TextField(title, text: $text)
                .font(.subheadline)
                .textInputAutocapitalization(autocapitalization)
                .textContentType(textContentType)
                .keyboardType(keyboardType)
                .autocorrectionDisabled(autocorrectionDisabled)
                .accessibilityLabel(title)
        }
        .padding(.horizontal, AppTheme.inputHorizontalPadding)
        .frame(height: AppTheme.newsEditorInputHeight)
        .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle)
        )
    }
}

struct EditorSecureField: View {
    let title: String
    @Binding var text: String
    let systemImage: String
    let textContentType: UITextContentType?

    init(
        _ title: String,
        text: Binding<String>,
        systemImage: String = "lock",
        textContentType: UITextContentType? = nil
    ) {
        self.title = title
        self._text = text
        self.systemImage = systemImage
        self.textContentType = textContentType
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(width: AppTheme.metadataIconSize)

            SecureField(title, text: $text)
                .font(.subheadline)
                .textContentType(textContentType)
                .accessibilityLabel(title)
        }
        .padding(.horizontal, AppTheme.inputHorizontalPadding)
        .frame(height: AppTheme.newsEditorInputHeight)
        .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle)
        )
    }
}

struct AuthHeaderView: View {
    let title: String
    let subtitle: String

    var body: some View {
        AppEditorSectionCard {
            HStack(alignment: .center, spacing: 14) {
                BrandMarkView(size: 54, width: 54, assetName: "logo1")

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

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

struct AppNotificationBellButton: View {
    let action: () -> Void

    init(action: @escaping () -> Void = {}) {
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(AppTheme.accentPrimary)
                    .frame(width: 40, height: 40)

                Circle()
                    .fill(AppTheme.accentDestructive)
                    .frame(width: 8, height: 8)
                    .offset(x: -6, y: 6)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppStrings.Home.notifications)
    }
}

struct AppHeroBannerEditButton: View {
    @Binding var selectedItem: PhotosPickerItem?
    let isUploading: Bool

    var body: some View {
        PhotosPicker(selection: $selectedItem, matching: .images, photoLibrary: .shared()) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .stroke(AppTheme.borderSubtle, lineWidth: 1)
                    )

                if isUploading {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    Image(systemName: "photo.badge.plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accentPrimary)
                }
            }
            .shadow(color: AppTheme.shadowSoft, radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(isUploading)
        .accessibilityLabel(AppStrings.Home.changeBanner)
    }
}

struct AppEventDateBlock: View {
    let date: Date
    let calendar: Calendar
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(date: Date, calendar: Calendar = .current) {
        self.date = date
        self.calendar = calendar
    }

    var body: some View {
        VStack(spacing: 3) {
            VStack(spacing: 1) {
                Text(dayText)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(AppTheme.accentPrimary)
                    .lineLimit(1)

                Text(monthText.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(AppTheme.accentDestructive)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(width: AppTheme.eventsDateRailWidth, height: 52)
            .background(
                reduceTransparency ? AppTheme.glassFallbackSurface(for: colorScheme) : AppTheme.glassControlSurface(for: colorScheme),
                in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
            )
            .background {
                if !reduceTransparency {
                    RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                    .strokeBorder(AppTheme.glassBorder(for: colorScheme))
            )

            Text(weekdayText.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(AppTheme.textSecondary.opacity(0.62))
                .lineLimit(1)
        }
        .frame(width: AppTheme.eventsDateRailWidth)
    }

    private var dayText: String {
        "\(calendar.component(.day, from: date))"
    }

    private var monthText: String {
        let formatter = DateFormatter()
        formatter.locale = LocalizationStore.locale
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter.string(from: date)
    }

    private var weekdayText: String {
        let formatter = DateFormatter()
        formatter.locale = LocalizationStore.locale
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: date)
    }
}

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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        title: String,
        systemImage: String? = nil,
        tint: Color = AppTheme.accentPrimary,
        fill: Color = AppTheme.badgeBlueFill,
        border: Color? = nil,
        trailingSystemImage: String? = nil,
        size: Size = .regular
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.fill = fill
        self.border = border
        self.trailingSystemImage = trailingSystemImage
        self.size = size
    }

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(size.iconFont)
            }

            Text(title)
                .font(size.font)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            if let trailingSystemImage {
                Image(systemName: trailingSystemImage)
                    .font(size.iconFont)
            }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, size.horizontalPadding)
        .padding(.vertical, size.verticalPadding)
        .background(
            reduceTransparency ? fill.opacity(0.95) : fill,
            in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
        )
        .background {
            if !reduceTransparency {
                RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
        .overlay {
            if let border {
                RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                    .strokeBorder(border)
            }
        }
        .shadow(color: AppTheme.glassShadow(for: colorScheme).opacity(0.65), radius: 5, y: 2)
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
            size: .regular
        )
        .frame(minHeight: AppTheme.iconButtonSize)
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
            HStack(spacing: spacing) {
                content
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
        AppHorizontalChipRow {
            content
        }
    }
}

struct AppFeedThumbnail: View {
    let imageURL: String?
    let fallbackSystemImage: String
    let tint: Color
    let fill: Color
    let size: CGFloat
    let cornerRadius: CGFloat
    let source: String

    init(
        imageURL: String?,
        fallbackSystemImage: String,
        tint: Color,
        fill: Color,
        size: CGFloat = AppTheme.feedThumbnailSize,
        cornerRadius: CGFloat = AppTheme.feedThumbnailRadius,
        source: String = "AppFeedThumbnail"
    ) {
        self.imageURL = imageURL
        self.fallbackSystemImage = fallbackSystemImage
        self.tint = tint
        self.fill = fill
        self.size = size
        self.cornerRadius = cornerRadius
        self.source = source
    }

    var body: some View {
        Group {
            if imageURL != nil {
                RemoteCardImage(
                    imageURL: imageURL,
                    height: size,
                    cornerRadius: cornerRadius,
                    source: source,
                    isDecorative: true
                )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(fill)

                    Image(systemName: fallbackSystemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tint)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct AppMetadataLine: View {
    let title: String
    let systemImage: String
    let tint: Color

    init(title: String, systemImage: String, tint: Color = AppTheme.textSecondary) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.weight(.medium))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
    }
}

struct AdaptiveCardGrid<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable {
    let items: Data
    @ViewBuilder let content: (Data.Element) -> Content

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 16), count: horizontalSizeClass == .regular ? 2 : 1)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(items) { item in
                content(item)
            }
        }
    }
}

struct CommunityCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        AppGlassCard(padding: AppTheme.cardPadding, spacing: 12, shadowRadius: 8, shadowY: 3) {
            content
        }
    }
}

struct DetailPageContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    content
                }
                .padding(.horizontal, AppTheme.pageHorizontal)
                .padding(.top, AppTheme.sectionSpacing)
                .padding(.bottom, AppTheme.homeBottomContentPadding)
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
            shadowRadius: 13,
            shadowY: 6
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
                .font(.title2.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineSpacing(2)
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
        HStack(alignment: .center, spacing: 12) {
            leadingContent
            Spacer(minLength: 0)
            trailingContent
        }
    }
}

enum RemoteImagePlaceholderStyle {
    case icon
    case glassSkeleton
}

struct RemoteImageView: View {
    private static let fallbackHeight: CGFloat = 220

    let imageURL: String?
    let height: CGFloat
    let cornerRadius: CGFloat
    let source: String
    let placeholderStyle: RemoteImagePlaceholderStyle
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var loadedImage: UIImage?
    @State private var loadFailed = false

    init(
        imageURL: String?,
        height: CGFloat,
        cornerRadius: CGFloat = 18,
        source: String = "unknown",
        placeholderStyle: RemoteImagePlaceholderStyle = .icon
    ) {
        self.imageURL = imageURL
        self.height = height
        self.cornerRadius = cornerRadius
        self.source = source
        self.placeholderStyle = placeholderStyle
    }

    var body: some View {
        Group {
            if let loadedImage {
                Image(uiImage: loadedImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: resolvedHeight)
                    .clipped()
            } else if loadFailed {
                unavailablePlaceholder
                    .frame(maxWidth: .infinity)
                    .frame(height: resolvedHeight)
                    .clipped()
            } else {
                loadingPlaceholder
                    .frame(maxWidth: .infinity)
                    .frame(height: resolvedHeight)
                    .clipped()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: imageURL) {
            await loadImage()
        }
    }

    private var resolvedHeight: CGFloat {
        Self.normalizedHeight(for: height)
    }

    static func normalizedHeight(for height: CGFloat) -> CGFloat {
        height > 0 ? height : fallbackHeight
    }

    private func placeholder(systemImage: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(AppTheme.surfaceSecondary)
            LinearGradient(
                colors: [
                    AppTheme.surfaceSecondary,
                    AppTheme.surfacePrimary
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(AppTheme.textSecondary)
        }
    }

    @ViewBuilder
    private var loadingPlaceholder: some View {
        switch placeholderStyle {
        case .icon:
            placeholder(systemImage: "photo")
        case .glassSkeleton:
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(reduceTransparency ? AppTheme.glassFallbackSurface(for: colorScheme) : AppTheme.glassControlSurface(for: colorScheme))
                .background {
                    if !reduceTransparency {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                }
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.05 : 0.20),
                            Color.white.opacity(0.02),
                            Color.white.opacity(colorScheme == .dark ? 0.04 : 0.16)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                )
        }
    }

    private var unavailablePlaceholder: some View {
        placeholder(systemImage: "photo.badge.exclamationmark")
    }

    @MainActor
    private func loadImage() async {
        loadedImage = nil
        loadFailed = false

        guard let imageURL, let url = URL(string: imageURL) else {
            return
        }

        let cacheKey = imageURL as NSString
        if let cachedImage = RemoteImageCache.shared.object(forKey: cacheKey) {
            loadedImage = cachedImage
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else {
                loadFailed = true
                return
            }

            RemoteImageCache.shared.setObject(image, forKey: cacheKey, cost: data.count)
            loadedImage = image
        } catch {
            let nsError = error as NSError
            if nsError.code == NSURLErrorCancelled {
                return
            }
            loadFailed = true
            print("RemoteImageView failed source=\(source) requestedHeight=\(height) resolvedHeight=\(resolvedHeight) code=\(nsError.code) message=\(nsError.localizedDescription)")
        }
    }
}

struct RemoteCardImage: View {
    let imageURL: String?
    let height: CGFloat
    let cornerRadius: CGFloat
    let source: String
    let isDecorative: Bool
    let placeholderStyle: RemoteImagePlaceholderStyle

    init(
        imageURL: String?,
        height: CGFloat,
        cornerRadius: CGFloat = 18,
        source: String = "unknown",
        isDecorative: Bool = false,
        placeholderStyle: RemoteImagePlaceholderStyle = .icon
    ) {
        self.imageURL = imageURL
        self.height = height
        self.cornerRadius = cornerRadius
        self.source = source
        self.isDecorative = isDecorative
        self.placeholderStyle = placeholderStyle
    }

    var body: some View {
        RemoteImageView(
            imageURL: imageURL,
            height: height,
            cornerRadius: cornerRadius,
            source: source,
            placeholderStyle: placeholderStyle
        )
            .accessibilityHidden(isDecorative)
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

struct MetadataRow: View {
    let label: String
    let value: String
    let systemImage: String

    var body: some View {
        Label {
            HStack {
                Text(label)
                Spacer()
                Text(value)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(AppTheme.accentPrimary)
        }
        .font(.subheadline)
    }
}

struct SelectableFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? AppTheme.accentPrimary : AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(isSelected ? AppTheme.badgeBlueFill : AppTheme.surfacePrimary)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(isSelected ? AppTheme.borderSubtle : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}

struct SectionHeaderBlock: View {
    let title: String
    let subtitle: String?

    init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

struct ContentMetadataPill: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(AppTheme.textSecondary)
            .multilineTextAlignment(.leading)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(AppTheme.surfaceSecondary)
            )
    }
}

enum AppNavigationRowAccessory {
    case chevron
    case none
}

struct AppNavigationRow: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let tint: Color
    let accessory: AppNavigationRowAccessory

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        tint: Color = AppTheme.accentPrimary,
        accessory: AppNavigationRowAccessory = .chevron
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.accessory = accessory
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(tint == AppTheme.accentDestructive ? tint : AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 12)

            if accessory == .chevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
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

struct AvatarArtworkView: View {
    let avatarURL: URL?
    let previewImage: UIImage?
    let initials: String
    let size: CGFloat
    let accessibilityLabel: String?
    let isLoading: Bool
    let isDecorative: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        avatarURL: URL?,
        previewImage: UIImage? = nil,
        initials: String,
        size: CGFloat,
        accessibilityLabel: String? = nil,
        isLoading: Bool = false,
        isDecorative: Bool = false
    ) {
        self.avatarURL = avatarURL
        self.previewImage = previewImage
        self.initials = initials
        self.size = size
        self.accessibilityLabel = accessibilityLabel
        self.isLoading = isLoading
        self.isDecorative = isDecorative
    }

    var body: some View {
        ZStack {
            avatarContent
                .frame(width: size, height: size)
                .clipShape(Circle())

            if isLoading {
                Circle()
                    .fill(reduceTransparency ? AppTheme.glassFallbackSurface(for: colorScheme) : AppTheme.glassControlSurface(for: colorScheme))
                    .background {
                        if !reduceTransparency {
                            Circle()
                                .fill(.ultraThinMaterial)
                        }
                    }
                    .overlay {
                        ProgressView()
                            .controlSize(.regular)
                            .tint(AppTheme.accentPrimary)
                    }
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().stroke(AppTheme.borderSubtle))
        .shadow(color: Color.black.opacity(0.06), radius: 10, y: 4)
        .accessibilityHidden(isDecorative)
        .accessibilityLabel(accessibilityLabel ?? initials)
    }

    @ViewBuilder
    private var avatarContent: some View {
        if let previewImage {
            Image(uiImage: previewImage)
                .resizable()
                .scaledToFill()
                .transition(.opacity)
        } else if let avatarURL {
            AsyncImage(url: avatarURL, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
                switch phase {
                case .empty:
                    avatarPlaceholder(showProgress: true)
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                case .failure:
                    avatarPlaceholder(showProgress: false)
                @unknown default:
                    avatarPlaceholder(showProgress: false)
                }
            }
        } else {
            avatarPlaceholder(showProgress: false)
        }
    }

    private func avatarPlaceholder(showProgress: Bool) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [AppTheme.accentPrimarySoft, AppTheme.surfaceSecondary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            if showProgress {
                ProgressView()
                    .controlSize(.small)
                    .tint(AppTheme.accentPrimary)
            } else {
                Text(initials)
                    .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.accentPrimary)
            }
        }
    }
}
