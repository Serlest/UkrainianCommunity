import SwiftUI

struct FeaturedBannerCardView: View {
    let banner: FeaturedBanner
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            background
            readabilityOverlay
            textContent
        }
        .clipShape(cardShape)
        .overlay {
            cardShape.strokeBorder(AppTheme.glassBorder(for: colorScheme).opacity(0.86))
        }
        .shadow(color: AppTheme.glassShadow(for: colorScheme), radius: AppTheme.glassCardShadowRadius, y: AppTheme.glassCardShadowY)
        .contentShape(cardShape)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var background: some View {
        GeometryReader { proxy in
            if let imageURL = banner.imageURL?.trimmingCharacters(in: .whitespacesAndNewlines), !imageURL.isEmpty {
                RemoteImageView(
                    imageURL: imageURL,
                    height: proxy.size.height,
                    cornerRadius: AppTheme.heroRadius,
                    source: "FeaturedBannerCardView",
                    placeholderStyle: .glassSkeleton
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
            } else {
                fallbackBackground
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
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

    private var readabilityOverlay: some View {
        AppTheme.bannerOverlayGradient(for: colorScheme)
    }

    private var textContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(banner.title)
                .font(AppTheme.screenTitleFont)
                .foregroundStyle(AppTheme.textOnHero)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            if let subtitle = banner.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !subtitle.isEmpty {
                Text(subtitle)
                    .font(AppTheme.secondaryBodyFont.weight(.medium))
                    .foregroundStyle(AppTheme.textOnHero.opacity(0.88))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(AppTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppTheme.heroRadius, style: .continuous)
    }

    private var accessibilityLabel: String {
        [banner.title, banner.subtitle]
            .compactMap { value in
                let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return trimmed.isEmpty ? nil : trimmed
            }
            .joined(separator: ", ")
    }
}
