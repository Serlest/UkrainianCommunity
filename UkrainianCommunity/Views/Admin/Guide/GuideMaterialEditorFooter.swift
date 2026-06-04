import SwiftUI

struct GuideMaterialEditorFooter: View {
    let isSaving: Bool
    let saveButtonTitle: String
    let onSave: () -> Void

    var body: some View {
        AppEditorSectionCard {
            PrimaryActionButton(
                title: saveButtonTitle,
                loadingTitle: GuideAuthoringPresentation.savingLabel,
                isEnabled: !isSaving,
                isLoading: isSaving,
                systemImage: "square.and.arrow.down"
            ) {
                onSave()
            }
        }
    }
}
