import SwiftUI

struct GuideEditorContentSection: View {
    @ObservedObject var viewModel: GuideEditorViewModel

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                AppEditorSectionTitle(title: AppStrings.GuideEditor.contentSection)

                guideInfoCard(
                    title: AppStrings.GuideEditor.bodyFallbackField,
                    message: AppStrings.GuideEditor.bodyFallbackHelp
                )

                guideInfoCard(
                    title: AppStrings.GuideEditor.contentBlocksField,
                    message: AppStrings.GuideEditor.contentBlocksHelp
                )

                AppEditorField(title: AppStrings.GuideEditor.bodyFallbackField) {
                    TextEditor(text: $viewModel.draft.body)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 140)
                        .padding(8)
                        .background(AppTheme.surfaceGlass, in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))

                    guideHelpText(AppStrings.GuideEditor.bodyFallbackHelp)
                }

                GuideArticleSourceLinksEditorView(sourceLinks: $viewModel.draft.sourceLinks)
                guideHelpText(AppStrings.GuideEditor.articleSourceLinksHelp)

                GuideContentBlocksEditorView(blocks: $viewModel.draft.contentBlocks)
            }
        }
    }

    private func guideInfoCard(title: String, message: String) -> some View {
        SoftContentCard(padding: AppTheme.eventsCardPadding) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(message)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func guideHelpText(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(AppTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
