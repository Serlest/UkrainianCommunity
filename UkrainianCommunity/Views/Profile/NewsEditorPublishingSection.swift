import SwiftUI

extension NewsEditorView {
    var newsLocalizationCard: some View {
        editorCard {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: editorCardSpacing) {
                    Text(ContentPublishingStrings.germanFallbackHint)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                    editorField(title: AppStrings.NewsEditor.titleFieldRequired, counterText: counterText(viewModel.germanTitle.count, limit: titleLimit)) {
                        TextField(AppStrings.NewsEditor.titlePlaceholder, text: $viewModel.germanTitle)
                            .newsEditorCompactInputStyle(minHeight: compactInputHeight)
                    }
                    editorField(title: AppStrings.NewsEditor.summaryFieldRequired, counterText: counterText(viewModel.germanSummary.count, limit: summaryLimit)) {
                        TextField(AppStrings.NewsEditor.summaryPlaceholder, text: $viewModel.germanSummary, axis: .vertical)
                            .lineLimit(2...4)
                            .newsEditorCompactInputStyle(minHeight: summaryInputHeight)
                    }
                    editorField(title: AppStrings.NewsEditor.bodySectionTitle, counterText: counterText(viewModel.germanBody.count, limit: bodyLimit)) {
                        TextEditor(text: $viewModel.germanBody)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: bodyInputHeight)
                            .appEditorInputStyle(minHeight: bodyInputHeight)
                    }
                }
                .padding(.top, editorCardSpacing)
            } label: {
                Label(ContentPublishingStrings.germanOptional, systemImage: "globe.europe.africa")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
            }
        }
    }

    var newsMediaMetadataCard: some View {
        editorCard {
            VStack(alignment: .leading, spacing: editorCardSpacing) {
                editorSectionTitle(ContentPublishingStrings.imageDetails)
                editorField(title: ContentPublishingStrings.imageCaption, counterText: counterText(viewModel.imageCaption.count, limit: NewsEditorViewModel.imageCaptionLimit)) {
                    TextField(ContentPublishingStrings.imageCaption, text: $viewModel.imageCaption)
                        .newsEditorCompactInputStyle(minHeight: compactInputHeight)
                }
                editorField(title: ContentPublishingStrings.imageAltText, counterText: counterText(viewModel.imageAlternativeText.count, limit: NewsEditorViewModel.imageAlternativeTextLimit)) {
                    TextField(ContentPublishingStrings.imageAltText, text: $viewModel.imageAlternativeText)
                        .newsEditorCompactInputStyle(minHeight: compactInputHeight)
                }
                editorField(title: ContentPublishingStrings.imageCredit, counterText: counterText(viewModel.imageCredit.count, limit: NewsEditorViewModel.imageCreditLimit)) {
                    TextField(ContentPublishingStrings.imageCredit, text: $viewModel.imageCredit)
                        .newsEditorCompactInputStyle(minHeight: compactInputHeight)
                }
            }
        }
    }

    var newsExternalActionCard: some View {
        editorCard {
            VStack(alignment: .leading, spacing: editorCardSpacing) {
                editorSectionTitle("\(ContentPublishingStrings.callToAction) · \(ContentPublishingStrings.optional)")
                editorField(title: ContentPublishingStrings.linkButtonTitle, counterText: counterText(viewModel.externalActionTitle.count, limit: NewsEditorViewModel.externalActionTitleLimit)) {
                    TextField(ContentPublishingStrings.linkButtonTitle, text: $viewModel.externalActionTitle)
                        .newsEditorCompactInputStyle(minHeight: compactInputHeight)
                }
                editorField(title: "URL", counterText: counterText(viewModel.externalActionURL.count, limit: NewsEditorViewModel.externalActionURLLimit)) {
                    TextField(
                        text: $viewModel.externalActionURL,
                        prompt: Text(verbatim: "https://")
                    ) {
                        Text(verbatim: "URL")
                    }
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .newsEditorCompactInputStyle(minHeight: compactInputHeight)
                }
                if !viewModel.isValidExternalAction {
                    Text(ContentPublishingStrings.secureWebLinkRequired)
                        .font(.caption)
                        .foregroundStyle(AppTheme.accentDestructiveForeground)
                }
            }
        }
    }
}
