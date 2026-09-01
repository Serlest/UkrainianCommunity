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
                eventLocalizationCard
                imageCard
            case .schedule:
                dateTimeCard
                occurrencesCard
                locationCard
            case .audience:
                categoryCard
                audienceCard
                additionalSettingsCard
                organizerContactCard
                tagsCard
            case .preview:
                eventPublicationSettingsCard
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

        var eventPublicationSettingsCard: some View {
            Group {
                if !viewModel.isEditing {
                    editorCard {
                        VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                            editorSectionTitle(AppStrings.ContentPublishing.settingsTitle)
                            Text(AppStrings.ContentPublishing.timingTitle)
                                .font(.subheadline.weight(.semibold))
                            Picker(AppStrings.ContentPublishing.timingTitle, selection: $viewModel.publicationMode) {
                                Text(AppStrings.ContentPublishing.publishNow).tag(ContentPublicationMode.now)
                                Text(AppStrings.ContentPublishing.publishLater).tag(ContentPublicationMode.scheduled)
                            }
                            .pickerStyle(.segmented)

                            if viewModel.publicationMode == .scheduled {
                                DatePicker(
                                    AppStrings.ContentPublishing.scheduledDate,
                                    selection: $viewModel.scheduledAt,
                                    in: Date().addingTimeInterval(5 * 60)...,
                                    displayedComponents: [.date, .hourAndMinute]
                                )
                                Text(viewModel.isValidSchedule ? AppStrings.ContentPublishing.scheduleHint : AppStrings.ContentPublishing.invalidSchedule)
                                    .font(.footnote)
                                    .foregroundStyle(viewModel.isValidSchedule ? AppTheme.textSecondary : AppTheme.accentDestructiveForeground)
                            }
                        }
                    }
                }
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
                    .accessibilityIdentifier("editor.event.next")
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
                    EventCard(event: viewModel.previewEvent, previewImage: selectedPreviewImage)
                }
            }
        }

        @ViewBuilder
        var statusContent: some View {
            if let error = organizerOrganizationsViewModel.error, !viewModel.isEditing {
                ErrorStateCard(title: AppStrings.Events.editorTitle, message: readableOrganizationErrorText(error), retryTitle: AppStrings.News.retry) {
                    Task { await organizerOrganizationsViewModel.load(for: authState.user) }
                }
            }
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
                isEnabled: viewModel.canPublish && !isPreparingPlanningPublication,
                isLoading: isPreparingPlanningPublication || viewModel.isPublishing || viewModel.isUploadingImage || viewModel.isProcessingImage
            ) {
                submit()
            }
        }

        func submit() {
            guard !isPreparingPlanningPublication else { return }
            guard hasAuthorizedOrganizerSelection else {
                viewModel.errorMessage = AppStrings.Events.organizationRequired
                currentStep = .basics
                return
            }
            Task {
                isPreparingPlanningPublication = true
                defer { isPreparingPlanningPublication = false }
                let lease: OwnerContentPublicationLease?
                if let planningPublicationCallbacks {
                    lease = await planningPublicationCallbacks.begin()
                    guard lease != nil else {
                        viewModel.errorMessage = AppStrings.ContentPlanning.publicationBeginFailed
                        return
                    }
                } else {
                    lease = nil
                }
                let didPublish = await viewModel.publish(
                    contentID: lease?.contentID,
                    contentAlreadyExists: lease?.contentAlreadyExists ?? false,
                    reservedModerationStatus: lease?.existingModerationStatus,
                    existingScheduledAt: lease?.existingScheduledAt,
                    publicationLeaseID: lease?.leaseID
                )
                guard didPublish else {
                    if let planningPublicationCallbacks, lease != nil {
                        await planningPublicationCallbacks.fail(
                            viewModel.errorMessage ?? AppStrings.ContentPlanning.updateFailed
                        )
                    }
                    return
                }
                guard let result = viewModel.lastPublicationResult else { return }
                guard await onPublished(result) else {
                    viewModel.errorMessage = AppStrings.ContentPlanning.updateFailed
                    return
                }
                await viewModel.completeSuccessfulPublication()
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
