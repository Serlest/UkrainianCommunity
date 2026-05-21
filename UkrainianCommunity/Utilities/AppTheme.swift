import SwiftUI

enum AppTheme {
    // Primary blue is the main interaction accent used for navigation,
    // buttons, icons, and branded emphasis throughout the app.
    static let accentPrimary = Color(red: 0.10, green: 0.26, blue: 0.56)

    // Soft blue is intended for subtle badge fills, borders, and tinted surfaces.
    static let accentPrimarySoft = accentPrimary.opacity(0.12)

    // Yellow is a support/highlight accent and should stay restrained.
    static let accentSupport = Color(red: 0.93, green: 0.76, blue: 0.23)

    // Red is reserved for destructive actions and like-state emphasis.
    static let accentDestructive = Color(red: 0.72, green: 0.14, blue: 0.18)

    // Apple-style calm page and surface tokens.
    static let pageBackground = Color(uiColor: .systemGroupedBackground)
    static let pageBackgroundBranded = LinearGradient(
        colors: [
            accentPrimary.opacity(0.08),
            accentSupport.opacity(0.06),
            accentDestructive.opacity(0.05)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let surfacePrimary = Color(uiColor: .secondarySystemGroupedBackground)
    static let surfaceSecondary = Color(uiColor: .tertiarySystemGroupedBackground)
    static let surfaceElevated = Color(uiColor: .secondarySystemGroupedBackground)
    static let surfaceGrouped = Color(uiColor: .secondarySystemGroupedBackground)
    static let surfaceControl = Color(uiColor: .tertiarySystemGroupedBackground)
    static let surfaceGlass = Color(uiColor: .secondarySystemGroupedBackground).opacity(0.88)
    static let surfaceHero = heroGradient
    static let borderSubtle = accentPrimary.opacity(0.06)
    static let shadowSoft = Color.black.opacity(0.035)
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textOnHero = Color.white
    static let badgeBlueFill = accentPrimarySoft
    static let badgeRedFill = accentDestructive.opacity(0.12)
    static let badgeGreenFill = Color.green.opacity(0.12)
    static let badgePurpleFill = Color.purple.opacity(0.12)

    static let pageHorizontal: CGFloat = 16
    static let sectionSpacing: CGFloat = 16
    static let feedSpacing: CGFloat = 24
    static let dashboardSpacing: CGFloat = 12
    static let cardPadding: CGFloat = 18
    static let detailCardPadding: CGFloat = 20
    static let dashboardCardPadding: CGFloat = 8
    static let homeSectionSpacing: CGFloat = 14
    static let homeHeaderHeroSpacing: CGFloat = 14
    static let feedRowSpacing: CGFloat = 14
    static let homeFeedCardPadding: CGFloat = 10
    static let homeBottomContentPadding: CGFloat = 116
    static let appHeaderLogoSize = CGSize(width: 160, height: 56)
    static let appHeaderBottomSpacing: CGFloat = 16
    static let appHeaderLeadingAdjustment: CGFloat = 0
    static let homeHeaderLogoSize = appHeaderLogoSize
    static let homeHeaderLeadingAdjustment = appHeaderLeadingAdjustment
    static let homeHeroFilterSpacing: CGFloat = 18
    static let contentPlanePadding: CGFloat = 10
    static let homeFeedPlanePadding = contentPlanePadding
    static let eventsHeaderContentSpacing: CGFloat = 13
    static let eventsControlGroupSpacing: CGFloat = 10
    static let searchControlHeight: CGFloat = 44
    static let iconButtonSize: CGFloat = 44
    static let metadataIconSize: CGFloat = 18
    static let inputHorizontalPadding: CGFloat = 14
    static let eventsSearchHeight = searchControlHeight
    static let eventsActionButtonSize = iconButtonSize
    static let newsDetailHeroHeight: CGFloat = 260
    static let newsDetailActionButtonSize = iconButtonSize
    static let iconButtonRadius = chipRadius
    static let inputRadius = chipRadius
    static let newsDetailActionButtonRadius = iconButtonRadius
    static let newsEditorSummaryInputHeight: CGFloat = 112
    static let newsEditorSummaryTextHeight: CGFloat = 94
    static let newsEditorBodyInputHeight: CGFloat = 150
    static let newsEditorCoverPreviewHeight: CGFloat = 190
    static let newsEditorDetailRowHeight: CGFloat = 52
    static let newsEditorInputHeight = newsEditorDetailRowHeight
    static let eventsChipTopSpacing: CGFloat = 6
    static let eventsSectionSpacing: CGFloat = 12
    static let eventsListRowSpacing: CGFloat = 10
    static let eventsCardPadding: CGFloat = 8
    static let eventsCardHorizontalSpacing: CGFloat = 10
    static let eventsCardContentSpacing: CGFloat = 5
    static let eventsMetadataSpacing: CGFloat = 8
    static let eventsThumbnailSize: CGFloat = 62
    static let eventsDateRailWidth: CGFloat = 50
    static let detailSectionSpacing: CGFloat = homeSectionSpacing
    static let detailInnerSpacing: CGFloat = dashboardSpacing
    static let detailCompactCardPadding: CGFloat = sectionSpacing
    static let detailTitleFont: Font = .title.weight(.bold)
    static let detailSubtitleFont: Font = .callout.weight(.medium)
    static let detailBodyFont: Font = .callout
    static let detailMetadataFont: Font = .caption.weight(.medium)
    static let detailMetadataIconFont: Font = .caption.weight(.semibold)
    static let detailBodyLineSpacing: CGFloat = 3
    static let detailHeroImageHeight: CGFloat = 220
    static let sectionHeroBannerHeight = heroBannerHeight
    static let eventsHeroHeight = sectionHeroBannerHeight
    static let organizationsHeroHeight = sectionHeroBannerHeight
    static let guideHeroHeight = sectionHeroBannerHeight
    static let organizationsCardPadding: CGFloat = 10
    static let organizationsThumbnailSize: CGFloat = 64
    static let organizationsCategoryCardWidth: CGFloat = 128
    static let organizationsCategoryCardHeight: CGFloat = 108

    static let cardRadius: CGFloat = 17
    static let contentPlaneRadius: CGFloat = 26
    static let heroRadius: CGFloat = 22
    static let imageRadius: CGFloat = 16
    static let chipRadius: CGFloat = 14
    static let feedThumbnailSize: CGFloat = 58
    static let feedThumbnailRadius: CGFloat = 13
    static let heroBannerHeight: CGFloat = 146

    static let heroGradient = LinearGradient(
        colors: [accentPrimary.opacity(0.92), accentDestructive.opacity(0.82), accentSupport.opacity(0.68)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let subtleGradient = LinearGradient(
        colors: [pageBackground, accentPrimary.opacity(0.018), surfacePrimary.opacity(0.72)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func glassSurface(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            Color(red: 0.108, green: 0.124, blue: 0.168).opacity(0.48)
        default:
            Color.white.opacity(0.36)
        }
    }

    static func glassControlSurface(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            Color(red: 0.132, green: 0.152, blue: 0.198).opacity(0.54)
        default:
            Color.white.opacity(0.44)
        }
    }

    static func groupedPlaneSurface(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            Color(red: 0.075, green: 0.090, blue: 0.128).opacity(0.36)
        default:
            Color.white.opacity(0.16)
        }
    }

    static func glassBorder(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            Color.white.opacity(0.075)
        default:
            accentPrimary.opacity(0.075)
        }
    }

    static func glassShadow(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            Color.black.opacity(0.30)
        default:
            Color.black.opacity(0.075)
        }
    }

    static func contentPlaneShadow(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            Color.black.opacity(0.24)
        default:
            Color.black.opacity(0.055)
        }
    }

    // Backward-compatible aliases for the existing codebase. These should be
    // migrated gradually to semantic names in later design-system phases.
    static let primaryBlue = accentPrimary
    static let accentYellow = accentSupport
    static let accentRed = accentDestructive
    static let cardBackground = surfacePrimary
    static let groupedBackground = pageBackground
}
