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
                            .newsEditorCompactInputStyle(minHeight: compactInputHeight)
                    }

                    editorField(
                        title: AppStrings.NewsEditor.summaryFieldRequired,
                        counterText: counterText(viewModel.summary.count, limit: summaryLimit)
                    ) {
                        ZStack(alignment: .topLeading) {
                            if viewModel.summary.isEmpty {
                                Text(AppStrings.NewsEditor.summaryPlaceholder)
                                    .font(.subheadline)
                                    .foregroundStyle(AppTheme.textSecondary.opacity(0.72))
                                    .lineSpacing(2)
                                    .padding(.horizontal, AppTheme.eventsControlGroupSpacing)
                                    .padding(.vertical, AppTheme.eventsMetadataSpacing)
                            }

                            TextEditor(text: $viewModel.summary)
                                .scrollContentBackground(.hidden)
                                .font(.subheadline)
                                .foregroundStyle(AppTheme.textPrimary)
                                .frame(minHeight: summaryTextHeight)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                        }
                        .newsEditorCompactInputStyle(minHeight: summaryInputHeight)
                    }
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
                                tint: AppTheme.accentPrimary,
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
                                    tint: AppTheme.accentPrimary,
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
                    .foregroundStyle(AppTheme.accentPrimary)
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
                    .foregroundStyle(AppTheme.textSecondary.opacity(0.7))
                    .labelStyle(.iconOnly)
                    .frame(width: 32, height: 32)
                    .background(AppTheme.glassControlSurface(for: colorScheme), in: Circle())
            }
        }
}
