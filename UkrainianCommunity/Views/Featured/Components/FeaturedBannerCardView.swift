import SwiftUI
import UIKit

struct FeaturedBannerCardView: View {
    let banner: FeaturedBanner
    let previewImage: UIImage?
    let onArtworkLoadStateChanged: ((Bool) -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    init(banner: FeaturedBanner, previewImage: UIImage? = nil,
         onArtworkLoadStateChanged: ((Bool) -> Void)? = nil) {
        self.banner = banner
        self.previewImage = previewImage
        self.onArtworkLoadStateChanged = onArtworkLoadStateChanged
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .trailing, spacing: 12) {
                    if let countdown = banner.countdown { FeaturedBannerCountdownView(countdown: countdown) }
                    background.frame(height: 120).clipShape(cardShape).accessibilityHidden(true)
                    if hasTextContent { textContent }
                }
            } else { card }
        }
        .modifier(BannerAccessibilityFallback(needsFallback: !hasTextContent && banner.countdown == nil))
        .accessibilityElement(children: .combine)
        .accessibilityHint(isActionable ? AppStrings.Action.open : "")
    }

    private var card: some View {
        ZStack(alignment: .bottomLeading) {
            background.accessibilityHidden(true)
            visualTreatment.accessibilityHidden(true)
            if hasTextContent {
                textContent
            }
        }
        .overlay(alignment: .topTrailing) {
            if !dynamicTypeSize.isAccessibilitySize, let countdown = banner.countdown {
                FeaturedBannerCountdownView(countdown: countdown)
                    .frame(maxWidth: 230, alignment: .trailing).padding(12)
            }
        }
        .clipShape(cardShape)
        .overlay {
            cardShape.strokeBorder(AppTheme.glassBorder(for: colorScheme).opacity(0.86))
        }
        .shadow(color: AppTheme.glassShadow(for: colorScheme), radius: AppTheme.glassCardShadowRadius, y: AppTheme.glassCardShadowY)
        .contentShape(cardShape)
        .accessibilityElement(children: .combine)
        .accessibilityHint(isActionable ? AppStrings.Action.open : "")
    }

    @ViewBuilder
    private var background: some View {
        GeometryReader { proxy in
#if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("-ui-testing"), ProcessInfo.processInfo.environment["UITestBanner14"] == "1", previewImage == nil {
                fallbackBackground.frame(width: proxy.size.width, height: proxy.size.height)
                    .onAppear { onArtworkLoadStateChanged?(true) }
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
                    onImageLoadStateChanged: onArtworkLoadStateChanged
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

    private var visualTreatment: some View {
        ZStack {
            LinearGradient(
                colors: [
                    .clear,
                    .black.opacity(hasTextContent ? 0.08 : 0),
                    .black.opacity(hasTextContent ? 0.58 : 0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            RadialGradient(
                colors: [
                    AppTheme.accentPrimary.opacity(colorScheme == .dark ? 0.28 : 0.18),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 4,
                endRadius: 220
            )
        }
        .allowsHitTesting(false)
    }

    private var textContent: some View {
        HStack(alignment: .bottom, spacing: AppTheme.eventsControlGroupSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                if let titleText {
                    Text(titleText)
                        .font(AppTheme.featuredBannerTitleFont)
                        .foregroundStyle(AppTheme.textOnHero)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let subtitleText {
                    Text(subtitleText)
                        .font(AppTheme.featuredBannerSubtitleFont)
                        .foregroundStyle(AppTheme.textOnHero.opacity(0.88))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 4)

            if isActionable {
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.textOnHero)
                    .frame(width: 30, height: 30)
                    .background(AppTheme.accentPrimary.opacity(0.92), in: Circle())
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, AppTheme.bannerTextScrimHorizontalPadding)
        .padding(.vertical, AppTheme.bannerTextScrimVerticalPadding)
        .background(
            AppTheme.bannerTextScrimBackground(for: colorScheme),
            in: RoundedRectangle(cornerRadius: AppTheme.bannerTextScrimRadius, style: .continuous)
        )
        .padding(AppTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
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
