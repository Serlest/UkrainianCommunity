import SwiftUI

struct GuideContentBlockTitleField: View {
    let title: String?
    let onChange: (String?) -> Void

    var body: some View {
        TextField(
            AppStrings.GuideEditor.blockTitlePlaceholder,
            text: Binding(
                get: { title ?? "" },
                set: { onChange($0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlankForGuideEditor) }
            )
        )
        .textInputAutocapitalization(.sentences)
        .textFieldStyle(.roundedBorder)
    }
}

struct GuideContentBlockBodyEditor: View {
    let text: String
    let label: String
    let onChange: (String) -> Void

    var body: some View {
        AppEditorField(title: label) {
            TextEditor(
                text: Binding(
                    get: { text },
                    set: { onChange(GuideEditorTextNormalization.normalizedPastedText($0, previousValue: text)) }
                )
            )
            .scrollContentBackground(.hidden)
            .frame(minHeight: 96)
            .padding(8)
            .background(AppTheme.surfaceGlass, in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
        }
    }
}

private extension String {
    var nilIfBlankForGuideEditor: String? {
        isEmpty ? nil : self
    }
}
