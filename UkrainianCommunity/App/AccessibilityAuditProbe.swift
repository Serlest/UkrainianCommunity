#if DEBUG && targetEnvironment(simulator)
import SwiftUI

/// Read-only observation for UI tests after changing the real system settings.
/// Does not override any accessibility environment values or render test chrome.
struct AccessibilityAuditProbe: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        Text(" ")
            .font(.system(size: 1))
            .foregroundStyle(.clear)
            .frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityLabel("Accessibility audit observation")
            .accessibilityIdentifier("audit.accessibilityProbe")
            .accessibilityValue("motion=\(reduceMotion ? 1 : 0);transparency=\(reduceTransparency ? 1 : 0);contrast=\(contrast == .increased ? 1 : 0)")
            .allowsHitTesting(false)
    }
}
#endif
