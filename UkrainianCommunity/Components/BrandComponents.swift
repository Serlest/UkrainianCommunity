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

struct AuthHeaderView: View {
    let title: String
    let subtitle: String

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.pushedScreenHeaderTextSpacing) {
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
