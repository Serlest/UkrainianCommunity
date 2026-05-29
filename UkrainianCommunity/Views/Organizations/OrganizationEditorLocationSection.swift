import SwiftUI

extension OrganizationEditorView {
    var locationCard: some View {
        editorCard {
            VStack(alignment: .leading, spacing: editorCardSpacing) {
                editorSectionTitle(AppStrings.Organizations.locationSectionTitle)

                Menu {
                    ForEach(AustrianFederalState.allCases) { federalState in
                        Button(AppStrings.FederalStates.title(for: federalState)) {
                            viewModel.selectedFederalState = federalState
                        }
                    }
                } label: {
                    HStack(spacing: AppTheme.eventsMetadataSpacing) {
                        Image(systemName: "map")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                            .frame(width: AppTheme.metadataIconSize, height: AppTheme.metadataIconSize)

                        Text(selectedRegionTitle)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(viewModel.selectedFederalState == nil ? AppTheme.textSecondary : AppTheme.textPrimary)

                        Spacer(minLength: AppTheme.eventsMetadataSpacing)

                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .padding(.horizontal, AppTheme.eventsControlGroupSpacing)
                    .frame(height: compactInputHeight)
                    .background(AppTheme.surfaceControl.opacity(0.36), in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                            .strokeBorder(AppTheme.borderSubtle)
                    )
                }
                .buttonStyle(.plain)

                iconTextField(systemImage: "building.2", placeholder: AppStrings.Organizations.fieldCity, text: $viewModel.city)

                iconTextField(systemImage: "mappin.circle", placeholder: AppStrings.Organizations.fieldAddress, text: $viewModel.address)
            }
        }
    }


    var selectedRegionTitle: String {
        guard let selectedFederalState = viewModel.selectedFederalState else {
            return AppStrings.Organizations.fieldRegionPlaceholder
        }
        return AppStrings.FederalStates.title(for: selectedFederalState)
    }

    var foundedMonthPicker: some View {
        Menu {
            Button(AppStrings.Organizations.fieldFoundedMonthNone) {
                viewModel.foundedMonth = nil
            }

            ForEach(1...12, id: \.self) { month in
                Button(localizedMonthName(for: month)) {
                    viewModel.foundedMonth = month
                }
            }
        } label: {
            HStack(spacing: AppTheme.eventsMetadataSpacing) {
                Image(systemName: "calendar.badge.clock")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: AppTheme.metadataIconSize, height: AppTheme.metadataIconSize)

                Text(selectedFoundedMonthTitle)
                    .font(.subheadline)
                    .foregroundStyle(viewModel.foundedMonth == nil ? AppTheme.textSecondary : AppTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Spacer(minLength: AppTheme.eventsMetadataSpacing)

                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(.horizontal, AppTheme.eventsControlGroupSpacing)
            .frame(minHeight: compactInputHeight, alignment: .leading)
            .background(AppTheme.surfaceControl.opacity(0.36), in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                    .strokeBorder(AppTheme.borderSubtle)
            )
            .opacity(viewModel.canSelectFoundedMonth ? 1 : 0.58)
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canSelectFoundedMonth)
        .accessibilityLabel(AppStrings.Organizations.fieldFoundedMonth)
    }

    var selectedFoundedMonthTitle: String {
        guard viewModel.canSelectFoundedMonth,
              let foundedMonth = viewModel.foundedMonth else {
            return AppStrings.Organizations.fieldFoundedMonthNone
        }
        return localizedMonthName(for: foundedMonth)
    }

    func localizedMonthName(for month: Int) -> String {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = 2024
        components.month = month
        components.day = 1

        guard let date = components.date else {
            return AppStrings.Organizations.fieldFoundedMonthNone
        }

        let formatter = DateFormatter()
        formatter.locale = LocalizationStore.locale
        formatter.setLocalizedDateFormatFromTemplate("LLLL")
        return formatter.string(from: date).capitalized(with: LocalizationStore.locale)
    }
}
