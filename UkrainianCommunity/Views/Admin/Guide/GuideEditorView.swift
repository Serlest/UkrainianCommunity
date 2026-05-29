import SwiftUI

struct GuideEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: GuideEditorViewModel
    @State private var statusMessage: String?
    @State private var submitConfirmationIsPresented = false

    init() {
        _viewModel = StateObject(wrappedValue: GuideEditorViewModel(
            repository: MockGuideRepository(),
            currentUserId: nil
        ))
    }

    init(viewModel: GuideEditorViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        DetailPageContainer {
            headerCard
            GuideEditorStatusSection(viewModel: viewModel, statusMessage: statusMessage)
            GuideEditorBasicsSection(viewModel: viewModel)
            GuideEditorClassificationSection(viewModel: viewModel)
            GuideEditorContentSection(viewModel: viewModel)
            GuideEditorReviewSettingsSection(viewModel: viewModel)
            GuideEditorActionSection(
                viewModel: viewModel,
                validateAction: validateOnly,
                saveDraftAction: saveDraft,
                submitForReviewAction: confirmSubmitForReview
            )
        }
        .background(AppTheme.subtleGradient.ignoresSafeArea())
        .navigationTitle(AppStrings.GuideEditor.title)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewModel.draft) { _, _ in
            statusMessage = nil
            viewModel.clearSaveState()
        }
        .alert(
            AppStrings.GuideEditor.submitForReviewConfirmationTitle,
            isPresented: $submitConfirmationIsPresented
        ) {
            Button(AppStrings.Common.cancel, role: .cancel) {}
            Button(AppStrings.GuideEditor.submitForReviewAction) {
                submitForReview()
            }
        } message: {
            Text(AppStrings.GuideEditor.submitForReviewConfirmationMessage)
        }
    }

    private var headerCard: some View {
        AppEditorSectionCard {
            SectionHeaderBlock(
                title: AppStrings.GuideEditor.title,
                subtitle: AppStrings.GuideEditor.subtitle
            )
        }
    }

    private func validateOnly() {
        statusMessage = viewModel.validate() ? AppStrings.GuideEditor.validationSuccess : nil
    }

    private func saveDraft() {
        statusMessage = nil
        Task {
            await viewModel.saveDraft()
        }
    }

    private func confirmSubmitForReview() {
        statusMessage = nil
        submitConfirmationIsPresented = true
    }

    private func submitForReview() {
        statusMessage = nil
        Task {
            if await viewModel.submitForReview() {
                dismiss()
            }
        }
    }
}

#Preview {
    NavigationStack {
        GuideEditorView()
    }
}
