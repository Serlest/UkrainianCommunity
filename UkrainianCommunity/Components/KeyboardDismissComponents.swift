import SwiftUI
import UIKit

struct DismissKeyboardOnTapModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.simultaneousGesture(
            TapGesture().onEnded {
                dismissKeyboard()
            }
        )
    }
}

struct KeyboardDismissBackground<Background: View>: View {
    let background: Background

    var body: some View {
        background
            .contentShape(Rectangle())
            .onTapGesture {
                dismissKeyboard()
            }
    }
}

private struct KeyboardDismissTapObserver: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        context.coordinator.configure(for: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.configure(for: uiView)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var window: UIWindow?
        private var recognizer: UITapGestureRecognizer?

        func configure(for view: UIView) {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view, let window = view.window else { return }
                guard self.window !== window else { return }

                self.detach()
                let recognizer = UITapGestureRecognizer(target: self, action: #selector(self.handleTap))
                recognizer.cancelsTouchesInView = false
                recognizer.delegate = self
                window.addGestureRecognizer(recognizer)
                self.window = window
                self.recognizer = recognizer
            }
        }

        func detach() {
            if let recognizer {
                window?.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
            window = nil
        }

        @objc private func handleTap() {
            dismissKeyboard()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            !touch.isInsideTextInput && !KeyboardFocusRegion.contains(touch)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

/// Marks the whole input control, including SwiftUI accessory buttons. Window
/// tap observers must not treat its clear/reveal actions as background touches.
private struct KeyboardFocusRegion: UIViewRepresentable {
    private static let regions = NSHashTable<UIView>.weakObjects()

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        Self.regions.add(view)
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
    static func dismantleUIView(_ uiView: UIView, coordinator: ()) { regions.remove(uiView) }

    static func contains(_ touch: UITouch) -> Bool {
        regions.allObjects.contains { region in
            guard region.window === touch.window, !region.bounds.isEmpty else { return false }
            var ancestor: UIView? = region
            while let view = ancestor {
                if view.isHidden || view.alpha < 0.01 { return false }
                ancestor = view.superview
            }
            return region.bounds.contains(touch.location(in: region))
        }
    }
}

extension View {
    func preservesKeyboardFocusWithinBounds() -> some View {
        background(KeyboardFocusRegion())
    }

    func dismissesKeyboardOnBackgroundTap() -> some View {
        modifier(DismissKeyboardOnTapModifier())
    }

    func keyboardDismissBackground<Background: View>(
        @ViewBuilder _ background: () -> Background
    ) -> some View {
        self.background(KeyboardDismissBackground(background: background()))
    }

    func observesKeyboardDismissTaps() -> some View {
        self.background(KeyboardDismissTapObserver().frame(width: 0, height: 0))
    }
}

private func dismissKeyboard() {
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder),
        to: nil,
        from: nil,
        for: nil
    )
}

private extension UITouch {
    var isInsideTextInput: Bool {
        var currentView = view
        while let view = currentView {
            if view is UITextField || view is UITextView {
                return true
            }
            currentView = view.superview
        }
        return false
    }
}
