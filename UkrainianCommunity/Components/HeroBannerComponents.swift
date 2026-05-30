import SwiftUI

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
