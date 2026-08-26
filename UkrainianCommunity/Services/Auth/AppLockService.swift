import Combine
import CryptoKit
import Foundation
import LocalAuthentication

enum AppBiometry: Equatable {
    case faceID, touchID, unavailable

    var symbol: String { self == .touchID ? "touchid" : "faceid" }
}

@MainActor
protocol LocalAuthenticationProviding: AnyObject {
    var biometry: AppBiometry { get }
    func authenticate(reason: String) async throws -> Bool
    func cancel()
}

@MainActor
final class DeviceLocalAuthentication: LocalAuthenticationProviding {
    private var context: LAContext?

    var biometry: AppBiometry {
        let probe = LAContext()
        var error: NSError?
        let available = probe.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        // A temporary biometric lockout still permits device-passcode recovery.
        guard available || (error as? LAError)?.code == .biometryLockout else { return .unavailable }
        switch probe.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        default: return .unavailable
        }
    }

    func authenticate(reason: String) async throws -> Bool {
        cancel()
        let next = LAContext()
        context = next
        next.localizedCancelTitle = AppStrings.Common.cancel
        var error: NSError?
        guard next.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw error ?? NSError(domain: LAError.errorDomain, code: LAError.biometryNotAvailable.rawValue)
        }
        defer { if context === next { context = nil } }
        return try await next.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
    }

    func cancel() {
        context?.invalidate()
        context = nil
    }
}

/// Device-local access gate, not a Firebase identity or permission provider.
/// Stores only a preference under a hashed UID, never a password or auth token.
@MainActor
final class AppLockService: ObservableObject {
    @Published private(set) var userID: String?
    @Published private(set) var isEnabled = false
    @Published private(set) var isUnlocked = false
    @Published private(set) var isAuthenticating = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var biometry: AppBiometry = .unavailable

    // Emitted synchronously AFTER mutations, so a window shield can be installed
    // before AuthState publishes a restored account or UIKit takes a snapshot.
    let protectionChanges = PassthroughSubject<Void, Never>()
    private let defaults: UserDefaults
    private let authentication: any LocalAuthenticationProviding
    private let storageKey = "appLock.enabledAccounts.v1"
    private var generation = 0
    private var isInBackground = false

    init(defaults: UserDefaults = .standard, authentication: (any LocalAuthenticationProviding)? = nil) {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing"),
           let scenario = ProcessInfo.processInfo.environment["UITestAppLockScenario"] {
            let suite = "UkrainianCommunity.AppLock.UITests"
            let testDefaults = UserDefaults(suiteName: suite)!
            if ProcessInfo.processInfo.environment["UITestResetAppLock"] == "1" {
                testDefaults.removePersistentDomain(forName: suite)
            }
            self.defaults = testDefaults
            self.authentication = ScriptedLocalAuthentication(scenario: scenario)
            return
        }
#endif
        self.defaults = defaults
        self.authentication = authentication ?? DeviceLocalAuthentication()
    }

    var isLocked: Bool { userID != nil && isEnabled && !isUnlocked }
    var needsPrivacyShield: Bool { userID != nil && (isEnabled || isAuthenticating) }

    func updateSession(userID: String?, passwordAuthenticated: Bool = false) {
        if self.userID != userID {
            cancelAuthentication()
            self.userID = userID
            isUnlocked = false
        }
        isEnabled = userID.map { defaults.bool(forKey: preferenceKey($0)) } ?? false
        if passwordAuthenticated, userID != nil { isUnlocked = !isInBackground }
        if userID == nil { isUnlocked = false }
        errorMessage = nil
        protectionChanges.send()
    }

    func refreshAvailability() { biometry = authentication.biometry }

    func enterBackground() {
        isInBackground = true
        lock()
    }

    func becomeActive() {
        isInBackground = false
        refreshAvailability()
    }

    func lock() {
        cancelAuthentication()
        isUnlocked = false
        protectionChanges.send()
    }

    func cancelAuthentication() {
        generation &+= 1
        authentication.cancel()
        isAuthenticating = false
        errorMessage = nil
        protectionChanges.send()
    }

    func unlock() async {
        guard isLocked, !isAuthenticating else { return }
        await evaluate(changePreference: nil)
    }

    func setEnabled(_ enabled: Bool) async {
        guard userID != nil, !isAuthenticating, enabled != isEnabled else { return }
        refreshAvailability()
        if enabled && biometry == .unavailable {
            errorMessage = AppStrings.AppLock.unavailable
            return
        }
        // Disabling protection also requires device-owner authentication.
        await evaluate(changePreference: enabled)
    }

    private func evaluate(changePreference: Bool?) async {
        guard let expectedUserID = userID else { return }
        generation &+= 1
        let request = generation
        isAuthenticating = true
        errorMessage = nil
        protectionChanges.send()
        do {
            let accepted = try await authentication.authenticate(reason: AppStrings.AppLock.reason)
            guard generation == request, userID == expectedUserID else { return }
            if accepted {
                if let changePreference {
                    defaults.set(changePreference, forKey: preferenceKey(expectedUserID))
                    isEnabled = changePreference
                }
                isUnlocked = true
            } else {
                errorMessage = AppStrings.AppLock.failed
            }
        } catch {
            guard generation == request, userID == expectedUserID else { return }
            let code = (error as? LAError)?.code
            if code != .userCancel && code != .appCancel && code != .systemCancel {
                errorMessage = AppStrings.AppLock.failed
            }
        }
        guard generation == request, userID == expectedUserID else { return }
        isAuthenticating = false
        refreshAvailability()
        protectionChanges.send()
    }

    private func preferenceKey(_ userID: String) -> String {
        let hash = SHA256.hash(data: Data(userID.utf8)).map { String(format: "%02x", $0) }.joined()
        return storageKey + "." + hash
    }
}

#if DEBUG
/// UI-test transport only. Never compiled into a Release/TestFlight binary.
@MainActor
private final class ScriptedLocalAuthentication: LocalAuthenticationProviding {
    let scenario: String
    private var attempts = 0
    init(scenario: String) { self.scenario = scenario }
    var biometry: AppBiometry { scenario == "unavailable" ? .unavailable : .faceID }
    func authenticate(reason: String) async throws -> Bool {
        attempts += 1
        try await Task.sleep(for: .milliseconds(200))
        // First call enables protection. The first subsequent unlock fails.
        return !(scenario == "failureThenSuccess" && attempts == 2)
    }
    func cancel() {}
}
#endif
