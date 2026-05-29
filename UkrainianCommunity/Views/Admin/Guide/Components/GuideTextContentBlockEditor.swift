import SwiftUI

struct GuideTextContentBlockEditor: View {
    @Binding var block: GuideContentBlock

    var body: some View {
        if case .text(let value) = block {
            GuideContentBlockTitleField(title: value.title) { title in
                block = .text(.init(id: value.id, title: title, text: value.text))
            }

            GuideContentBlockBodyEditor(
                text: value.text,
                label: AppStrings.GuideEditor.blockTextField
            ) { text in
                block = .text(.init(id: value.id, title: value.title, text: text))
            }
        }
    }
}

