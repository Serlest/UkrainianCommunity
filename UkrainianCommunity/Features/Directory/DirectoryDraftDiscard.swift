import SwiftUI

/// New nested drafts have their own cancellation boundary, before joining a category draft.
struct DirectoryDraftDiscard: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    let hasChanges: Bool
    @Binding var isPresented: Bool
    func body(content: Content) -> some View {
        content
            .interactiveDismissDisabled(hasChanges)
            .confirmationDialog(DirectoryEditorText.value("Відкинути зміни?", "Änderungen verwerfen?"),
                                isPresented: $isPresented, titleVisibility: .visible) {
                Button(DirectoryEditorText.value("Відкинути зміни", "Änderungen verwerfen"), role: .destructive) { dismiss() }
                Button(DirectoryEditorText.value("Продовжити редагування", "Weiter bearbeiten"), role: .cancel) {}
            }
    }
}
