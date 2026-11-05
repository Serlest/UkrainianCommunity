import SwiftUI
import UIKit
import LinkPresentation

/// Presents UIKit's activity controller directly. In particular, iPad needs a
/// real popover anchored to the share control, not an activity controller
/// embedded as the child of a SwiftUI sheet.
struct ContentTextSharePresenter: UIViewRepresentable {
    @Binding var isPresented: Bool
    let text: String
    let title: String

    func makeUIView(context: Context) -> Presenter {
        Presenter()
    }

    func updateUIView(_ controller: Presenter, context: Context) {
        controller.configure(presented: isPresented, text: text, title: title) {
            isPresented = false
        }
    }

    static func dismantleUIView(_ controller: Presenter, coordinator: ()) {
        controller.stop()
    }

    final class Presenter: UIView, UIPopoverPresentationControllerDelegate {
        private var requested = false
        private var text = ""
        private var shareTitle = ""
        private var activity: UIActivityViewController?
        private var onFinish: (() -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            presentIfReady()
        }

        func configure(presented: Bool, text: String, title: String, onFinish: @escaping () -> Void) {
            requested = presented
            self.text = text
            self.shareTitle = title
            self.onFinish = onFinish
            if presented {
                presentIfReady()
            } else if let activity {
                activity.dismiss(animated: true) { [weak self] in self?.finish() }
            }
        }

        private func presentIfReady() {
            guard requested, activity == nil, let window, var presenter = window.rootViewController else { return }
            while let presented = presenter.presentedViewController { presenter = presented }
            let controller = UIActivityViewController(
                activityItems: [Item(text: text, title: shareTitle)], applicationActivities: nil
            )
            activity = controller
            controller.completionWithItemsHandler = { [weak self] _, _, _, _ in self?.finish() }
            if traitCollection.userInterfaceIdiom == .pad {
                controller.modalPresentationStyle = .popover
                controller.popoverPresentationController?.sourceView = self
                controller.popoverPresentationController?.sourceRect = bounds
                controller.popoverPresentationController?.delegate = self
            }
            presenter.present(controller, animated: true) { [weak self, weak controller] in
                controller?.presentationController?.delegate = self
            }
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            finish()
        }

        func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) {
            finish()
        }

        private func finish() {
            guard activity != nil else { return }
            activity = nil
            requested = false
            onFinish?()
        }

        func stop() {
            onFinish = nil
            requested = false
            activity?.dismiss(animated: false)
            activity = nil
        }
    }

    /// One plain-text item keeps Copy available and preserves the complete
    /// localized payload for receivers that ignore a separate share message.
    final class Item: NSObject, UIActivityItemSource {
        let text: String
        let title: String

        init(text: String, title: String) { self.text = text; self.title = title }

        func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any { text }

        func activityViewController(_ activityViewController: UIActivityViewController,
                                    itemForActivityType activityType: UIActivity.ActivityType?) -> Any? { text }

        func activityViewController(_ activityViewController: UIActivityViewController,
                                    subjectForActivityType activityType: UIActivity.ActivityType?) -> String { title }

        func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
            let metadata = LPLinkMetadata()
            metadata.title = title
            return metadata
        }
    }
}
