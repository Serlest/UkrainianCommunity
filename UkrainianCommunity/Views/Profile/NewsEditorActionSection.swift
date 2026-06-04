import SwiftUI

extension NewsEditorView {
        var editorHeader: some View {
            AppCenteredBrandHeader {
                AppGlassIconButton(systemImage: "xmark", accessibilityLabel: AppStrings.Common.cancel) {
                    requestClose()
                }
            } trailingContent: {
                EmptyView()
            }
        }

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

        var editorTitleBlock: some View {
            VStack(alignment: .leading, spacing: AppTheme.eventsCardContentSpacing) {
                Text(viewModel.isEditing ? AppStrings.NewsEditor.editTitle : AppStrings.NewsEditor.addTitle)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(AppStrings.NewsEditor.editorSubtitle)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
