import SwiftUI
import Testing
import UIKit
@testable import UkrainianCommunity

@Suite("Liquid Glass fallback")
@MainActor
struct AppGlassFallbackTests {
    @Test
    func reduceTransparencyFallbackIsOpaqueInSupportedAppearances() {
        for colorScheme in [ColorScheme.light, .dark] {
            let surface = AppGlassFallbackRole.surface.color(
                for: colorScheme,
                reduceTransparency: true
            )
            let alpha = UIColor(surface).cgColor.alpha

            #expect(alpha >= 0.90)
        }
    }
}
