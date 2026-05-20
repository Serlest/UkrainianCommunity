import SwiftUI
import UIKit

private enum RemoteImageCache {
    static let shared: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 100
        cache.totalCostLimit = 75 * 1024 * 1024
        return cache
    }()
}

struct GradientHeroCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2.weight(.bold))
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(AppTheme.textOnHero.opacity(0.85))
            content
        }
        .padding(AppTheme.detailCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surfaceHero)
        .foregroundStyle(AppTheme.textOnHero)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.heroRadius, style: .continuous))
    }
}

struct BrandMarkView: View {
    let size: CGFloat
    let width: CGFloat
    let assetName: String?

    init(size: CGFloat, width: CGFloat? = nil, assetName: String? = nil) {
        self.size = size
        self.width = width ?? size
        self.assetName = assetName
    }

    var body: some View {
        Group {
            if let assetName {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
            } else {
                generatedMark
            }
        }
        .frame(width: width, height: size)
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
    @ViewBuilder let trailingContent: TrailingContent

    init(
        title: String,
        subtitle: String? = nil,
        brandAssetName: String? = nil,
        showsBrandText: Bool = true,
        brandSize: CGSize = CGSize(width: 52, height: 52),
        @ViewBuilder trailingContent: () -> TrailingContent
    ) {
        self.title = title
        self.subtitle = subtitle
        self.brandAssetName = brandAssetName
        self.showsBrandText = showsBrandText
        self.brandSize = brandSize
        self.trailingContent = trailingContent()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            BrandMarkView(size: brandSize.height, width: brandSize.width, assetName: brandAssetName)

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
    @ViewBuilder let footerContent: FooterContent

    init(
        title: String,
        subtitle: String,
        imageSource: AppHeroBannerImageSource = .none,
        height: CGFloat = AppTheme.heroBannerHeight,
        @ViewBuilder footerContent: () -> FooterContent
    ) {
        self.title = title
        self.subtitle = subtitle
        self.imageSource = imageSource
        self.height = height
        self.footerContent = footerContent()
    }

    var body: some View {
        Group {
            if imageSource.isImageOnlyBanner {
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
        .background(AppTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: AppTheme.heroRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.heroRadius, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle)
        )
        .shadow(color: AppTheme.shadowSoft, radius: 6, y: 3)
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
                isDecorative: true
            )
        case let .localAsset(assetName):
            Image(assetName)
                .resizable()
                .scaledToFill()
        case .none:
            AppHeroFallbackArtwork()
        }
    }
}

private extension AppHeroBannerImageSource {
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
        height: CGFloat = AppTheme.heroBannerHeight
    ) {
        self.init(title: title, subtitle: subtitle, imageSource: imageSource, height: height) {
            EmptyView()
        }
    }
}

private struct AppHeroFallbackArtwork: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    AppTheme.accentPrimary.opacity(0.055),
                    AppTheme.accentSupport.opacity(0.08),
                    AppTheme.surfaceElevated
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            HStack {
                Spacer()

                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppTheme.accentPrimary.opacity(0.16),
                                    AppTheme.accentSupport.opacity(0.14),
                                    AppTheme.surfaceElevated.opacity(0.72)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 168, height: 116)
                        .offset(x: 18, y: -4)

                    Circle()
                        .fill(AppTheme.surfaceElevated.opacity(0.74))
                        .frame(width: 112, height: 112)
                        .offset(x: -26, y: 16)

                    Image(systemName: "building.columns")
                        .font(.system(size: 54, weight: .medium))
                        .foregroundStyle(AppTheme.accentPrimary.opacity(0.18))
                        .offset(x: 20, y: -8)

                    Image(systemName: "person.2.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(AppTheme.accentPrimary.opacity(0.42))
                        .offset(x: -28, y: 16)

                    RibbonStripe(color: AppTheme.accentPrimary)
                        .frame(height: 7)
                        .offset(y: 52)

                    RibbonStripe(color: AppTheme.accentDestructive)
                        .frame(height: 6)
                        .offset(y: 62)

                    RibbonStripe(color: AppTheme.accentSupport)
                        .frame(height: 5)
                        .offset(y: 70)
                }
                .frame(width: 220)
            }
        }
    }
}

