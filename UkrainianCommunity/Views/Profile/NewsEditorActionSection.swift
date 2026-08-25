import SwiftUI

extension NewsEditorView {
        var editorProgress: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(NewsEditorStep.allCases) { step in
                        Capsule()
                            .fill(step.rawValue <= currentStep.rawValue ? AppTheme.primaryBlue : AppTheme.borderSubtle)
                            .frame(height: 4)
                    }
                }

                Text(currentStep.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .accessibilityElement(children: .combine)
        }

        @ViewBuilder
        var editorStepContent: some View {
            switch currentStep {
            case .basics:
                if !viewModel.isEditing {
                    organizerCard
                }
                mainInformationCard
            case .content:
                coverImageCard
                bodyContentCard
            case .preview:
                additionalDetailsCard
                if let validationMessage = viewModel.validationMessage {
                    editorCard {
                        Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(AppTheme.accentDestructiveForeground)
                    }
                }
                newsPreviewCard
                publicationNoticeCard
            }
        }

        var editorNavigation: some View {
            HStack(spacing: AppTheme.dashboardSpacing) {
                if currentStep != .basics {
                    Button {
                        focusedField = nil
                        currentStep = currentStep.previous
                    } label: {
                        Label(AppStrings.NewsEditor.editorBack, systemImage: "chevron.left")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                if currentStep == .preview {
                    bottomPublishButton
                } else {
                    PrimaryActionButton(
                        title: AppStrings.NewsEditor.editorNext,
                        isEnabled: canAdvanceCurrentStep,
                        isLoading: false
                    ) {
                        focusedField = nil
                        currentStep = currentStep.next
                    }
                }
            }
        }

        var canAdvanceCurrentStep: Bool {
            switch currentStep {
            case .basics:
                viewModel.canAdvanceBasics && hasAuthorizedOrganizerSelection
            case .content:
                viewModel.canAdvanceContent
            case .preview:
                viewModel.canPublish
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
            guard hasAuthorizedOrganizerSelection else {
                viewModel.errorMessage = AppStrings.NewsEditor.organizationPermissionRequired
                currentStep = .basics
                return
            }
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
                        .foregroundStyle(AppTheme.accentPrimaryForeground)
                }
            }

            if let successMessage = viewModel.successMessage {
                editorCard {
                    Label(successMessage, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.accentSuccessForeground)
                }
            }

            if let errorMessage = viewModel.errorMessage {
                editorCard {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.accentDestructiveForeground)
                }
            }

            if viewModel.requiresOrganizationRegionBeforePublishing {
                editorCard {
                    Label(AppStrings.NewsEditor.organizationRegionRequired, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.accentDestructiveForeground)
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
