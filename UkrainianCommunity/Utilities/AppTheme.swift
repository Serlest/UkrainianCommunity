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
    static let surfacePrimary = Color(uiColor: .secondarySystemBackground)
    static let surfaceSecondary = Color(uiColor: .tertiarySystemBackground)
    static let surfaceElevated = Color(uiColor: .systemBackground)
    static let surfaceHero = heroGradient
    static let borderSubtle = accentPrimary.opacity(0.04)
    static let shadowSoft = Color.black.opacity(0.018)
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

    static let cardRadius: CGFloat = 17
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
        colors: [accentPrimary.opacity(0.018), accentSupport.opacity(0.012), Color(uiColor: .systemBackground)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // Backward-compatible aliases for the existing codebase. These should be
    // migrated gradually to semantic names in later design-system phases.
    static let primaryBlue = accentPrimary
    static let accentYellow = accentSupport
    static let accentRed = accentDestructive
    static let cardBackground = surfacePrimary
    static let groupedBackground = pageBackground
}
