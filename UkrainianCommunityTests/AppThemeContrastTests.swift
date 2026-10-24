import Foundation
import SwiftUI
import Testing
import UIKit
@testable import UkrainianCommunity

struct AppThemeContrastTests {
    @Test func secondaryTextMeetsAAInSupportedAppearances() {
        assertMeetsAA(AppTheme.textSecondary)
    }
    @Test func darkWallpaperCannotWashOutLinksOrSecondaryLabels() {
        UITraitCollection(userInterfaceStyle: .dark).performAsCurrent {
            for overlay in AppTheme.screenBackgroundOverlayColors(for: .dark) {
                func opaque(_ color: UIColor, over background: UIColor) -> UIColor {
                    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                    var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
                    color.getRed(&r, green: &g, blue: &b, alpha: &a)
                    background.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
                    return UIColor(red: r*a+br*(1-a), green: g*a+bg*(1-a), blue: b*a+bb*(1-a), alpha: 1)
                }
                // Pure white is the brightest possible wallpaper pixel.
                let background = opaque(UIColor(overlay).resolvedColor(with: .current), over: .white)
                let link = UIColor(AppTheme.accentPrimaryForeground).resolvedColor(with: .current)
                let secondary = opaque(UIColor(AppTheme.textSecondary).resolvedColor(with: .current), over: background)
                #expect(contrastRatio(link, background) >= 4.5)
                #expect(contrastRatio(secondary, background) >= 4.5)
            }
        }
    }

    @Test
    func primaryForegroundMeetsAAInSupportedAppearances() {
        assertMeetsAA(AppTheme.accentPrimaryForeground)
    }

    @Test
    func destructiveForegroundMeetsAAInSupportedAppearances() {
        assertMeetsAA(AppTheme.accentDestructiveForeground)
    }

    @Test func newsMetadataMeetsAAOnOpaqueCards() {
        for style: UIUserInterfaceStyle in [.light, .dark] {
            UITraitCollection(userInterfaceStyle: style).performAsCurrent {
                let foreground = UIColor(AppTheme.feedSecondaryText).resolvedColor(with: .current)
                let background = UIColor(AppTheme.feedCardSurface).resolvedColor(with: .current)
                #expect(contrastRatio(foreground, background) >= 4.5)
                #expect(background.cgColor.alpha == 1)
            }
        }
    }

    @Test func bannerCaptionRemainsReadableOverWhiteArtwork() {
        for style: UIUserInterfaceStyle in [.light, .dark] {
            UITraitCollection(userInterfaceStyle: style).performAsCurrent {
                let scheme: ColorScheme = style == .dark ? .dark : .light
                let scrim = UIColor(AppTheme.bannerTextScrimBackground(for: scheme)).resolvedColor(with: .current)
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                scrim.getRed(&r, green: &g, blue: &b, alpha: &a)
                // White artwork is the brightest background; subtitle alpha is 0.88.
                let background = UIColor(red: r*a + 1-a, green: g*a + 1-a, blue: b*a + 1-a, alpha: 1)
                background.getRed(&r, green: &g, blue: &b, alpha: &a)
                let subtitle = UIColor(red: 0.88 + r*0.12, green: 0.88 + g*0.12, blue: 0.88 + b*0.12, alpha: 1)
                #expect(contrastRatio(.white, background) >= 4.5)
                #expect(contrastRatio(subtitle, background) >= 4.5)
            }
        }
    }

    @Test func tabForegroundsRemainLegibleOnMaterialExtremes() {
        for style: UIUserInterfaceStyle in [.light, .dark] {
            UITraitCollection(userInterfaceStyle: style).performAsCurrent {
                // Native regular glass and its selected pill vary with content.
                // Include the lightest dark and darkest light surfaces observed
                // in screenshots, in addition to system backgrounds.
                let backgrounds: [UIColor] = style == .dark
                    ? [.init(white: 0.16, alpha: 1), .init(white: 0.25, alpha: 1)]
                    : [.init(white: 0.85, alpha: 1), .white]
                #expect(contrastRatio(AppTheme.tabSelectedColor.resolvedColor(with: .current),
                    AppTheme.tabSelectionSurface.resolvedColor(with: .current)) >= 4.5)
                if style == .dark {
                    #expect(contrastRatio(AppTheme.tabSelectedColor.resolvedColor(with: .current),
                        UIColor(white: 0.45, alpha: 1)) >= 4.5)
                }
                for color in [AppTheme.tabSelectedColor, AppTheme.tabUnselectedColor] {
                    for background in backgrounds {
                        #expect(contrastRatio(color.resolvedColor(with: .current), background) >= 4.5)
                    }
                }
            }
        }
    }

    @Test
    func fixedFillTokensAreNotUsedAsForegroundStyles() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceRoot = projectRoot.appendingPathComponent("UkrainianCommunity", isDirectory: true)
        let expression = try NSRegularExpression(
            pattern: #"foreground(?:Style|Color)\([^\n]*AppTheme\.(?:accentPrimary|accentDestructive)(?!Foreground)"#
        )
        let enumerator = FileManager.default.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: nil
        )
        var violations: [String] = []

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            if expression.firstMatch(in: source, range: range) != nil {
                violations.append(fileURL.path.replacingOccurrences(of: projectRoot.path + "/", with: ""))
            }
        }

        #expect(violations.isEmpty, "Fixed fill colors used as foregrounds: \(violations.sorted())")
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
