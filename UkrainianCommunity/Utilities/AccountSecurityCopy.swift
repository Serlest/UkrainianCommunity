import Foundation

enum AccountSecurityCopy {
    private static func text(_ key: String, _ fallback: String) -> String {
        LocalizationStore.localizedString("account_security_help." + key, defaultValue: fallback, table: "AccountSecurity")
    }

    static var recoveryTitle: String { text("recovery.title", "Sign-in help") }
    static var recoveryAction: String { text("recovery.action", "Can't access your code?") }
    static var recoveryBody: String { text("recovery.body", "If you have a saved passkey, close this window, cancel code verification and choose passkey sign-in.\n\nIf neither your authenticator nor a passkey is available, contact support. Recovery options can be reviewed after confirming account ownership.\n\nDo not send passwords or one-time codes.") }
    static var contactSupport: String { text("recovery.contact", "Contact support") }
    static var close: String { text("recovery.close", "Close") }
    static var registrationHelp: String { text("app_lock.registration_help", "Optional. Confirm protection with Face ID, Touch ID or your device passcode. It will apply to this account on this device after registration. You can change it in Profile settings. Your account's sign-in methods remain available.") }
    static var settingsHelp: String { text("app_lock.settings_help", "Protection applies after the selected interval in the background. After restarting, Face ID, Touch ID or your device passcode is required. After signing out, use one of the sign-in methods linked to your account.") }
    static var alternativeSignIn: String { text("app_lock.alternative_sign_in", "Use another sign-in method") }
    static var authenticationFailed: String { text("app_lock.authentication_failed", "Access could not be confirmed. Try again or choose another sign-in method.") }
}

enum AccountRecoverySupport {
    // Public support contact in bundled and published privacy policy 2026.22.
    static let email = "ukrainian.community@outlook.com"

    static var composeURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        return components.url
    }
}
