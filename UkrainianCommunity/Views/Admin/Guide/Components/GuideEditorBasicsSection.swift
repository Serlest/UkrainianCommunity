import SwiftUI

struct GuideEditorBasicsSection: View {
    @ObservedObject var viewModel: GuideEditorViewModel

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                AppEditorSectionTitle(title: AppStrings.GuideEditor.basicsSection)

                AppEditorField(title: AppStrings.GuideEditor.titleField) {
                    TextField(AppStrings.GuideEditor.titlePlaceholder, text: $viewModel.draft.title)
                        .textInputAutocapitalization(.sentences)
                        .textFieldStyle(.roundedBorder)
                }

                AppEditorField(title: AppStrings.GuideEditor.summaryField) {
                    TextEditor(text: $viewModel.draft.summary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 78)
                        .padding(8)
                        .background(AppTheme.surfaceGlass, in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
                }
            }
        }
    }
}
