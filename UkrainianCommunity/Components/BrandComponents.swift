import SwiftUI

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

struct AdaptiveBrandLockupView: View {
    enum Layout {
        case horizontal
        case vertical
    }

    let layout: Layout

    var body: some View {
        Group {
            switch layout {
            case .horizontal:
                HStack(spacing: 10) {
                    brandSymbol(size: 56)
                    brandText(titleFont: .title3, subtitleFont: .subheadline)
                }
            case .vertical:
                VStack(spacing: 14) {
                    brandSymbol(size: 132)
                    brandText(titleFont: .largeTitle, subtitleFont: .title2)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppStrings.Home.brandTitle)
    }

    private func brandSymbol(size: CGFloat) -> some View {
        Image("logo1")
            .resizable()
            .frame(width: size * 2.88, height: size)
            .frame(width: size * 0.82, height: size, alignment: .leading)
            .clipped()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private func brandText(titleFont: Font, subtitleFont: Font) -> some View {
        let titleParts = AppStrings.Home.brandTitle.split(separator: " ", maxSplits: 1)
        let primaryTitle = titleParts.first.map(String.init) ?? AppStrings.Home.brandTitle
        let secondaryTitle = titleParts.count > 1 ? String(titleParts[1]) : ""

        return VStack(alignment: layout == .horizontal ? .leading : .center, spacing: 0) {
            Text(primaryTitle)
                .font(titleFont.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)

            Text(secondaryTitle)
                .font(subtitleFont.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimaryForeground)
        }
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct AppBrandHeader<TrailingContent: View>: View {
    @ViewBuilder let trailingContent: TrailingContent

    init(@ViewBuilder trailingContent: () -> TrailingContent) {
        self.trailingContent = trailingContent()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppTheme.eventsControlGroupSpacing) {
                AdaptiveBrandLockupView(layout: .horizontal)
                    .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: 0)

                trailingContent
            }
            VStack(alignment: .leading, spacing: 8) {
                AdaptiveBrandLockupView(layout: .horizontal)
                HStack { Spacer(minLength: 0); trailingContent }
            }
        }
        .frame(maxWidth: .infinity, minHeight: AppTheme.appHeaderLogoSize.height)
        .padding(.leading, AppTheme.appHeaderLeadingAdjustment)
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

            AdaptiveBrandLockupView(layout: .horizontal)
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, minHeight: AppTheme.appHeaderLogoSize.height)
        .accessibilityElement(children: .contain)
    }
}

struct AuthHeaderView: View {
    let title: String
    let subtitle: String

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.pushedScreenHeaderTextSpacing) {
                Text(title)
                    .font(AppTheme.authHeaderTitleFont)
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(subtitle)
                    .font(AppTheme.authHeaderSubtitleFont)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
