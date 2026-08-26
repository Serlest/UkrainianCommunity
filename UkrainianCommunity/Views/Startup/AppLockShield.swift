import Combine
import SwiftUI
import UIKit

/// A scene-owned window covers sheets/full-screen presentations without removing
/// their view hierarchy (and therefore without throwing away an editor draft).
struct AppLockShield: UIViewRepresentable {
    let authState: AuthState

    func makeCoordinator() -> Coordinator { Coordinator(authState: authState) }

    func makeUIView(context: Context) -> WindowProbe {
        let view = WindowProbe()
        view.onWindow = { [weak coordinator = context.coordinator] window in
            coordinator?.attach(to: window)
        }
        return view
    }

    func updateUIView(_ uiView: WindowProbe, context: Context) {
        context.coordinator.attach(to: uiView.window)
    }

    static func dismantleUIView(_ uiView: WindowProbe, coordinator: Coordinator) { coordinator.detach() }

    final class WindowProbe: UIView {
        var onWindow: ((UIWindow?) -> Void)?
        override func didMoveToWindow() { super.didMoveToWindow(); onWindow?(window) }
    }

    @MainActor
    final class Coordinator {
        private let authState: AuthState
        private let lock: AppLockService
        private weak var sourceWindow: UIWindow?
        private var shieldWindow: UIWindow?
        private var host: UIHostingController<AppLockScreen>?
        private var curtain: UIView?
        private var observation: AnyCancellable?
        private var observers: [NSObjectProtocol] = []
        private var isActive = false
        private var previousInteraction = true
        private var previousAccessibilityHidden = false

        init(authState: AuthState) {
            self.authState = authState
            lock = authState.appLock
        }

        func attach(to window: UIWindow?) {
            guard let window, let scene = window.windowScene, sourceWindow !== window else { return }
            detach()
            sourceWindow = window
            isActive = scene.activationState == .foregroundActive
            observation = lock.protectionChanges.sink { [weak self] in self?.refresh() }
            let center = NotificationCenter.default
            observers = [
                center.addObserver(forName: UIScene.willDeactivateNotification, object: scene, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.isActive = false
                        self?.refresh()
                    }
                },
                center.addObserver(forName: UIScene.didEnterBackgroundNotification, object: scene, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.lock.enterBackground() }
                },
                center.addObserver(forName: UIScene.didActivateNotification, object: scene, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.isActive = true
                        self?.lock.becomeActive()
                        self?.refresh()
                    }
                }
            ]
            refresh()
        }

        func detach() {
            observation?.cancel()
            observation = nil
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            hideShield()
            sourceWindow = nil
        }

        private func refresh() {
            guard let sourceWindow, let scene = sourceWindow.windowScene else { return }
            let shouldShow = lock.isLocked || (!isActive && lock.needsPrivacyShield)
            guard shouldShow else { hideShield(); return }

            if shieldWindow == nil {
                previousInteraction = sourceWindow.isUserInteractionEnabled
                previousAccessibilityHidden = sourceWindow.accessibilityElementsHidden
                sourceWindow.endEditing(true)
                sourceWindow.isUserInteractionEnabled = false
                sourceWindow.accessibilityElementsHidden = true

                // Also cover the source window itself for app-switcher snapshots.
                let curtain = UIView(frame: sourceWindow.bounds)
                curtain.backgroundColor = .systemBackground
                curtain.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                sourceWindow.addSubview(curtain)
                self.curtain = curtain

                let window = UIWindow(windowScene: scene)
                window.frame = scene.coordinateSpace.bounds
                window.windowLevel = .alert + 1
                let controller = UIHostingController(rootView: screen)
                controller.view.accessibilityViewIsModal = true
                host = controller
                window.rootViewController = controller
                shieldWindow = window
                window.makeKeyAndVisible()
                UIAccessibility.post(notification: .screenChanged, argument: nil)
            } else {
                host?.rootView = screen
                if let curtain { sourceWindow.bringSubviewToFront(curtain) }
            }
        }

        private var screen: AppLockScreen {
            AppLockScreen(lock: lock, showsControls: isActive && lock.isLocked) { [weak self] in
                guard let self else { return false }
                guard await AuthService.shared.signOut() else { return false }
                self.authState.presentAuthFlow(.login)
                return true
            }
        }

        private func hideShield() {
            guard shieldWindow != nil else { return }
            shieldWindow?.isHidden = true
            shieldWindow?.rootViewController = nil
            shieldWindow = nil
            host = nil
            curtain?.removeFromSuperview()
            curtain = nil
            sourceWindow?.isUserInteractionEnabled = previousInteraction
            sourceWindow?.accessibilityElementsHidden = previousAccessibilityHidden
            if isActive { sourceWindow?.makeKey() }
            UIAccessibility.post(notification: .screenChanged, argument: nil)
        }
    }
}
