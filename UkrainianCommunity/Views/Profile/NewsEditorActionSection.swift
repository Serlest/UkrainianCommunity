import SwiftUI

extension NewsEditorView {
        var editorHeader: some View {
            ZStack {
                BrandMarkView(
                    size: headerLogoSize.height,
                    width: headerLogoSize.width,
                    assetName: "logo1",
                    contentMode: .fit
                )
                .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, minHeight: AppTheme.iconButtonSize)
            .overlay(alignment: .leading) {
                headerIconButton(systemImage: "xmark", accessibilityLabel: AppStrings.Common.cancel) {
                    requestClose()
                }
            }
            .accessibilityElement(children: .contain)
        }

        func headerIconButton(systemImage: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accentPrimary)
                    .frame(width: AppTheme.iconButtonSize, height: AppTheme.iconButtonSize)
                    .background(
                        reduceTransparency ? AppTheme.glassFallbackSurface(for: colorScheme) : AppTheme.glassControlSurface(for: colorScheme),
                        in: RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
                    )
                    .background {
                        if !reduceTransparency {
                            RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
                                .fill(.ultraThinMaterial)
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
                            .strokeBorder(AppTheme.glassBorder(for: colorScheme))
                    )
                    .shadow(color: AppTheme.glassShadow(for: colorScheme), radius: 5, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
        }

        var bottomPublishButton: some View {
            Button(action: submit) {
                HStack(spacing: AppTheme.eventsMetadataSpacing) {
                    if viewModel.isPublishing || viewModel.isUploadingImage || viewModel.isProcessingImage {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }

                    Text(viewModel.isPublishing || viewModel.isUploadingImage || viewModel.isProcessingImage ? statusMessage : viewModel.primarySubmitButtonTitle)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
                        .fill(viewModel.canPublish ? AppTheme.accentPrimary : AppTheme.accentPrimary.opacity(0.26))
                )
                .shadow(color: AppTheme.accentPrimary.opacity(viewModel.canPublish ? 0.18 : 0), radius: 12, y: 6)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canPublish || viewModel.isPublishing || viewModel.isUploadingImage || viewModel.isProcessingImage)
            .accessibilityLabel(viewModel.primarySubmitButtonTitle)
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
