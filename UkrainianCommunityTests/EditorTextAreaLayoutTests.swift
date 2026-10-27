import SwiftUI
import Testing
import UIKit
@testable import UkrainianCommunity

@MainActor
struct EditorTextAreaLayoutTests {
    @Test func multilineInputKeepsSeveralReadableLinesAtMaximumTextSize() async throws {
        let normal = try await measure(.large, category: .large)
        let accessible = try await measure(.accessibility5, category: .accessibilityExtraExtraExtraLarge)
        #expect(accessible.fontSize > normal.fontSize * 2)
        #expect(accessible.height > normal.height * 2)
    }

    private func measure(_ size: DynamicTypeSize, category: UIContentSizeCategory) async throws -> (height: CGFloat, fontSize: CGFloat) {
        let text = "A long multiline description that remains editable and scrollable.\nSecond paragraph.\nThird paragraph."
        let content = ScrollView {
            EditorTextArea("Description", text: .constant(text), counterText: "\(text.count)/240")
        }.environment(\.dynamicTypeSize, size)
        let controller = UIHostingController(rootView: content)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 1400))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        controller.view.frame = window.bounds
        controller.view.traitOverrides.preferredContentSizeCategory = category
        for _ in 0..<20 {
            controller.view.layoutIfNeeded()
            if let editor = findTextView(controller.view), editor.bounds.height > 0 { break }
            await Task.yield()
        }
        let editor = try #require(findTextView(controller.view))
        let font = try #require(editor.font)
        let usableHeight = editor.bounds.height - editor.textContainerInset.top - editor.textContainerInset.bottom
        #expect(usableHeight >= font.lineHeight * 3, "The actual native editor must show at least three complete lines")
        #expect(editor.text == text)
        #expect(editor.isEditable && editor.isScrollEnabled)
        return (editor.bounds.height, font.pointSize)
    }

    private func findTextView(_ view: UIView) -> UITextView? {
        if let editor = view as? UITextView { return editor }
        for child in view.subviews {
            if let editor = findTextView(child) { return editor }
        }
        return nil
    }
}
