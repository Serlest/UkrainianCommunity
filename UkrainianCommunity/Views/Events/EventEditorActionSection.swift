import SwiftUI

extension EventEditorView {
        var editorProgress: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(EventEditorStep.allCases) { step in
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
                mainCard
                imageCard
            case .schedule:
                dateTimeCard
                locationCard
            case .audience:
                categoryCard
                audienceCard
                additionalSettingsCard
                organizerContactCard
                tagsCard
            case .preview:
                if let validationMessage = viewModel.validationMessage {
                    editorStatusCard {
                        Label(validationMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(AppTheme.accentDestructiveForeground)
                    }
                }
                eventPreviewCard
                publishNoticeCard
            }
        }

        var editorNavigation: some View {
            HStack(spacing: AppTheme.dashboardSpacing) {
                if currentStep != .basics {
                    Button {
                        currentStep = currentStep.previous
                    } label: {
                        Label(AppStrings.Events.editorBack, systemImage: "chevron.left")
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }

                if currentStep == .preview {
                    bottomSubmitButton
                } else {
                    PrimaryActionButton(
                        title: AppStrings.Events.editorNext,
                        isEnabled: canAdvanceCurrentStep,
                        isLoading: false
                    ) {
                        currentStep = currentStep.next
                    }
                }
            }
        }

        var canAdvanceCurrentStep: Bool {
            switch currentStep {
            case .basics:
                viewModel.canAdvanceBasics && hasAuthorizedOrganizerSelection
            case .schedule:
                viewModel.canAdvanceSchedule
            case .audience:
                viewModel.canAdvanceAudience
            case .preview:
                viewModel.canPublish
            }
        }

        var eventPreviewCard: some View {
            editorCard {
                VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                    editorSectionTitle(AppStrings.Events.editorPreviewTitle)

                    Text(viewModel.title)
                        .font(AppTheme.cardTitleFont)
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(viewModel.summary)
                        .font(AppTheme.cardSubtitleFont)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Label(
                        LocalizationStore.dateString(
                            from: viewModel.startDate,
                            dateStyle: .full,
                            timeStyle: viewModel.isAllDay ? .none : .short
                        ),
                        systemImage: "calendar"
                    )

                    Label(
                        [viewModel.venue, viewModel.city]
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                            .joined(separator: ", "),
                        systemImage: "mappin.and.ellipse"
                    )

                    AppHorizontalChipRow {
                        AppInfoChip(
                            title: viewModel.selectedCategory.title,
                            systemImage: viewModel.selectedCategory.systemImage,
                            tint: AppTheme.accentPrimaryForeground,
                            fill: AppTheme.badgeBlueFill
                        )
                        AppInfoChip(
                            title: viewModel.selectedAudience.title,
                            systemImage: viewModel.selectedAudience.systemImage,
                            tint: AppTheme.textSecondary,
                            fill: AppTheme.surfaceControl
                        )
                        if viewModel.requiresRegistration {
                            AppInfoChip(
                                title: AppStrings.Events.requiresRegistrationToggle,
                                systemImage: "checklist",
                                tint: AppTheme.accentSuccessForeground,
                                fill: AppTheme.badgeGreenFill
                            )
                        }
                    }
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
            }
        }

        @ViewBuilder
        var statusContent: some View {
            if viewModel.isPublishing || viewModel.isUploadingImage || viewModel.isProcessingImage {
                editorStatusCard {
                    Label(statusMessage, systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.accentPrimaryForeground)
                }
            }

            if let errorMessage = viewModel.errorMessage {
                editorStatusCard {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.accentDestructiveForeground)
                }
            }

            if let successMessage = viewModel.successMessage {
                editorStatusCard {
                    Label(successMessage, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.accentSuccessForeground)
                }
            }

            if viewModel.requiresOrganizationRegionBeforePublishing {
                editorStatusCard {
                    Label(AppStrings.Events.organizationRegionRequired, systemImage: "exclamationmark.triangle.fill")
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
            return AppStrings.Events.publishing
        }


        var bottomSubmitButton: some View {
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
                viewModel.errorMessage = AppStrings.Events.organizationRequired
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
}
