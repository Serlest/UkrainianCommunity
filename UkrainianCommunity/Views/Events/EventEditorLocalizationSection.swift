import SwiftUI

extension EventEditorView {
    var eventLocalizationCard: some View {
        editorCard {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: editorCardSpacing) {
                    Text(ContentPublishingStrings.germanFallbackHint)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)

                    editorField(title: AppStrings.Events.fieldTitle, counterText: "\(viewModel.germanTitle.count)/120") {
                        TextField(AppStrings.Events.titlePlaceholder, text: $viewModel.germanTitle)
                            .textInputAutocapitalization(.sentences)
                            .eventEditorCompactInputStyle(minHeight: compactInputHeight)
                    }
                    editorField(title: AppStrings.Events.fieldSummary) {
                        multilineInput(
                            placeholder: AppStrings.Events.summaryPlaceholder,
                            text: $viewModel.germanSummary,
                            minHeight: summaryInputHeight,
                            counterText: "\(viewModel.germanSummary.count)/200"
                        )
                    }
                    editorField(title: AppStrings.Events.fieldDetails) {
                        multilineInput(
                            placeholder: AppStrings.Events.detailsPlaceholder,
                            text: $viewModel.germanDetails,
                            minHeight: detailsInputHeight,
                            counterText: "\(viewModel.germanDetails.count)/2000"
                        )
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
}
