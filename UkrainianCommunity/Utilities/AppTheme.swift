import SwiftUI

enum AppTheme {
    static let primaryBlue = Color(red: 0.10, green: 0.26, blue: 0.56)
    static let accentYellow = Color(red: 0.93, green: 0.76, blue: 0.23)
    static let accentRed = Color(red: 0.72, green: 0.14, blue: 0.18)
    static let cardBackground = Color(uiColor: .secondarySystemBackground)
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)

    static let heroGradient = LinearGradient(
        colors: [primaryBlue.opacity(0.92), accentRed.opacity(0.82), accentYellow.opacity(0.68)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let subtleGradient = LinearGradient(
        colors: [primaryBlue.opacity(0.08), accentYellow.opacity(0.06), accentRed.opacity(0.05)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
