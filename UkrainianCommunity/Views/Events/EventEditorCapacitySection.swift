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
                    if viewModel.participationMode.requiresExternalURL {
                        editorDivider
                        externalParticipationRows
                    }
                    if viewModel.participationMode != .none {
                        editorDivider
                        priceRow
                    }
                    if viewModel.requiresRegistration {
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
            Menu {
                ForEach(EventParticipationMode.allCases) { mode in
                    Button {
                        viewModel.participationMode = mode
                    } label: {
                        if viewModel.participationMode == mode {
                            Label(mode.localizedTitle, systemImage: "checkmark")
                        } else {
                            Text(mode.localizedTitle)
                        }
                    }
                }
            } label: {
                settingsRow(
                    systemImage: "checklist",
                    title: ContentPublishingStrings.participation,
                    value: viewModel.participationMode.localizedTitle,
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
        }

        var externalParticipationRows: some View {
            VStack(alignment: .leading, spacing: 8) {
                editorField(title: ContentPublishingStrings.linkButtonTitle, counterText: "\(viewModel.externalActionTitle.count)/\(EventEditorViewModel.externalActionTitleLimit)") {
                    TextField(ContentPublishingStrings.linkButtonTitle, text: $viewModel.externalActionTitle)
                        .eventEditorCompactInputStyle(minHeight: compactInputHeight)
                }
                editorField(title: "URL", counterText: "\(viewModel.externalActionURL.count)/\(EventEditorViewModel.externalActionURLLimit)") {
                    TextField("https://", text: $viewModel.externalActionURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .eventEditorCompactInputStyle(minHeight: compactInputHeight)
                }
                if !viewModel.isValidExternalParticipation {
                    Text(ContentPublishingStrings.secureWebLinkRequired)
                        .font(.caption)
                        .foregroundStyle(AppTheme.accentDestructiveForeground)
                }
            }
        }

        var priceRow: some View {
            VStack(alignment: .leading, spacing: 4) {
                Menu {
                    ForEach(EventPriceKind.allCases) { kind in
                        Button(kind.localizedTitle) {
                            viewModel.priceKind = kind
                        }
                    }
                } label: {
                    settingsRow(
                        systemImage: "eurosign.circle",
                        title: ContentPublishingStrings.priceType,
                        value: viewModel.priceKind.localizedTitle,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)

                if [.exact, .startingFrom, .range].contains(viewModel.priceKind) {
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
                }

                if viewModel.priceKind == .range {
                    TextField(ContentPublishingStrings.maximumPrice, text: $viewModel.maximumPriceText)
                        .keyboardType(.decimalPad)
                        .eventEditorCompactInputStyle(minHeight: compactInputHeight)
                }

                editorField(title: ContentPublishingStrings.priceNote, counterText: "\(viewModel.priceNote.count)/\(EventEditorViewModel.priceNoteLimit)") {
                    TextField(ContentPublishingStrings.priceNote, text: $viewModel.priceNote)
                        .eventEditorCompactInputStyle(minHeight: compactInputHeight)
                }

                Text(ContentPublishingStrings.informationOnly)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
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
                    .foregroundStyle(AppTheme.accentPrimaryForeground)
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
