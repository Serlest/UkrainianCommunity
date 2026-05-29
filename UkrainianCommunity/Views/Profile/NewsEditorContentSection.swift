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
                                    .foregroundStyle(AppTheme.textSecondary.opacity(0.72))
                                    .lineSpacing(2)
                                    .padding(.horizontal, AppTheme.eventsControlGroupSpacing)
                                    .padding(.top, AppTheme.dashboardSpacing)
                            }

                            TextEditor(text: $viewModel.body)
                                .scrollContentBackground(.hidden)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.textPrimary)
                                .frame(minHeight: bodyInputHeight)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 4)
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

        var sourceCard: some View {
            editorCard {
                VStack(alignment: .leading, spacing: editorCardSpacing) {
                    editorSectionTitle(AppStrings.NewsEditor.sourceSectionTitle)

                    TextField(AppStrings.NewsEditor.sourcePlaceholder, text: $viewModel.sourceInput)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .newsEditorCompactInputStyle(minHeight: compactInputHeight)

                    Text(AppStrings.NewsEditor.sourceHelper)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineSpacing(2)
                }
            }
        }

        var tagsCard: some View {
            editorCard {
                VStack(alignment: .leading, spacing: editorCardSpacing) {
                    editorSectionTitle(AppStrings.NewsEditor.tagsSectionTitle)

                    TextField(AppStrings.NewsEditor.tagsPlaceholder, text: $viewModel.tagsInput)
                        .newsEditorCompactInputStyle(minHeight: compactInputHeight)

                    Text(AppStrings.NewsEditor.tagsHelper)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineSpacing(2)
                }
            }
        }

        var settingsCard: some View {
            editorCard {
                VStack(alignment: .leading, spacing: editorCardSpacing) {
                    editorSectionTitle(AppStrings.NewsEditor.regionSectionTitle)

                    Menu {
                        ForEach(AustrianFederalState.allCases) { federalState in
                        Button(federalState.newsEditorDisplayName) {
                                viewModel.selectedFederalState = federalState
                            }
                        }
                    } label: {
                        settingsRows {
                            detailRow(
                                systemImage: "map",
                                title: AppStrings.NewsEditor.regionSectionTitle,
                            value: viewModel.selectedFederalState.newsEditorDisplayName,
                                showsChevron: true
                            )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
}
