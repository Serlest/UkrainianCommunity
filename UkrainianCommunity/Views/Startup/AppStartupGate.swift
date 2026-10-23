import SwiftUI
import UIKit
import GoogleSignIn

struct AppStartupGate: View {
    let container: AppContainer

    @EnvironmentObject private var authState: AuthState
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var legalComplianceMonitor: LegalComplianceMonitorService
    @ObservedObject private var remoteNotificationRouteCoordinator = RemoteNotificationRouteCoordinator.shared
    @State private var isShowingSplash = true
    @State private var hasEnteredBackground = false
    @State private var mountedContentUserID: String?

    private let transitionDuration = 0.25

    init(container: AppContainer) {
        self.container = container
        _legalComplianceMonitor = StateObject(wrappedValue: LegalComplianceMonitorService(
            legalDocumentRepository: container.legalDocumentRepository,
            userRepository: container.userRepository,
            foregroundVerificationInterval: Self.foregroundVerificationInterval
        ))
    }

    private static var foregroundVerificationInterval: TimeInterval? {
#if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-ui-testing"),
           ProcessInfo.processInfo.environment["UITestLegalReverification"] != nil { return 0 }
#endif
        return nil
    }

    private var reduceMotionEnabled: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    var body: some View {
        rootContent
        .background(AppAccessShield(
            authState: authState,
            isAccessBlocked: authState.isAuthenticated && !isAccessReady,
            accessContent: accessGateContent
                .environmentObject(authState)
                .preferredColorScheme(AppAppearance.stored.colorScheme)
                .environment(\.locale, Locale(identifier: AppLanguage.stored.rawValue))
        ).frame(width: 0, height: 0))
        .onChange(of: readyContentUserID, initial: true) { _, userID in
            if let userID { mountedContentUserID = userID }
        }
        .onChange(of: authState.user?.id) { _, userID in
            if userID == nil { mountedContentUserID = nil }
        }
        .onAppear {
            evaluateStartupState()
        }
        .onChange(of: authState.isRestoring) { _, _ in
            evaluateStartupState()
        }
        .task(id: legalComplianceKey) {
            await legalComplianceMonitor.configure(user: authState.isAuthenticated ? authState.user : nil)
        }
        .onChange(of: legalComplianceMonitor.activeRequirement, initial: true) { _, _ in
            markPendingLegalRouteHandledByRequiredReview()
        }
        .onChange(of: remoteNotificationRouteCoordinator.pendingRoute) { _, _ in
            markPendingLegalRouteHandledByRequiredReview()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { hasEnteredBackground = true }
            guard phase == .active else { return }
            let resumedFromBackground = hasEnteredBackground
            hasEnteredBackground = false
            guard resumedFromBackground, authState.isAuthenticated else { return }
            Task { await legalComplianceMonitor.verifyAfterBackgroundIfNeeded(user: authState.user) }
        }
        .onOpenURL { url in
            _ = GIDSignIn.sharedInstance.handle(url)
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        // Once admitted, keep the same account's entire view hierarchy mounted.
        // Temporary verification gates must not destroy its @State/navigation.
        if authState.isAuthenticated, let userID = authState.user?.id,
           mountedContentUserID == userID {
            ContentView(container: container, isStartupReady: isAccessReady)
                .id(userID)
                .environmentObject(authState)
        } else if usesGuestUITestFixture {
            ContentView(container: container)
                .environmentObject(authState)
        } else if authState.isRestoring || isShowingSplash || authState.isAuthenticated {
            SplashLoadingView()
        } else {
            AuthFlowContainerView(initialDestination: requiredAuthDestination, allowsDismissal: false)
                .id(requiredAuthDestination)
                .environmentObject(authState)
                .preferredColorScheme(AppAppearance.stored.colorScheme)
                .environment(\.locale, Locale(identifier: AppLanguage.stored.rawValue))
        }
    }

    private var isAccessReady: Bool {
        !authState.isRestoring && !isShowingSplash && authState.isAuthenticated
            && legalComplianceMonitor.verificationFailure == nil
            && legalComplianceMonitor.activeRequirement == nil
            && legalComplianceMonitor.verifiedKey == legalComplianceKey
    }

    private var readyContentUserID: String? {
        isAccessReady ? authState.user?.id : nil
    }

    @ViewBuilder
    private var accessGateContent: some View {
        if authState.presentedAuthFlow == .privilegedMultiFactorRequirement {
            // A protected session may be needed to accept legal updates.
            // Keep that security flow reachable even when legal verification fails.
            AuthFlowContainerView(initialDestination: .privilegedMultiFactorRequirement, allowsDismissal: false)
                .environmentObject(authState)
        } else if let failure = legalComplianceMonitor.verificationFailure {
            StartupAccessFailureView(failure: failure) {
                await legalComplianceMonitor.retryVerification(user: authState.user)
            }
        } else if let requirement = legalComplianceMonitor.activeRequirement,
                  requirement.userID == authState.user?.id {
            LegalComplianceView(
                requirement: requirement,
                isAccepting: legalComplianceMonitor.isAccepting,
                errorMessage: legalComplianceMonitor.errorMessage,
                accept: {
                    Task { await legalComplianceMonitor.acceptRequiredDocuments(authState: authState) }
                },
                decline: {
                    Task { await legalComplianceMonitor.declineAndSignOut() }
                }
            )
        } else {
            SplashLoadingView()
                .accessibilityIdentifier("startup.access.verifying")
        }
    }

    private var requiredAuthDestination: AuthFlowDestination {
        if let presented = authState.presentedAuthFlow { return presented }
        switch authState.sessionState {
        case .verificationPending: return .emailVerification
        case .registrationPending: return .socialRegistration
        case .sessionUnavailable: return .sessionRecovery
        default: return .landing
        }
    }

    private var legalComplianceKey: String {
        guard authState.isAuthenticated, let user = authState.user else { return "signed-out" }
        return [user.id, user.acceptedTermsVersion ?? "", user.acceptedPrivacyVersion ?? ""]
            .joined(separator: ":")
    }

    private var usesGuestUITestFixture: Bool {
#if DEBUG && targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains("-ui-testing")
            && ProcessInfo.processInfo.environment["UITestForceGuestSession"] == "1"
#else
        false
#endif
    }

    private func markPendingLegalRouteHandledByRequiredReview() {
        guard authState.isAuthenticated,
              let requirement = legalComplianceMonitor.activeRequirement,
              requirement.userID == authState.user?.id,
              !requirement.requiredDocuments.isEmpty else { return }
        remoteNotificationRouteCoordinator.markLegalRouteHandledByRequiredReview(
            reviewedDocumentTypes: Set(requirement.requiredDocuments.map(\.type))
        )
    }

    private func evaluateStartupState() {
        guard isShowingSplash else {
            return
        }

        guard !authState.isRestoring else {
            return
        }

        if reduceMotionEnabled {
            isShowingSplash = false
        } else {
            withAnimation(.easeInOut(duration: transitionDuration)) {
                isShowingSplash = false
            }
        }
    }
}
