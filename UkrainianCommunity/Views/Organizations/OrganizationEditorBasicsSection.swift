import SwiftUI

extension OrganizationEditorView {
    var mainInfoCard: some View {
        editorCard {
            VStack(alignment: .leading, spacing: editorCardSpacing) {
                editorSectionTitle(AppStrings.Organizations.detailsSectionTitle)

                profileKindPicker

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
                            .frame(width: uploadMinHeight * 1.35)
                        nameField
                        descriptionField
                    }
                }

                categoryPicker
                secondaryCategoryPicker
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

            OrganizationEditorChoiceGrid {
                ForEach(OrganizationEditorCategory.allCases) { category in
                    Button {
                        viewModel.organizationType = category.rawValue
                    } label: {
                        OrganizationEditorChoiceTile(
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

    var profileKindPicker: some View {
        VStack(alignment: .leading, spacing: editorCardSpacing) {
            editorSectionTitle(AppStrings.Organizations.profileKindTitle)

            OrganizationEditorChoiceGrid {
                ForEach(OrganizationProfileKind.allCases) { kind in
                    Button {
                        viewModel.profileKind = kind
                    } label: {
                        OrganizationEditorChoiceTile(
                            title: kind.title,
                            systemImage: kind.systemImage,
                            isSelected: viewModel.profileKind == kind
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    var secondaryCategoryPicker: some View {
        VStack(alignment: .leading, spacing: editorCardSpacing) {
            editorSectionTitle(AppStrings.Organizations.secondaryCategoriesTitle)

            OrganizationEditorChoiceGrid {
                ForEach(OrganizationEditorCategory.allCases.filter { $0.rawValue != viewModel.organizationType }) { category in
                    Button {
                        viewModel.toggleSecondaryCategory(category)
                    } label: {
                        OrganizationEditorChoiceTile(
                            title: category.title,
                            systemImage: category.systemImage,
                            isSelected: viewModel.secondaryCategories.contains(category.rawValue)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(
                        !viewModel.secondaryCategories.contains(category.rawValue)
                            && viewModel.secondaryCategories.count >= OrganizationDirectoryProfile.maximumSecondaryCategoryCount
                    )
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
                    AppAdaptiveGrid(
                        minimumWidth: 240,
                        maximumWidth: 360,
                        spacing: AppTheme.eventsMetadataSpacing
                    ) {
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

private struct OrganizationEditorChoiceGrid<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 138, maximum: 260), spacing: 8)],
            alignment: .leading,
            spacing: 8
        ) {
            content
        }
    }
}

private struct OrganizationEditorChoiceTile: View {
    let title: String
    let systemImage: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(width: 20)

            Text(title)
                .font(.footnote.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .foregroundStyle(isSelected ? Color.white : AppTheme.textPrimary)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(isSelected ? AppTheme.accentPrimary : AppTheme.surfaceControl)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(
                    isSelected ? AppTheme.accentPrimary.opacity(0.2) : AppTheme.borderSubtle,
                    lineWidth: 1
                )
        }
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
