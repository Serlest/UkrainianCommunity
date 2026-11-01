import SwiftUI
import UIKit

enum FeaturedBannerLayoutPolicy {
    static let artworkAspectRatio: CGFloat = 16.0 / 9.0
    static func needsStackedContent(typeSize: DynamicTypeSize, width: CGFloat) -> Bool {
        typeSize >= .xLarge || (width > 0 && width < 340)
    }
}

struct FeaturedBannerCardView: View {
    let banner: FeaturedBanner
    let previewImage: UIImage?
    let artworkHeight: CGFloat?
    let forceStackedContent: Bool
    let countdownIsActive: Bool
    let onArtworkLoadStateChanged: ((Bool) -> Void)?
    let videoEligible: Bool
    let onVideoPrimaryAction: (() -> Void)?
    let onVideoExpanded: (Bool) -> Void
    let onVideoReady: (Bool) -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var renderedWidth: CGFloat = 0

    init(banner: FeaturedBanner, previewImage: UIImage? = nil, artworkHeight: CGFloat? = nil,
         forceStackedContent: Bool = false,
         countdownIsActive: Bool = true,
         videoEligible: Bool = false, onVideoPrimaryAction: (() -> Void)? = nil,
         onVideoExpanded: @escaping (Bool) -> Void = { _ in }, onVideoReady: @escaping (Bool) -> Void = { _ in },
         onArtworkLoadStateChanged: ((Bool) -> Void)? = nil) {
        self.videoEligible = videoEligible; self.onVideoPrimaryAction = onVideoPrimaryAction
        self.onVideoExpanded = onVideoExpanded; self.onVideoReady = onVideoReady
        self.banner = banner
        self.previewImage = previewImage
        self.artworkHeight = artworkHeight
        self.forceStackedContent = forceStackedContent
        self.countdownIsActive = countdownIsActive
        self.onArtworkLoadStateChanged = onArtworkLoadStateChanged
    }

    var body: some View {
        // Keep the media subtree (and its sheet/player state) in the same position
        // when rotation or Dynamic Type switches between overlay and stacked text.
        VStack(alignment: .trailing, spacing: usesStackedContent ? 12 : 0) {
            if usesStackedContent, let countdown = banner.countdown {
                FeaturedBannerCountdownView(countdown: countdown, overArtwork: false, isRunning: countdownIsActive)
            }
            imageLayout { card }.accessibilityHidden(usesStackedContent && banner.video == nil)
            if usesStackedContent && hasTextContent { textContent }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { renderedWidth = $0 }
        .modifier(BannerAccessibilityFallback(needsFallback: !hasTextContent && banner.countdown == nil))
        .accessibilityElement(children: banner.video == nil ? .combine : .contain)
        .accessibilityHint(isActionable ? AppStrings.Action.open : "")
    }

    private var usesStackedContent: Bool {
        forceStackedContent || verticalSizeClass == .compact
            || FeaturedBannerLayoutPolicy.needsStackedContent(typeSize: dynamicTypeSize, width: renderedWidth)
    }

    private var imageLayout: FeaturedBannerAspectLayout {
        FeaturedBannerAspectLayout(aspectRatio: FeaturedBannerLayoutPolicy.artworkAspectRatio,
                                   minimumHeight: artworkHeight,
                                   maximumHeight: artworkHeight ?? AppTheme.featuredBannerMaximumHeight)
    }

    private var media: some View {
        ZStack {
            background.accessibilityHidden(true)
            if let video = banner.video {
                FeaturedBannerVideoPlayer(video: video, title: banner.localizedTitle, inlineEligible: videoEligible,
                    hasAction: onVideoPrimaryAction != nil, onPrimaryAction: { onVideoPrimaryAction?() },
                    onExpanded: onVideoExpanded, onReady: onVideoReady)
            }
        }
    }

    private var card: some View {
        ZStack(alignment: .bottomLeading) {
            media
            if !usesStackedContent && hasTextContent {
                textContent.allowsHitTesting(banner.video == nil)
            }
        }
        .overlay(alignment: .topTrailing) {
            if !usesStackedContent, let countdown = banner.countdown {
                FeaturedBannerCountdownView(countdown: countdown, isRunning: countdownIsActive)
                    .frame(maxWidth: 230, alignment: .trailing).padding(8).allowsHitTesting(false)
            }
        }
        .clipShape(cardShape)
        .overlay {
            cardShape.strokeBorder(AppTheme.glassBorder(for: colorScheme).opacity(0.86)).allowsHitTesting(false)
        }
        .shadow(color: AppTheme.glassShadow(for: colorScheme), radius: AppTheme.glassCardShadowRadius, y: AppTheme.glassCardShadowY)
        .contentShape(cardShape)
        .accessibilityElement(children: banner.video == nil ? .combine : .contain)
        .accessibilityHint(isActionable ? AppStrings.Action.open : "")
    }

    @ViewBuilder
    private var background: some View {
        GeometryReader { proxy in
#if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("-ui-testing"), ProcessInfo.processInfo.environment["UITestBanner14"] == "1", ProcessInfo.processInfo.environment["UITestBanner14Scope"] != "startupCache", previewImage == nil {
                if ProcessInfo.processInfo.environment["UITestBanner14Artwork"] == "1" {
                    AdaptiveBannerImage(image: BannerAuditHarness14.artwork)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .onAppear { onArtworkLoadStateChanged?(true) }
                } else {
                    fallbackBackground.frame(width: proxy.size.width, height: proxy.size.height)
                        .onAppear { onArtworkLoadStateChanged?(true) }
                }
            } else {
                artwork(size: proxy.size)
            }
#else
            artwork(size: proxy.size)
#endif
        }
    }

