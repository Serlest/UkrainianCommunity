import SwiftUI

extension NewsEditorView {
        var bottomPublishButton: some View {
            PrimaryActionButton(
                title: viewModel.primarySubmitButtonTitle,
                loadingTitle: statusMessage,
                isEnabled: viewModel.canPublish,
                isLoading: viewModel.isPublishing || viewModel.isUploadingImage || viewModel.isProcessingImage
            ) {
                submit()
            }
        }

        func submit() {
            Task {
                let didPublish = await viewModel.publish()
                guard didPublish else { return }
                await onPublished()
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
            if viewModel.isPublishing || viewModel.isUploadingImage || viewModel.isProcessingImage {
                editorCard {
                    Label(statusMessage, systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.accentPrimary)
                }
            }

            if let successMessage = viewModel.successMessage {
                editorCard {
                    Label(successMessage, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.green)
                }
            }

            if let errorMessage = viewModel.errorMessage {
                editorCard {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.accentDestructive)
                }
            }

            if viewModel.requiresOrganizationRegionBeforePublishing {
                editorCard {
                    Label(AppStrings.NewsEditor.organizationRegionRequired, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.accentDestructive)
                }
            }
        }

        var statusMessage: String {
            if viewModel.isUploadingImage {
                return AppStrings.NewsEditor.uploadingImage
            }
            if viewModel.isProcessingImage {
                return AppStrings.NewsEditor.processingImage
            }
            return AppStrings.NewsEditor.publishing
        }
}
