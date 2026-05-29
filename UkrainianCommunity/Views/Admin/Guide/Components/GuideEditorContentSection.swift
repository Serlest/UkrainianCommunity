import SwiftUI

struct GuideEditorContentSection: View {
    @ObservedObject var viewModel: GuideEditorViewModel

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                AppEditorSectionTitle(title: AppStrings.GuideEditor.contentSection)

                AppEditorField(title: AppStrings.GuideEditor.bodyFallbackField) {
                    TextEditor(text: $viewModel.draft.body)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 140)
                        .padding(8)
                        .background(AppTheme.surfaceGlass, in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
                }

                GuideArticleSourceLinksEditorView(sourceLinks: $viewModel.draft.sourceLinks)

                GuideContentBlocksEditorView(blocks: $viewModel.draft.contentBlocks)
            }
        }
    }
}
