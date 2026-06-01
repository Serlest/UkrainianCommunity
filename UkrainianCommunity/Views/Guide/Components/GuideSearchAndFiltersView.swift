import SwiftUI

struct GuideSearchAndFiltersView: View {
    @ObservedObject var viewModel: GuideListViewModel

    var body: some View {
        filterRow
    }

    private var filterRow: some View {
        AppHorizontalFilterRow {
            contentTypeFilter
            regionFilter
            audienceFilter
            clearFiltersButton
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
