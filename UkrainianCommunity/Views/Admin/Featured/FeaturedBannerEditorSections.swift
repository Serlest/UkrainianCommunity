import SwiftUI
import UIKit

struct FeaturedBannerEditorPreviewSection: View {
    @ObservedObject var viewModel: FeaturedBannerEditorViewModel
    let previewImage: UIImage?

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                AppEditorSectionTitle(title: AppStrings.FeaturedEditor.previewSection)
                FeaturedBannerCardView(banner: viewModel.previewBanner, previewImage: previewImage)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                Text(AppStrings.FeaturedEditor.previewHelper)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct FeaturedBannerEditorBasicsSection: View {
    @ObservedObject var viewModel: FeaturedBannerEditorViewModel

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                AppEditorSectionTitle(title: AppStrings.FeaturedEditor.basicsSection)
                EditorTextField(
                    AppStrings.FeaturedEditor.internalNameField,
                    text: $viewModel.internalName,
                    systemImage: "tag",
                    counterText: "\(viewModel.internalName.count)/\(FeaturedBannerValidationService.internalNameMaxLength)"
                )

                Label(PublishedContentLanguage.ukrainian.title, systemImage: "globe.europe.africa")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                EditorTextField(
                    AppStrings.FeaturedEditor.titleField,
                    text: $viewModel.title,
                    systemImage: "textformat",
                    counterText: "\(viewModel.title.count)/\(FeaturedBannerValidationService.titleMaxLength)"
                )
                EditorTextArea(
                    AppStrings.FeaturedEditor.subtitleField,
                    text: $viewModel.subtitle,
                    counterText: "\(viewModel.subtitle.count)/\(FeaturedBannerValidationService.subtitleMaxLength)"
                )

                DisclosureGroup {
                    VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                        Text(ContentPublishingStrings.germanFallbackHint)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        EditorTextField(
                            AppStrings.FeaturedEditor.titleField,
                            text: $viewModel.germanTitle,
                            systemImage: "textformat",
                            counterText: "\(viewModel.germanTitle.count)/\(FeaturedBannerValidationService.titleMaxLength)"
                        )
                        EditorTextArea(
                            AppStrings.FeaturedEditor.subtitleField,
                            text: $viewModel.germanSubtitle,
                            counterText: "\(viewModel.germanSubtitle.count)/\(FeaturedBannerValidationService.subtitleMaxLength)"
                        )
                    }
                    .padding(.top, AppTheme.dashboardSpacing)
                } label: {
                    Label(ContentPublishingStrings.germanOptional, systemImage: "character.book.closed")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                }

                Toggle(isOn: $viewModel.isActive) {
                    Text(AppStrings.FeaturedManagement.activeToggle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                }
            }
        }
    }
}

struct FeaturedBannerEditorTargetingSection: View {
    @ObservedObject var viewModel: FeaturedBannerEditorViewModel

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                AppEditorSectionTitle(title: AppStrings.FeaturedEditor.targetingSection)

                Picker(AppStrings.FeaturedEditor.regionScopeField, selection: $viewModel.regionScope) {
                    ForEach(FeaturedBannerRegionScope.allCases) { scope in
                        Text(scope.editorTitle).tag(scope)
                    }
                }
                .pickerStyle(.segmented)

                if viewModel.regionScope == .federalState {
                    Picker(AppStrings.FeaturedEditor.federalStateField, selection: $viewModel.federalState) {
                        Text(AppStrings.FeaturedEditor.selectFederalState).tag(Optional<AustrianFederalState>.none)
                        ForEach(AustrianFederalState.allCases) { federalState in
                            Text(AppStrings.FederalStates.title(for: federalState)).tag(Optional(federalState))
                        }
                    }
                    .pickerStyle(.menu)
                }

                VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                    Text(AppStrings.FeaturedEditor.visibleSectionsField)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    ForEach(FeaturedBannerVisibleSection.supportedCases) { section in
                        Toggle(isOn: Binding(
                            get: { viewModel.visibleSections.contains(section) },
                            set: { viewModel.toggleVisibleSection(section, isVisible: $0) }
                        )) {
                            Text(section.editorTitle)
                                .font(.subheadline)
                        }
                    }
                }
            }
        }
    }
}

struct FeaturedBannerEditorActionSection: View {
    @ObservedObject var viewModel: FeaturedBannerEditorViewModel
    let onSelectTarget: () -> Void

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                AppEditorSectionTitle(title: AppStrings.FeaturedEditor.actionSection)

                Picker(AppStrings.FeaturedEditor.actionTypeField, selection: $viewModel.actionType) {
                    ForEach(FeaturedBannerActionType.supportedCases) { actionType in
                        Text(actionType.editorTitle).tag(actionType)
                    }
                }
                .pickerStyle(.menu)

                Text(viewModel.actionType.editorHelperText)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if viewModel.requiresActionTarget {
                    FeaturedBannerActionTargetSelectionField(
                        kind: viewModel.actionTargetPickerKind,
                        selectedItem: viewModel.selectedActionTargetItem,
                        targetID: viewModel.actionTargetID,
                        isLoading: viewModel.isLoadingCurrentActionTargets,
                        onSelect: onSelectTarget,
                        onClear: { viewModel.actionTargetID = "" }
                    )
                    .task { await viewModel.loadActionTargetsIfNeeded() }
                }

                if viewModel.requiresExternalURL {
                    EditorTextField(
                        AppStrings.FeaturedEditor.externalURLField,
                        text: $viewModel.externalURL,
                        systemImage: "link",
                        keyboardType: .URL,
                        autocapitalization: .never,
                        autocorrectionDisabled: true
                    )
                }
            }
        }
    }
}

struct FeaturedBannerEditorSchedulingSection: View {
    @ObservedObject var viewModel: FeaturedBannerEditorViewModel

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                AppEditorSectionTitle(title: AppStrings.FeaturedEditor.schedulingSection)

                Stepper(value: $viewModel.displayDurationSeconds, in: FeaturedBannerValidationService.displayDurationBounds) {
                    FeaturedEditorValueRow(
                        title: AppStrings.FeaturedEditor.durationField,
                        value: AppStrings.FeaturedEditor.durationValue(viewModel.displayDurationSeconds),
                        systemImage: "timer"
                    )
                }

                Stepper(value: $viewModel.priority, in: FeaturedBannerValidationService.priorityBounds) {
                    FeaturedEditorValueRow(
                        title: AppStrings.FeaturedEditor.priorityField,
                        value: "\(viewModel.priority)",
                        systemImage: "list.number"
                    )
                }

                Toggle(AppStrings.FeaturedEditor.startsAtEnabled, isOn: $viewModel.hasStartDate)
                    .font(.subheadline.weight(.semibold))
                if viewModel.hasStartDate {
                    DatePicker(AppStrings.FeaturedEditor.startsAtField, selection: $viewModel.startsAt)
                        .datePickerStyle(.compact)
                }

                Toggle(AppStrings.FeaturedEditor.endsAtEnabled, isOn: $viewModel.hasEndDate)
                    .font(.subheadline.weight(.semibold))
                if viewModel.hasEndDate {
                    DatePicker(AppStrings.FeaturedEditor.endsAtField, selection: $viewModel.endsAt)
                        .datePickerStyle(.compact)
                }
            }
        }
    }
}