    @ViewBuilder private func artwork(size: CGSize) -> some View {
            if let previewImage {
                AdaptiveBannerImage(image: previewImage)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .onAppear { onArtworkLoadStateChanged?(true) }
            } else if let imageURL = banner.imageURL?.trimmingCharacters(in: .whitespacesAndNewlines), !imageURL.isEmpty {
                RemoteImageView(
                    imageURL: imageURL,
                    height: size.height,
                    cornerRadius: AppTheme.heroRadius,
                    source: "FeaturedBannerCardView",
                    placeholderStyle: .glassSkeleton,
                    presentationStyle: .adaptiveBanner,
                    onImageLoadStateChanged: onArtworkLoadStateChanged,
                    persistentCacheKey: "\(banner.id)|\(imageURL)|\(banner.updatedAt.timeIntervalSince1970)"
                )
                .frame(width: size.width, height: size.height)
                .clipped()
            } else {
                fallbackBackground
                    .frame(width: size.width, height: size.height)
                    .onAppear { onArtworkLoadStateChanged?(true) }
            }
    }

    private var fallbackBackground: some View {
        LinearGradient(
            colors: [
                AppTheme.accentPrimary.opacity(colorScheme == .dark ? 0.70 : 0.18),
                AppTheme.surfaceElevated.opacity(colorScheme == .dark ? 0.92 : 0.98),
                AppTheme.accentSupport.opacity(colorScheme == .dark ? 0.24 : 0.18)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var textContent: some View {
        HStack(alignment: .bottom, spacing: AppTheme.eventsControlGroupSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                if let titleText {
                    Text(titleText)
                        .font(AppTheme.featuredBannerTitleFont)
                        .foregroundStyle(titleColor)
                        .shadow(color: titleShadow.opacity(0.85), radius: 1, y: 1)
                        .shadow(color: titleShadow.opacity(0.55), radius: 2)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let subtitleText {
                    Text(subtitleText)
                        .font(AppTheme.featuredBannerSubtitleFont)
                        .foregroundStyle(subtitleColor)
                        .shadow(color: subtitleShadow.opacity(0.85), radius: 1, y: 1)
                        .shadow(color: subtitleShadow.opacity(0.55), radius: 2)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 4)

            if isActionable && banner.video == nil {
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.textOnHero)
                    .frame(width: 30, height: 30)
                    .background(AppTheme.accentPrimary.opacity(0.92), in: Circle())
                    .accessibilityHidden(true)
            }
        }
        .padding(.trailing, banner.video != nil && !usesStackedContent ? 104 : 0)
        .padding(AppTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleColor: Color {
        FeaturedBannerTextColor.color(hex: banner.textAppearance.titleColorHex,
                                     fallback: usesStackedContent ? AppTheme.textPrimary : AppTheme.textOnHero)
    }
    private var subtitleColor: Color {
        FeaturedBannerTextColor.color(hex: banner.textAppearance.subtitleColorHex,
                                     fallback: usesStackedContent ? AppTheme.textSecondary : AppTheme.textOnHero.opacity(0.88))
    }
    private var titleShadow: Color {
        usesStackedContent && banner.textAppearance.titleColorHex == nil ? .clear
            : FeaturedBannerTextColor.shadow(for: titleColor, scheme: colorScheme)
    }
    private var subtitleShadow: Color {
        usesStackedContent && banner.textAppearance.subtitleColorHex == nil ? .clear
            : FeaturedBannerTextColor.shadow(for: subtitleColor, scheme: colorScheme)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppTheme.heroRadius, style: .continuous)
    }

    private var titleText: String? {
        nonEmpty(banner.localizedTitle(for: appLanguage))
    }

    private var subtitleText: String? {
        nonEmpty(banner.localizedSubtitle(for: appLanguage))
    }

    private var appLanguage: AppLanguage {
        AppLanguage.resolved(from: locale)
    }

    private var hasTextContent: Bool {
        titleText != nil || subtitleText != nil
    }

    private var isActionable: Bool {
        switch banner.actionType {
        case .news, .event, .organization:
            return nonEmpty(banner.actionTargetID) != nil
        case .externalURL:
            return FeaturedBannerURLNormalizer.normalizedExternalURL(from: banner.externalURL) != nil
        case .none, .unsupportedLegacy:
            return false
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct BannerAccessibilityFallback: ViewModifier {
    let needsFallback: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if needsFallback { content.accessibilityLabel(AppStrings.FeaturedManagement.title) }
        else { content }
    }
}