private struct RibbonStripe: View {
    let color: Color

    var body: some View {
        CurvedFlagStripe()
            .fill(color.opacity(0.92))
            .frame(width: 230)
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
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle)
        )
        .shadow(color: AppTheme.shadowSoft, radius: 5, y: 2)
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

struct AppInfoChip: View {
    enum Size {
        case small
        case regular

        var font: Font {
            switch self {
            case .small:
                .caption2.weight(.bold)
            case .regular:
                .caption.weight(.semibold)
            }
        }

        var iconFont: Font {
            switch self {
            case .small:
                .caption2.weight(.semibold)
            case .regular:
                .caption.weight(.semibold)
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
        .background(fill, in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
        .overlay {
            if let border {
                RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                    .strokeBorder(border)
            }
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

struct AppDateBadge: View {
    let date: Date
    let calendar: Calendar

    init(date: Date, calendar: Calendar = .current) {
        self.date = date
        self.calendar = calendar
    }

    var body: some View {
        VStack(spacing: 2) {
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
        .frame(width: 42, height: 46)
        .background(AppTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle)
        )
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
            .fixedSize(horizontal: false, vertical: true)
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
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(AppTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .fill(AppTheme.surfacePrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle)
        )
    }
}

struct DetailPageContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 16) {
                    content
                }
                .padding(.horizontal, AppTheme.pageHorizontal)
                .padding(.top, AppTheme.sectionSpacing)
                .padding(.bottom, 120)
                .frame(width: proxy.size.width, alignment: .leading)
            }
            .frame(width: proxy.size.width)
        }
    }
}

struct DetailCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(AppTheme.detailCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .fill(AppTheme.surfacePrimary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle)
        )
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
                .foregroundStyle(.primary)

            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            metadataContent
        }
    }
}

struct DetailImageCard: View {
    let imageURL: String?
    let height: CGFloat
    let source: String

    private var resolvedHeight: CGFloat {
        RemoteImageView.normalizedHeight(for: height)
    }

    var body: some View {
        DetailCard {
            RemoteCardImage(imageURL: imageURL, height: height, cornerRadius: AppTheme.imageRadius, source: source)
                .frame(maxWidth: .infinity)
                .frame(height: resolvedHeight)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous))
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

struct RemoteImageView: View {
    private static let fallbackHeight: CGFloat = 220

    let imageURL: String?
    let height: CGFloat
    let cornerRadius: CGFloat
    let source: String
    @State private var loadedImage: UIImage?
    @State private var loadFailed = false

    init(imageURL: String?, height: CGFloat, cornerRadius: CGFloat = 18, source: String = "unknown") {
        self.imageURL = imageURL
        self.height = height
        self.cornerRadius = cornerRadius
        self.source = source
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
                placeholder(systemImage: "photo")
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

    init(
        imageURL: String?,
        height: CGFloat,
        cornerRadius: CGFloat = 18,
        source: String = "unknown",
        isDecorative: Bool = false
    ) {
        self.imageURL = imageURL
        self.height = height
        self.cornerRadius = cornerRadius
        self.source = source
        self.isDecorative = isDecorative
    }

    var body: some View {
        RemoteImageView(imageURL: imageURL, height: height, cornerRadius: cornerRadius, source: source)
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
        ContentUnavailableView(title, systemImage: "tray")
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
        CommunityCard {
            VStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 24))
                    .foregroundStyle(AppTheme.textSecondary)

                Text(title)
                    .font(.headline.weight(.semibold))

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
        }
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
                    .fill(.ultraThinMaterial)
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
