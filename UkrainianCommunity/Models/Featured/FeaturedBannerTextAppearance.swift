import Foundation

nonisolated struct FeaturedBannerTextAppearance: Codable, Equatable, Sendable {
    var titleColorHex: String?
    var subtitleColorHex: String?

    static let standard = FeaturedBannerTextAppearance()
    var isValid: Bool {
        [titleColorHex, subtitleColorHex].compactMap { $0 }.allSatisfy { Self.normalizedHex($0) != nil }
    }
    static func normalizedHex(_ value: String) -> String? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil else { return nil }
        return text.uppercased()
    }
}
