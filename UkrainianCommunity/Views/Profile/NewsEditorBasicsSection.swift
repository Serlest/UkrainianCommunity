import SwiftUI

extension NewsEditorView {
        var mainInformationCard: some View {
            editorCard {
                VStack(alignment: .leading, spacing: editorCardSpacing) {
                    editorField(
                        title: AppStrings.NewsEditor.titleFieldRequired,
                        counterText: counterText(viewModel.title.count, limit: titleLimit)
                    ) {
                        TextField(AppStrings.NewsEditor.titlePlaceholder, text: $viewModel.title)
                            .font(.subheadline)
                            .textInputAutocapitalization(.sentences)
                            .submitLabel(.next)
                            .focused($focusedField, equals: .title)
                            .onSubmit { focusedField = .summary }
                            .newsEditorCompactInputStyle(minHeight: compactInputHeight)
                            .accessibilityIdentifier("editor.news.title")
                    }

                    editorField(
                        title: AppStrings.NewsEditor.summaryFieldRequired,
                        counterText: counterText(viewModel.summary.count, limit: summaryLimit)
                    ) {
                        ZStack(alignment: .topLeading) {
                            if viewModel.summary.isEmpty {
                                Text(AppStrings.NewsEditor.summaryPlaceholder)
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .lineSpacing(2)
                                    .padding(.horizontal, AppTheme.eventsControlGroupSpacing)
                                    .padding(.vertical, AppTheme.eventsMetadataSpacing)
                            }

                            TextEditor(text: $viewModel.summary)
                                .scrollContentBackground(.hidden)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.textPrimary)
                                .focused($focusedField, equals: .summary)
                                .frame(minHeight: summaryTextHeight)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .accessibilityIdentifier("editor.news.summary")
                        }
                        .newsEditorCompactInputStyle(minHeight: summaryInputHeight)
                    }
                }
            }
        }

        var newsCategoryCard: some View {
            editorCard {
                VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                    editorSectionTitle(AppStrings.NewsEditor.categorySectionTitle)

                    AppHorizontalFilterRow {
                        ForEach(NewsCategory.allCases) { category in
                            NewsEditorCategoryChip(
                                category: category,
                                isSelected: viewModel.selectedCategory == category
                            ) {
                                viewModel.selectedCategory = category
                            }
                        }
                    }

                    Divider()
                    editorSectionTitle(AppStrings.NewsEditor.additionalCategoriesTitle)

                    AppHorizontalFilterRow {
                        ForEach(NewsCategory.allCases) { category in
                            NewsEditorCategoryChip(
                                category: category,
                                isSelected: viewModel.additionalCategories.contains(category)
                            ) {
                                viewModel.toggleAdditionalCategory(category)
                            }
                            .disabled(viewModel.isAdditionalCategoryDisabled(category))
                            .opacity(viewModel.isAdditionalCategoryDisabled(category) && !viewModel.additionalCategories.contains(category) ? 0.45 : 1)
                        }
                    }

                    Text(AppStrings.NewsEditor.additionalCategoriesHelper)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineSpacing(2)
                }
            }
        }

        var noOrganizerAccessCard: some View {
            EmptyStateCard(
                systemImage: "building.2.crop.circle",
                title: AppStrings.NewsEditor.addTitle,
                message: AppStrings.NewsEditor.noOrganizerAccess
            )
        }

        var organizerCard: some View {
            editorCard {
                VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                    editorSectionTitle(AppStrings.NewsEditor.organizerSectionTitle)

                    Button {
                        guard canSelectOrganizer else { return }
                        isShowingOrganizerPicker = true
                    } label: {
                        HStack(spacing: AppTheme.dashboardSpacing) {
                            AppFeedThumbnail(
                                imageURL: viewModel.organizerImageURL,
                                fallbackSystemImage: "building.2",
                                tint: AppTheme.accentPrimaryForeground,
                                fill: AppTheme.accentPrimarySoft,
                                size: organizerLogoSize,
                                cornerRadius: AppTheme.feedThumbnailRadius,
                                source: "NewsEditorOrganizer"
                            )

                            VStack(alignment: .leading, spacing: 4) {
                                Text(viewModel.organizerName ?? organizerPlaceholderTitle)
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(AppTheme.textPrimary)
                                    .lineLimit(2)

                                AppInfoChip(
                                    title: organizerStatusTitle,
                                    systemImage: "building.2",
                                    tint: AppTheme.accentPrimaryForeground,
                                    fill: AppTheme.accentPrimarySoft,
                                    size: .small
                                )
                            }

                            Spacer(minLength: AppTheme.eventsMetadataSpacing)

                            organizerAccessory
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSelectOrganizer)
                    .frame(minHeight: 52)
                    .contentShape(Rectangle())
                    .accessibilityHint(canSelectOrganizer ? AppStrings.NewsEditor.organizerPickerHint : "")
                    .accessibilityIdentifier("editor.news.organizer")
                }
            }
        }

        var organizerPlaceholderTitle: String {
            if organizerOrganizationsViewModel.isLoading {
                return AppStrings.Profile.loadingUserProfile
            }

            return AppStrings.NewsEditor.selectOrganizer
        }

        var organizerStatusTitle: String {
            if viewModel.organizerName != nil {
                return AppStrings.Organizations.detailBadge
            }

            if availableOrganizerOrganizations.isEmpty {
                return AppStrings.Common.notAvailable
            }

            return AppStrings.NewsEditor.selectOrganizer
        }

        @ViewBuilder
        var organizerAccessory: some View {
            if canSelectOrganizer {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accentPrimaryForeground)
                    .frame(width: 32, height: 32)
                    .background(AppTheme.glassControlSurface(for: colorScheme), in: Circle())
            } else if organizerOrganizationsViewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(AppTheme.accentPrimary)
                    .frame(width: 32, height: 32)
                    .background(AppTheme.glassControlSurface(for: colorScheme), in: Circle())
            } else {
                Label(AppStrings.Common.notAvailable, systemImage: "lock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .labelStyle(.iconOnly)
                    .frame(width: 32, height: 32)
                    .background(AppTheme.glassControlSurface(for: colorScheme), in: Circle())
            }
        }
}

private struct NewsEditorCategoryChip: View {
    let category: NewsCategory
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
                .background(isSelected ? AppTheme.accentPrimarySoft : AppTheme.surfaceGlass, in: Capsule())
                .overlay(Capsule().strokeBorder(isSelected ? AppTheme.accentPrimary.opacity(0.12) : AppTheme.borderSubtle))
        }
        .buttonStyle(.plain)
        .frame(minHeight: AppTheme.minimumInteractiveTarget)
        .contentShape(Rectangle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
