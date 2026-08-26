import SwiftUI

extension NewsEditorView {
        var bodyContentCard: some View {
            editorCard {
                VStack(alignment: .leading, spacing: editorCardSpacing) {
                    editorSectionTitle(AppStrings.NewsEditor.bodySectionTitle)

                    VStack(spacing: 0) {
                        ZStack(alignment: .topLeading) {
                            if viewModel.body.isEmpty {
                                Text(AppStrings.NewsEditor.bodyPlaceholder)
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .lineSpacing(2)
                                    .padding(.horizontal, AppTheme.eventsControlGroupSpacing)
                                    .padding(.top, AppTheme.dashboardSpacing)
                            }

                            TextEditor(text: $viewModel.body)
                                .scrollContentBackground(.hidden)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.textPrimary)
                                .focused($focusedField, equals: .body)
                                .frame(minHeight: bodyInputHeight)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 4)
                                .accessibilityIdentifier("editor.news.body")
                        }

                        HStack {
                            Spacer(minLength: 0)
                            Text(counterText(viewModel.body.count, limit: bodyLimit))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(AppTheme.textSecondary)
                                .padding(.trailing, AppTheme.eventsControlGroupSpacing)
                                .padding(.bottom, AppTheme.eventsMetadataSpacing)
                        }
                    }
                    .background(AppTheme.glassControlSurface(for: colorScheme), in: RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.imageRadius, style: .continuous)
                            .strokeBorder(AppTheme.glassBorder(for: colorScheme).opacity(0.82))
                    )
                }
            }
        }

        var additionalDetailsCard: some View {
            editorCard {
                VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                    editorSectionTitle(AppStrings.NewsEditor.additionalDetailsTitle)

                    VStack(alignment: .leading, spacing: editorCardSpacing) {
                    editorSectionTitle(AppStrings.NewsEditor.sourceSectionTitle)

                    TextField(AppStrings.NewsEditor.sourcePlaceholder, text: $viewModel.sourceInput)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focusedField, equals: .source)
                        .onSubmit { focusedField = .tags }
                        .newsEditorCompactInputStyle(minHeight: compactInputHeight)

                    Text(AppStrings.NewsEditor.sourceHelper)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineSpacing(2)
                    }

                    Divider().overlay(AppTheme.borderSubtle)

                    VStack(alignment: .leading, spacing: editorCardSpacing) {
                    editorSectionTitle(AppStrings.NewsEditor.tagsSectionTitle)

                    TextField(AppStrings.NewsEditor.tagsPlaceholder, text: $viewModel.tagsInput)
                        .submitLabel(.done)
                        .focused($focusedField, equals: .tags)
                        .onSubmit { focusedField = nil }
                        .newsEditorCompactInputStyle(minHeight: compactInputHeight)

                    Text(AppStrings.NewsEditor.tagsHelper)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineSpacing(2)
                    }
                }
            }
        }

        var newsPreviewCard: some View {
            editorCard {
                VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                    editorSectionTitle(AppStrings.NewsEditor.previewTitle)
                    NewsCard(post: viewModel.previewPost, previewImage: selectedPreviewImage)
                }
            }
        }

        var publicationNoticeCard: some View {
            editorCard {
                HStack(alignment: .top, spacing: AppTheme.eventsMetadataSpacing) {
                    Image(systemName: "info.circle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.accentPrimaryForeground)
                        .frame(width: AppTheme.metadataIconSize, height: AppTheme.metadataIconSize)

                    Text(AppStrings.NewsEditor.publicationNotice)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineSpacing(3)
                }
            }
        }

        var settingsCard: some View {
            editorCard {
                VStack(alignment: .leading, spacing: editorCardSpacing) {
                    editorSectionTitle(AppStrings.NewsEditor.regionSectionTitle)

                    Menu {
                        ForEach(AustrianFederalState.allCases) { federalState in
                            Button(federalState.displayName) {
                                viewModel.selectedFederalState = federalState
                            }
                        }
                    } label: {
                        settingsRows {
                            detailRow(
                                systemImage: "map",
                                title: AppStrings.NewsEditor.regionSectionTitle,
                                value: viewModel.selectedFederalState.displayName,
                                showsChevron: true
                            )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
}
