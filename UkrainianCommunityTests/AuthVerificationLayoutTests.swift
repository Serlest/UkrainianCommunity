import Foundation
import SwiftUI
import Testing
import UIKit
@testable import UkrainianCommunity

@MainActor
struct AuthVerificationLayoutTests {
    @Test
    func verificationAndAuthenticatorLayoutsInBothLanguages() throws {
        let previous = LocalizationStore.language
        defer { LocalizationStore.language = previous }
        for (language, dark) in [(AppLanguage.ukrainian, false), (.german, true)] {
            LocalizationStore.language = language
            let state = AuthState()
            state.setVerificationPendingSession(userID: "layout", email: "member@example.test", notice: .emailSent)
            let coordinator = AuthMultiFactorSignInCoordinator()
            coordinator.begin(factors: [AuthMultiFactorFactor(id: "totp", displayName: "Authenticator", enrollmentDate: .now)])
            for authenticator in [false, true] {
                let content = NavigationStack {
                    Group {
                        if authenticator { MultiFactorSignInView(coordinator: coordinator) }
                        else { EmailVerificationView() }
                    }
                    .environmentObject(state)
                }
                .environment(\.scenePhase, .active)
                .environment(\.locale, Locale(identifier: language.rawValue))
                .preferredColorScheme(dark ? .dark : .light)
                let host = UIHostingController(rootView: content)
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
                window.overrideUserInterfaceStyle = dark ? .dark : .light
                window.rootViewController = host
                window.isHidden = false
                defer { window.isHidden = true }
                host.view.frame = window.bounds
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                var rendered = false
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
                    rendered = host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
                }
                #expect(rendered)
                let data = try #require(image.pngData())
                Attachment.record([UInt8](data), named: "auth-\(authenticator ? "authenticator" : "verification")-\(language.rawValue).png")
            }
        }
    }
}
