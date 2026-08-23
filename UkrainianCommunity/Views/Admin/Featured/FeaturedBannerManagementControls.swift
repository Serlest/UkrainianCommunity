import SwiftUI

enum FeaturedBannerManagementFilter: String, CaseIterable, Identifiable {
    case all
    case live
    case scheduled
    case inactive
    case needsAttention

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return AppStrings.FeaturedManagement.filterAll
        case .live:
            return AppStrings.FeaturedManagement.statusLive
        case .scheduled:
            return AppStrings.FeaturedManagement.statusScheduled
        case .inactive:
            return AppStrings.FeaturedManagement.inactive
        case .needsAttention:
            return AppStrings.FeaturedManagement.filterNeedsAttention
        }
    }

    func includes(_ banner: FeaturedBanner) -> Bool {
        switch (self, banner.lifecycleState()) {
        case (.all, _):
            return true
        case (.live, .live), (.scheduled, .scheduled), (.inactive, .inactive):
            return true
        case (.needsAttention, .migrationRequired), (.needsAttention, .expired):
            return true
        default:
            return false
        }
    }
}

struct FeaturedBannerManagementControls: View {
    @Binding var searchText: String
    @Binding var filter: FeaturedBannerManagementFilter
    let visibleCount: Int
    let totalCount: Int

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                HStack(spacing: AppTheme.eventsMetadataSpacing) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AppTheme.textSecondary)

                    TextField(AppStrings.FeaturedManagement.searchPlaceholder, text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if !searchText.isEmpty {
                        AppSearchClearButton {
                            searchText = ""
                        }
                    }
                }
                .padding(.horizontal, AppTheme.inputHorizontalPadding)
                .frame(minHeight: AppTheme.newsEditorInputHeight)
                .background(AppTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.inputRadius, style: .continuous)
                        .strokeBorder(AppTheme.borderSubtle)
                }

                HStack {
                    Picker(AppStrings.FeaturedManagement.filterLabel, selection: $filter) {
                        ForEach(FeaturedBannerManagementFilter.allCases) { filter in
                            Text(filter.title).tag(filter)
                        }
                    }
                    .pickerStyle(.menu)

                    Spacer()

                    Text(AppStrings.FeaturedManagement.resultsCount(visibleCount, total: totalCount))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
    }
}
