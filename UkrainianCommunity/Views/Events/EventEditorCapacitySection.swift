import SwiftUI

extension EventEditorView {
        var additionalSettingsCard: some View {
            editorCard {
                VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                    editorSectionTitle(AppStrings.Events.additionalSettingsTitle)
                    if viewModel.showsRegionPicker {
                        regionPickerRow
                        editorDivider
                    }
                    registrationRequirementRow
                    if viewModel.requiresRegistration {
                        editorDivider
                        priceRow
                        editorDivider
                        capacityRow
                    }
                }
            }
        }

        var regionPickerRow: some View {
            Menu {
                ForEach(AustrianFederalState.allCases) { federalState in
                    Button(federalState.displayName) {
                        viewModel.selectedFederalState = federalState
                    }
                }
            } label: {
                settingsRow(
                    systemImage: "map",
                    title: AppStrings.NewsEditor.regionSectionTitle,
                    value: viewModel.selectedFederalState.displayName,
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
        }

        var registrationRequirementRow: some View {
            Toggle(isOn: $viewModel.requiresRegistration) {
                HStack(spacing: AppTheme.dashboardSpacing) {
                    Image(systemName: "checklist")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: AppTheme.metadataIconSize, height: AppTheme.metadataIconSize)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppStrings.Events.requiresRegistrationToggle)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppTheme.textPrimary)

                        Text(AppStrings.Events.requiresRegistrationHelper)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary.opacity(0.78))
                    }
                }
            }
            .toggleStyle(.switch)
        }

        var priceRow: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: AppTheme.dashboardSpacing) {
                    Image(systemName: "eurosign.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: AppTheme.metadataIconSize, height: AppTheme.metadataIconSize)

                    Text(AppStrings.Events.priceTitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.textPrimary)

                    Spacer(minLength: AppTheme.eventsMetadataSpacing)

                    TextField(AppStrings.Events.pricePlaceholder, text: $viewModel.priceText)
                        .keyboardType(.decimalPad)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.textPrimary)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 112)
                }
                .frame(minHeight: 44)

                Text(AppStrings.Events.priceHelper)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.78))
                    .padding(.leading, AppTheme.metadataIconSize + AppTheme.dashboardSpacing)
            }
        }

        var capacityRow: some View {
            HStack(spacing: AppTheme.dashboardSpacing) {
                Image(systemName: "person.2")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: AppTheme.metadataIconSize, height: AppTheme.metadataIconSize)

                Text(AppStrings.Events.maxParticipantsTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.textPrimary)

                Spacer(minLength: AppTheme.eventsMetadataSpacing)

                TextField(AppStrings.Events.unlimitedParticipants, text: $viewModel.capacityText)
                    .keyboardType(.numberPad)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.textPrimary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 112)
            }
            .frame(minHeight: 48)
        }

        var publishNoticeCard: some View {
            HStack(alignment: .top, spacing: AppTheme.eventsMetadataSpacing) {
                Image(systemName: "info.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accentPrimary)
                    .frame(width: AppTheme.metadataIconSize, height: AppTheme.metadataIconSize)

                Text(AppStrings.Events.publishNotice)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineSpacing(3)
            }
            .padding(editorCardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.surfaceGlass, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        }
}
