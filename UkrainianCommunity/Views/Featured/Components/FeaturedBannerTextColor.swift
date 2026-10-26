import SwiftUI
import UIKit

enum FeaturedBannerTextColor {
    static func color(hex: String?, fallback: Color) -> Color {
        guard let hex, let normalized = FeaturedBannerTextAppearance.normalizedHex(hex),
              let value = UInt32(normalized.dropFirst(), radix: 16) else { return fallback }
        return Color(red: Double((value >> 16) & 255) / 255,
                     green: Double((value >> 8) & 255) / 255,
                     blue: Double(value & 255) / 255)
    }
    static func hex(from color: Color) -> String? {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        let values = [red, green, blue].map { Int((min(1, max(0, $0)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", values[0], values[1], values[2])
    }
    static func shadow(for color: Color, scheme: ColorScheme) -> Color {
        let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(color).resolvedColor(with: traits).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return .black }
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return luminance < 0.45 ? .white : .black
    }
}
