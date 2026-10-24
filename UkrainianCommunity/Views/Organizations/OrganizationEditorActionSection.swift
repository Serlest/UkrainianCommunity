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
        .accessibilityIdentifier("organizationEditor.submit")
    }

    var bottomSubmitTitle: String {
        viewModel.submitButtonTitle(for: authState.user)
    }

    var bottomLoadingTitle: String {
        organizationsViewModel.isUploadingOrganizationImage ? AppStrings.NewsEditor.uploadingImage : AppStrings.Organizations.publishing
    }

    var isSaving: Bool {
        organizationsViewModel.isSavingOrganization || viewModel.isProcessingImage || viewModel.isSubmitting || isSubmittingForm
    }

    var canTapSubmit: Bool {
        viewModel.canSubmit
            && !isSaving
            && (viewModel.isEditing || (organizationRulesDocument != nil && hasConfirmedOrganizationRules))
    }

    func submit() {
        guard canTapSubmit else { return }
        let identity = ProfileAccessIdentity(user: authState.user)
        isSubmittingForm = true
        Task {
            defer { isSubmittingForm = false }
            let didSave = await viewModel.submit(
                with: organizationsViewModel,
                user: authState.user,
                organizationRulesVersion: organizationRulesDocument?.version
            )
            // Keep the accepted rules and the concrete failure visible so the
            // user can retry without reopening the document and losing context.
            guard didSave, ProfileAccessIdentity(user: authState.user) == identity else { return }
            await onSaved()
            dismiss()
        }
    }

    func requestClose() {
        guard !isSaving else { return }
        if viewModel.isEditing && viewModel.hasUnsavedEdits {
            isShowingEditDiscardConfirmation = true
        } else if viewModel.shouldConfirmDraftBeforeDismiss {
            isShowingDraftCloseConfirmation = true
        } else {
            dismiss()
        }
    }

    @ViewBuilder
    var statusContent: some View {
        if organizationsViewModel.isSavingOrganization || viewModel.isProcessingImage || viewModel.isSubmitting || isSubmittingForm {
            editorCard {
                Label(
                    organizationsViewModel.isUploadingOrganizationImage ? AppStrings.NewsEditor.uploadingImage : AppStrings.Organizations.publishing,
                    systemImage: "arrow.triangle.2.circlepath"
                )
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.accentPrimaryForeground)
            }
        }

        if let errorMessage = viewModel.errorMessage {
            editorCard {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.accentDestructiveForeground)
            }
        }

        if let successMessage = viewModel.successMessage {
            editorCard {
                Label(successMessage, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.accentSuccessForeground)
            }
        }
    }
}
