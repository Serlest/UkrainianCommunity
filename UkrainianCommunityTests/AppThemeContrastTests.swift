import SwiftUI
import Testing
import UIKit
@testable import UkrainianCommunity

struct AppThemeContrastTests {
    @Test
    func primaryForegroundMeetsAAInSupportedAppearances() {
        assertMeetsAA(AppTheme.accentPrimaryForeground)
    }

    @Test
    func destructiveForegroundMeetsAAInSupportedAppearances() {
        assertMeetsAA(AppTheme.accentDestructiveForeground)
    }

    private func assertMeetsAA(_ color: Color) {
        let appearances: [(UIUserInterfaceStyle, UIAccessibilityContrast)] = [
            (.light, .normal),
            (.light, .high),
            (.dark, .normal),
            (.dark, .high)
        ]

        for (style, contrast) in appearances {
            let styleTraits = UITraitCollection(userInterfaceStyle: style)
            let contrastTraits = UITraitCollection(accessibilityContrast: contrast)

            styleTraits.performAsCurrent {
                contrastTraits.performAsCurrent {
                    let foreground = UIColor(color)
                        .resolvedColor(with: .current)
                    let backgrounds = [
                        UIColor.systemGroupedBackground,
                        UIColor.secondarySystemGroupedBackground,
                        UIColor.tertiarySystemGroupedBackground
                    ]

                    for background in backgrounds {
                        let ratio = contrastRatio(
                            foreground,
                            background.resolvedColor(with: .current)
                        )
                        #expect(ratio >= 4.5)
                    }
                }
            }
        }
    }

    private func contrastRatio(_ first: UIColor, _ second: UIColor) -> Double {
        let firstLuminance = relativeLuminance(first)
        let secondLuminance = relativeLuminance(second)
        return (max(firstLuminance, secondLuminance) + 0.05)
            / (min(firstLuminance, secondLuminance) + 0.05)
    }

    private func relativeLuminance(_ color: UIColor) -> Double {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        #expect(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))

        func linearize(_ component: CGFloat) -> Double {
            let value = Double(component)
            return value <= 0.04045
                ? value / 12.92
                : pow((value + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * linearize(red)
            + 0.7152 * linearize(green)
            + 0.0722 * linearize(blue)
    }
}
