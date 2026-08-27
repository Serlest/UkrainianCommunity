import SwiftUI

extension EventEditorView {
        var mainCard: some View {
            editorCard {
                VStack(alignment: .leading, spacing: editorCardSpacing) {
                    editorField(title: AppStrings.Events.fieldTitle, counterText: "\(viewModel.title.count)/120") {
                        TextField(AppStrings.Events.titlePlaceholder, text: $viewModel.title)
                            .font(.subheadline)
                            .textInputAutocapitalization(.sentences)
                            .eventEditorCompactInputStyle(minHeight: compactInputHeight)
                            .accessibilityIdentifier("editor.event.title")
                    }

                    editorField(title: AppStrings.Events.fieldSummary) {
                        multilineInput(
                            placeholder: AppStrings.Events.summaryPlaceholder,
                            text: $viewModel.summary,
                            minHeight: summaryInputHeight,
                            counterText: "\(viewModel.summary.count)/200"
                        )
                        .accessibilityIdentifier("editor.event.summary")
                    }

                    editorField(title: AppStrings.Events.fieldDetails) {
                        multilineInput(
                            placeholder: AppStrings.Events.detailsPlaceholder,
                            text: $viewModel.details,
                            minHeight: detailsInputHeight,
                            counterText: "\(viewModel.details.count)/2000"
                        )
                        .accessibilityIdentifier("editor.event.details")
                    }
                }
            }
        }

