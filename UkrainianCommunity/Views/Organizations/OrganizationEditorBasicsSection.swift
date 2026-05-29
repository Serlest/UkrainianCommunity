import SwiftUI

extension OrganizationEditorView {
    var mainInfoCard: some View {
        editorCard {
            VStack(alignment: .leading, spacing: editorCardSpacing) {
                editorSectionTitle(AppStrings.Organizations.detailsSectionTitle)

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: AppTheme.dashboardSpacing) {
                        logoPicker
                            .frame(width: uploadMinHeight)

                        VStack(alignment: .leading, spacing: editorCardSpacing) {
                            nameField
                            descriptionField
                        }
                    }

                    VStack(alignment: .leading, spacing: editorCardSpacing) {
                        logoPicker
                        nameField
                        descriptionField
                    }
                }

                categoryPicker
            }
        }
    }

    var nameField: some View {
        editorField(title: AppStrings.Organizations.fieldName, counterText: "\(viewModel.name.count)/100") {
            TextField(AppStrings.Organizations.fieldNamePlaceholder, text: $viewModel.name)
                .font(.subheadline)
                .textInputAutocapitalization(.words)
                .organizationEditorCompactInputStyle(minHeight: compactInputHeight)
                .accessibilityLabel(AppStrings.Organizations.fieldName)
        }
    }

    var descriptionField: some View {
        editorField(title: AppStrings.Organizations.fieldDescription, counterText: "\(viewModel.shortDescription.count)/\(OrganizationEditorViewModel.shortDescriptionLimit)") {
            TextField(AppStrings.Organizations.fieldDescriptionPlaceholder, text: $viewModel.shortDescription, axis: .vertical)
                .lineLimit(3...6)
                .font(.subheadline)
                .textInputAutocapitalization(.sentences)
                .organizationEditorCompactInputStyle(minHeight: summaryInputHeight)
                .accessibilityLabel(AppStrings.Organizations.fieldDescription)
        }
    }

    var categoryPicker: some View {
        VStack(alignment: .leading, spacing: editorCardSpacing) {
            editorSectionTitle(AppStrings.Organizations.categorySectionTitle)

            AppHorizontalFilterRow {
                ForEach(OrganizationEditorCategory.allCases) { category in
                    Button {
                        viewModel.organizationType = category.rawValue
                    } label: {
                        AppFilterChip(
                            title: category.title,
                            systemImage: category.systemImage,
                            isSelected: viewModel.organizationType == category.rawValue
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    var aboutCard: some View {
        editorCard {
            VStack(alignment: .leading, spacing: editorCardSpacing) {
                editorSectionTitle(AppStrings.Organizations.aboutSectionTitle)

                TextField(AppStrings.Organizations.fieldMissionStatementPlaceholder, text: $viewModel.missionStatement, axis: .vertical)
                    .lineLimit(2...4)
                    .font(.subheadline)
                    .textInputAutocapitalization(.sentences)
                    .organizationEditorCompactInputStyle(minHeight: summaryTextHeight)
                    .accessibilityLabel(AppStrings.Organizations.fieldMissionStatement)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(AppStrings.Organizations.fieldFullDescription)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)

                        Spacer(minLength: AppTheme.eventsMetadataSpacing)

                        Text("\(viewModel.fullDescription.count)/\(OrganizationEditorViewModel.fullDescriptionLimit)")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .monospacedDigit()
                    }

                    TextField(AppStrings.Organizations.fieldFullDescriptionPlaceholder, text: $viewModel.fullDescription, axis: .vertical)
                        .lineLimit(6...12)
                        .font(.subheadline)
                        .textInputAutocapitalization(.sentences)
                        .organizationEditorCompactInputStyle(minHeight: summaryTextHeight)
                        .accessibilityLabel(AppStrings.Organizations.fieldFullDescription)
                }

                VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppTheme.eventsMetadataSpacing) {
                        iconTextField(systemImage: "calendar", placeholder: AppStrings.Organizations.fieldFoundedYear, text: $viewModel.foundedYear)
                            .keyboardType(.numberPad)

                        foundedMonthPicker
                    }

                    iconTextField(systemImage: "globe.europe.africa", placeholder: AppStrings.Organizations.fieldLanguages, text: $viewModel.languages)
                }
            }
        }
    }
}
