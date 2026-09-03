import SwiftUI
import UIKit

struct AppUpdatePrompt: ViewModifier {
    let isReady: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @StateObject private var controller = AppUpdatePromptController(client: AppUpdateClientFactory.make())
    @State private var windowReference = AppUpdateWindowReference()

    private var canOfferUpdate: Bool { isReady && scenePhase == .active }

    func body(content: Content) -> some View {
        content
            .background(AppUpdateWindowProbe(reference: windowReference).frame(width: 0, height: 0))
            .task(id: canOfferUpdate) {
                guard canOfferUpdate else { return }
                await controller.checkIfNeeded()
                // Do not present underneath an editor, auth sheet, existing
                // alert, navigation transition or the Face ID shield window.
                while !Task.isCancelled, controller.update != nil, !controller.isPresented {
                    if windowReference.canPresent {
                        controller.isPresented = true
                        break
                    }
                    do { try await Task.sleep(for: .milliseconds(500)) }
                    catch { return }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { controller.enteredBackground() }
            }
            .alert(AppStrings.AppUpdate.title, isPresented: Binding(
                get: { controller.isPresented && canOfferUpdate },
                set: { controller.isPresented = $0 }
            )) {
                Button(AppStrings.AppUpdate.updateNow) {
                    openURL(controller.openStore()) { accepted in
                        if !accepted { controller.storeCouldNotOpen() }
                    }
                }
                    .accessibilityIdentifier("appUpdate.now")
                Button(AppStrings.AppUpdate.later, role: .cancel) { controller.later() }
                    .accessibilityIdentifier("appUpdate.later")
            } message: {
                Text(AppStrings.AppUpdate.message(controller.update?.version ?? ""))
            }
    }
}

@MainActor
private final class AppUpdateWindowReference {
    weak var window: UIWindow?
    var canPresent: Bool {
        guard let window, window.isKeyWindow, window.isUserInteractionEnabled,
              let root = window.rootViewController,
              root.presentedViewController == nil,
              !root.isBeingPresented, !root.isBeingDismissed,
              root.transitionCoordinator == nil else { return false }
        return true
    }
}

private struct AppUpdateWindowProbe: UIViewRepresentable {
    let reference: AppUpdateWindowReference
    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        view.reference = reference
        view.isUserInteractionEnabled = false
        return view
    }
    func updateUIView(_ view: Probe, context: Context) { reference.window = view.window }
    final class Probe: UIView {
        weak var reference: AppUpdateWindowReference?
        override func didMoveToWindow() { super.didMoveToWindow(); reference?.window = window }
    }
}
