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

    private let transitionDuration = 0.25

    init(container: AppContainer) {
        self.container = container
        _legalComplianceMonitor = StateObject(wrappedValue: LegalComplianceMonitorService(
            legalDocumentRepository: container.legalDocumentRepository,
            userRepository: container.userRepository
        ))
    }

    private var reduceMotionEnabled: Bool {
        UIAccessibility.isReduceMotionEnabled
    }

    var body: some View {
        ZStack {
            if authState.isRestoring || isShowingSplash {
                SplashLoadingView()
            } else if authState.isAuthenticated,
                      let requirement = legalComplianceMonitor.activeRequirement,
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
                .preferredColorScheme(AppAppearance.stored.colorScheme)
                .environment(\.locale, Locale(identifier: AppLanguage.stored.rawValue))
            } else if authState.isAuthenticated
                        && legalComplianceMonitor.verifiedKey != legalComplianceKey {
                SplashLoadingView()
            } else if authState.isAuthenticated || usesGuestUITestFixture {
                ContentView(container: container)
                    .environmentObject(authState)
            } else {
                AuthFlowContainerView(initialDestination: requiredAuthDestination, allowsDismissal: false)
                    .id(requiredAuthDestination)
                    .environmentObject(authState)
                    .preferredColorScheme(AppAppearance.stored.colorScheme)
                    .environment(\.locale, Locale(identifier: AppLanguage.stored.rawValue))
            }
        }
        .background(AppLockShield(authState: authState).frame(width: 0, height: 0))
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
