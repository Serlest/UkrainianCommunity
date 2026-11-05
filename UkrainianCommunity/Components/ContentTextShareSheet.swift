import SwiftUI
import UIKit
import LinkPresentation

/// Retains a plain-text representation for Copy and messenger receivers while
/// providing a readable title. ShareLink's custom-preview overload can offer
/// String as a file instead, removing Copy on some iOS versions.
struct ContentTextShareSheet: UIViewControllerRepresentable {
    let text: String
    let title: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [context.coordinator], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}

    func makeCoordinator() -> Item { Item(text: text, title: title) }

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
