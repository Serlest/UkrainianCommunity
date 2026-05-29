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
                    }

                    editorField(title: AppStrings.Events.fieldSummary) {
                        multilineInput(
                            placeholder: AppStrings.Events.summaryPlaceholder,
                            text: $viewModel.summary,
                            minHeight: summaryInputHeight,
                            counterText: "\(viewModel.summary.count)/200"
                        )
                    }

                    editorField(title: AppStrings.Events.fieldDetails) {
                        multilineInput(
                            placeholder: AppStrings.Events.detailsPlaceholder,
                            text: $viewModel.details,
                            minHeight: detailsInputHeight,
                            counterText: "\(viewModel.details.count)/2000"
                        )
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
                    .foregroundStyle(isSelected ? AppTheme.accentPrimary : AppTheme.textSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
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
        }
    }
}