        var categoryCard: some View {
            editorCard {
                VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                    editorSectionTitle(AppStrings.Events.categorySectionTitle)

                    AppHorizontalFilterRow {
                        ForEach(EventCategory.allCases) { category in
                            EventEditorCategoryChip(category: category, isSelected: viewModel.selectedCategory == category) {
                                viewModel.selectedCategory = category
                            }
                        }
                    }

                    editorDivider

                    editorSectionTitle(AppStrings.Events.additionalCategoriesTitle)

                    AppHorizontalFilterRow {
                        ForEach(EventCategory.allCases) { category in
                            EventEditorCategoryChip(
                                category: category,
                                isSelected: viewModel.additionalCategories.contains(category)
                            ) {
                                viewModel.toggleAdditionalCategory(category)
                            }
                            .disabled(viewModel.isAdditionalCategoryDisabled(category))
                            .opacity(viewModel.isAdditionalCategoryDisabled(category) && !viewModel.additionalCategories.contains(category) ? 0.45 : 1)
                        }
                    }

                    Text(AppStrings.Events.additionalCategoriesHelper)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineSpacing(2)
                }
            }
        }

        var tagsCard: some View {
            editorCard {
                VStack(alignment: .leading, spacing: editorCardSpacing) {
                    editorSectionTitle(AppStrings.Events.tagsSectionTitle)

                    HStack(spacing: AppTheme.eventsMetadataSpacing) {
                        TextField(AppStrings.Events.tagPlaceholder, text: $viewModel.tagInput)
                            .font(.subheadline)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            .eventEditorCompactInputStyle(minHeight: compactInputHeight)
                            .onSubmit {
                                viewModel.addTagFromInput()
                            }

                        Button {
                            viewModel.addTagFromInput()
                        } label: {
                            Image(systemName: "plus")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: AppTheme.iconButtonSize, height: AppTheme.iconButtonSize)
                                .background(AppTheme.accentPrimary, in: RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(AppStrings.Events.addTag)
                    }

                    if !viewModel.tags.isEmpty {
                        AppHorizontalChipRow(spacing: 8) {
                            ForEach(viewModel.tags, id: \.self) { tag in
                                Button {
                                    viewModel.removeTag(tag)
                                } label: {
                                    AppInfoChip(
                                        title: tag,
                                        systemImage: "tag",
                                        trailingSystemImage: "xmark",
                                        size: .small
                                    )
                                }
                                .buttonStyle(.plain)
                                .frame(minHeight: AppTheme.minimumInteractiveTarget)
                                .contentShape(Rectangle())
                                .accessibilityLabel("\(AppStrings.Events.removeTag): \(tag)")
                            }
                        }
                    }

                    Text(AppStrings.Events.tagsHelper)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineSpacing(2)
                }
            }
        }

        var audienceCard: some View {
            editorCard {
                VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                    editorSectionTitle(AppStrings.Events.audienceSectionTitle)

                    AppHorizontalFilterRow {
                        ForEach(EventAudience.allCases) { audience in
                            EventEditorAudienceChip(
                                audience: audience,
                                isSelected: viewModel.selectedAudience == audience
                            ) {
                                viewModel.selectedAudience = audience
                            }
                        }
                    }

                    editorDivider

                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppStrings.Events.ageRestrictionTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: AppTheme.dashboardSpacing) {
                                ageField(title: AppStrings.Events.minimumAge, text: $viewModel.minimumAgeText)
                                ageField(title: AppStrings.Events.maximumAge, text: $viewModel.maximumAgeText)
                            }

                            VStack(spacing: AppTheme.dashboardSpacing) {
                                ageField(title: AppStrings.Events.minimumAge, text: $viewModel.minimumAgeText)
                                ageField(title: AppStrings.Events.maximumAge, text: $viewModel.maximumAgeText)
                            }
                        }

                        Text(AppStrings.Events.noAgeRestriction)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
            }
        }

        func ageField(title: String, text: Binding<String>) -> some View {
            HStack(spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                TextField("—", text: text)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(AppStrings.Events.ageYearsShort)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: AppTheme.minimumInteractiveTarget)
            .background(AppTheme.surfaceControl, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(AppTheme.borderSubtle))
            .accessibilityElement(children: .combine)
        }

        var organizerContactCard: some View {
            editorCard {
                VStack(alignment: .leading, spacing: editorCardSpacing) {
                    editorSectionTitle(AppStrings.Events.organizerContactSectionTitle)

                    editorField(title: AppStrings.Events.organizerNameField) {
                        TextField(AppStrings.Events.organizerNamePlaceholder, text: $viewModel.eventOrganizerName)
                            .font(.subheadline)
                            .textInputAutocapitalization(.words)
                            .eventEditorCompactInputStyle(minHeight: compactInputHeight)
                    }

                    editorField(title: AppStrings.Events.organizerURLField) {
                        TextField(AppStrings.Events.organizerURLPlaceholder, text: $viewModel.organizerURL)
                            .font(.subheadline)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .eventEditorCompactInputStyle(minHeight: compactInputHeight)
                    }

                    editorField(title: AppStrings.Events.contactPhoneField) {
                        TextField(AppStrings.Events.contactPhonePlaceholder, text: $viewModel.contactPhone)
                            .font(.subheadline)
                            .keyboardType(.phonePad)
                            .eventEditorCompactInputStyle(minHeight: compactInputHeight)
                    }

                    editorField(title: AppStrings.Events.contactEmailField) {
                        TextField(AppStrings.Events.contactEmailPlaceholder, text: $viewModel.contactEmail)
                            .font(.subheadline)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .eventEditorCompactInputStyle(minHeight: compactInputHeight)
                    }

                    editorField(title: AppStrings.Events.contactURLField) {
                        TextField(AppStrings.Events.contactURLPlaceholder, text: $viewModel.contactURL)
                            .font(.subheadline)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .eventEditorCompactInputStyle(minHeight: compactInputHeight)
                    }

                    Text(AppStrings.Events.organizerContactHelper)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineSpacing(2)
                }
            }
        }

    struct EventEditorCategoryChip: View {
        let category: EventCategory
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Label(category.title, systemImage: category.systemImage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(isSelected ? AppTheme.accentPrimaryForeground : AppTheme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        (isSelected ? AppTheme.accentPrimarySoft : AppTheme.surfaceGlass),
                        in: Capsule(style: .continuous)
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(isSelected ? AppTheme.accentPrimary.opacity(0.12) : AppTheme.borderSubtle)
                    )
            }
            .buttonStyle(.plain)
            .frame(minHeight: AppTheme.minimumInteractiveTarget)
            .contentShape(Rectangle())
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }

    struct EventEditorAudienceChip: View {
        let audience: EventAudience
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Label(audience.title, systemImage: audience.systemImage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(isSelected ? AppTheme.accentPrimaryForeground : AppTheme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(isSelected ? AppTheme.accentPrimarySoft : AppTheme.surfaceGlass, in: Capsule())
                    .overlay(Capsule().strokeBorder(isSelected ? AppTheme.accentPrimary.opacity(0.12) : AppTheme.borderSubtle))
            }
            .buttonStyle(.plain)
            .frame(minHeight: AppTheme.minimumInteractiveTarget)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }
}
