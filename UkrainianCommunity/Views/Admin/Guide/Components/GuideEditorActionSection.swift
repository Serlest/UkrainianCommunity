import SwiftUI

struct GuideEditorActionSection: View {
    @ObservedObject var viewModel: GuideEditorViewModel
    let validateAction: () -> Void
    let saveDraftAction: () -> Void
    let submitForReviewAction: () -> Void

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                Text(AppStrings.GuideEditor.backendNotice)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                ViewThatFits(in: .horizontal) {
                    actionButtons(axis: .horizontal)
                    actionButtons(axis: .vertical)
                }
            }
        }
    }

    @ViewBuilder
    private func actionButtons(axis: Axis) -> some View {
        if axis == .horizontal {
            HStack(spacing: AppTheme.eventsMetadataSpacing) {
                buttons
            }
        } else {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                buttons
            }
        }
    }

    private var buttons: some View {
        Group {
            Button(AppStrings.GuideEditor.validateAction) {
                validateAction()
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isSaving)

            Button(AppStrings.GuideEditor.saveDraftAction) {
                saveDraftAction()
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isSaving)

            if viewModel.canSubmitForReview {
                Button(AppStrings.GuideEditor.submitForReviewAction) {
                    submitForReviewAction()
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isSaving)
            }
        }
    }
}
