import SwiftUI

extension OrganizationEditorView {
    var bottomSubmitButton: some View {
        PrimaryActionButton(
            title: bottomSubmitTitle,
            loadingTitle: bottomLoadingTitle,
            isEnabled: canTapSubmit,
            isLoading: isSaving
        ) {
            submit()
        }
    }

    var bottomSubmitTitle: String {
        viewModel.submitButtonTitle(for: authState.user)
    }

    var bottomLoadingTitle: String {
        organizationsViewModel.isUploadingOrganizationImage ? AppStrings.NewsEditor.uploadingImage : AppStrings.Organizations.publishing
    }

    var isSaving: Bool {
        organizationsViewModel.isSavingOrganization || viewModel.isProcessingImage
    }

    var canTapSubmit: Bool {
        viewModel.canSubmit && !isSaving
    }

    func submit() {
        guard canTapSubmit else { return }
        Task {
            let didSave = await viewModel.submit(
                with: organizationsViewModel,
                user: authState.user
            )
            guard didSave else { return }
            await onSaved()
            dismiss()
        }
    }

    func requestClose() {
        if viewModel.shouldConfirmDraftBeforeDismiss {
            isShowingDraftCloseConfirmation = true
        } else {
            dismiss()
        }
    }

    @ViewBuilder
    var statusContent: some View {
        if organizationsViewModel.isSavingOrganization || viewModel.isProcessingImage {
            editorCard {
                Label(
                    organizationsViewModel.isUploadingOrganizationImage ? AppStrings.NewsEditor.uploadingImage : AppStrings.Organizations.publishing,
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.accentPrimary)
            }
        }

        if let errorMessage = viewModel.errorMessage {
            editorCard {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.accentDestructive)
            }
        }

        if let successMessage = viewModel.successMessage {
            editorCard {
                Label(successMessage, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.green)
            }
        }
    }
}
