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
                newsCategoryCard
                newsLocalizationCard
            case .content:
                coverImageCard
                newsMediaMetadataCard
                bodyContentCard
            case .preview:
                additionalDetailsCard
                newsExternalActionCard
                newsPublicationSettingsCard
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

        var newsPublicationSettingsCard: some View {
            editorCard {
                VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                    editorSectionTitle(AppStrings.ContentPublishing.settingsTitle)

                    Text(AppStrings.ContentPublishing.reachTitle)
                        .font(.subheadline.weight(.semibold))
                    Picker(AppStrings.ContentPublishing.reachTitle, selection: $viewModel.selectedRegionScope) {
                        Text(AppStrings.ContentPublishing.regionalReach).tag(RegionScope.federalState)
                        Text(AppStrings.ContentPublishing.nationwideReach).tag(RegionScope.austria)
                    }
                    .pickerStyle(.segmented)

                    if viewModel.selectedRegionScope == .austria {
                        Label(
                            viewModel.nationwideRequiresReview
                                ? AppStrings.ContentPublishing.nationwideReviewHint
                                : AppStrings.ContentPublishing.nationwideOwnerHint,
                            systemImage: viewModel.nationwideRequiresReview ? "checkmark.shield" : "map"
                        )
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                    }

                    if !viewModel.isEditing {
                        Divider()
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
                    .accessibilityIdentifier("editor.news.next")
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
                isEnabled: viewModel.canPublish && !isPreparingPlanningPublication,
                isLoading: isPreparingPlanningPublication || viewModel.isPublishing || viewModel.isUploadingImage || viewModel.isProcessingImage
            ) {
                submit()
            }
        }

        func submit() {
            guard !isPreparingPlanningPublication else { return }
            guard hasAuthorizedOrganizerSelection else {
                viewModel.errorMessage = AppStrings.NewsEditor.organizationPermissionRequired
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
                    existingModerationStatus: lease?.existingModerationStatus,
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

        @ViewBuilder
        var statusContent: some View {
            if let error = organizerOrganizationsViewModel.error, !viewModel.isEditing {
                ErrorStateCard(title: AppStrings.Profile.createNews, message: readableOrganizationErrorText(error), retryTitle: AppStrings.News.retry) {
                    Task { await organizerOrganizationsViewModel.load(for: authState.user) }
                }
            }
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
                    Label {
                        Text(errorMessage)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.accentDestructiveForeground)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
