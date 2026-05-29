import SwiftUI

extension OrganizationEditorView {
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
            AppGlassIconButton(systemImage: "xmark", accessibilityLabel: AppStrings.Common.cancel) {
                dismiss()
            }
        }
        .accessibilityElement(children: .contain)
    }

    var bottomSubmitButton: some View {
        Button(action: submit) {
            HStack(spacing: AppTheme.eventsMetadataSpacing) {
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }

                Text(isSaving ? bottomLoadingTitle : bottomSubmitTitle)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
                    .fill(canTapSubmit ? AppTheme.accentPrimary : AppTheme.accentPrimary.opacity(0.26))
            )
            .shadow(color: AppTheme.accentPrimary.opacity(canTapSubmit ? 0.18 : 0), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(!canTapSubmit)
        .accessibilityLabel(bottomSubmitTitle)
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

    var editorTitleBlock: some View {
        VStack(alignment: .leading, spacing: AppTheme.eventsCardContentSpacing) {
            Text(viewModel.navigationTitle)
                .font(.title2.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(AppStrings.Organizations.editorSubtitle)
                .font(.footnote.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
