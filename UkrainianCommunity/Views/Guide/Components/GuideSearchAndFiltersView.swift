import SwiftUI

struct GuideSearchAndFiltersView: View {
    @ObservedObject var viewModel: GuideListViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
            filterFeedback
            filterRow
        }
    }

    private var filterRow: some View {
        AppHorizontalFilterRow {
            contentTypeFilter
            regionFilter
            audienceFilter
            clearFiltersButton
        }
    }

    private var filterFeedback: some View {
        SoftContentCard(padding: AppTheme.eventsCardPadding) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(AppStrings.Guide.resultsCount(viewModel.filteredArticles.count))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    if viewModel.filterState.hasActiveFilters {
                        AppInfoChip(
                            title: AppStrings.Guide.activeFiltersTitle,
                            systemImage: "line.3.horizontal.decrease.circle",
                            tint: AppTheme.accentPrimary,
                            fill: AppTheme.badgeBlueFill,
                            size: .small
                        )
                    }
                }

                Text(activeFilterSummaryText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var contentTypeFilter: some View {
        if !viewModel.availableContentTypes.isEmpty {
            Menu {
                Button(AppStrings.Guide.filterAllTypes) {
                    viewModel.selectedContentType = nil
                }

                ForEach(viewModel.availableContentTypes) { contentType in
                    Button(contentType.guideFilterTitle) {
                        viewModel.selectedContentType = contentType
                    }
                }
            } label: {
                AppFilterChip(
                    title: viewModel.selectedContentType?.guideFilterTitle ?? AppStrings.Guide.filterAllTypes,
                    systemImage: "doc.text.magnifyingglass",
                    isSelected: viewModel.selectedContentType != nil,
                    trailingSystemImage: "chevron.down"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var regionFilter: some View {
        Menu {
            Button(AppStrings.Home.regionAllAustria) {
                viewModel.selectedFederalState = nil
            }

            ForEach(AustrianFederalState.allCases) { federalState in
                Button(federalState.guideFilterDisplayName) {
                    viewModel.selectedFederalState = federalState
                }
            }
        } label: {
            AppFilterChip(
                title: viewModel.selectedFederalState?.guideFilterDisplayName ?? AppStrings.Home.regionAllAustria,
                systemImage: "mappin.and.ellipse",
                isSelected: viewModel.selectedFederalState != nil,
                trailingSystemImage: "chevron.down"
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var audienceFilter: some View {
        if !viewModel.availableAudiences.isEmpty {
            Menu {
                Button(AppStrings.Guide.filterAllAudiences) {
                    viewModel.selectedAudience = nil
                }

                ForEach(viewModel.availableAudiences, id: \.self) { audience in
                    Button(audience) {
                        viewModel.selectedAudience = audience
                    }
                }
            } label: {
                AppFilterChip(
                    title: viewModel.selectedAudience ?? AppStrings.Guide.filterAllAudiences,
                    systemImage: "person.2",
                    isSelected: viewModel.selectedAudience != nil,
                    trailingSystemImage: "chevron.down"
                )
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var clearFiltersButton: some View {
        if viewModel.filterState.hasActiveFilters {
            Button {
                viewModel.clearFilters()
            } label: {
                AppFilterChip(
                    title: AppStrings.Guide.filterClear,
                    systemImage: "xmark.circle",
                    isSelected: false
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var activeFilterSummaryText: String {
        let summaryParts = viewModel.filterState.summaryParts
        if summaryParts.isEmpty {
            return AppStrings.Guide.activeFiltersEmptyHint
        }

        return summaryParts.joined(separator: " • ")
    }
}

private extension GuideContentType {
    var guideFilterTitle: String {
        switch self {
        case .guide:
            AppStrings.Guide.contentTypeGuide
        case .quickInfo:
            AppStrings.Guide.contentTypeQuickInfo
        case .checklist:
            AppStrings.Guide.contentTypeChecklist
        case .contact:
            AppStrings.Guide.contentTypeContact
        case .process:
            AppStrings.Guide.contentTypeProcess
        }
    }
}

private extension AustrianFederalState {
    var guideFilterDisplayName: String {
        AppStrings.FederalStates.title(for: self)
    }
}

private extension GuideFilterState {
    var summaryParts: [String] {
        var parts: [String] = []

        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSearchText.isEmpty {
            parts.append(AppStrings.Guide.filterSummaryItem(AppStrings.Guide.filterSearchLabel, trimmedSearchText))
        }

        if let selectedCategory {
            parts.append(AppStrings.Guide.filterSummaryItem(AppStrings.Guide.filterCategoryLabel, selectedCategory.title))
        }

        if let selectedContentType {
            parts.append(AppStrings.Guide.filterSummaryItem(AppStrings.Guide.filterTypeLabel, selectedContentType.guideFilterTitle))
        }

        if let selectedFederalState {
            parts.append(AppStrings.Guide.filterSummaryItem(AppStrings.Guide.filterRegionLabel, selectedFederalState.guideFilterDisplayName))
        }

        if let selectedAudience, !selectedAudience.isEmpty {
            parts.append(AppStrings.Guide.filterSummaryItem(AppStrings.Guide.filterAudienceLabel, selectedAudience))
        }

        return parts
    }
}
