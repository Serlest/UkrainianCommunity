import SwiftUI

struct SystemLogsFilterBar: View {
    @Binding var selectedSection: SystemLogDashboardSection
    @Binding var sortOption: SystemLogSortOption
    let sections: [SystemLogDashboardSection]
    let selectedFilters: Set<SystemLogQuickFilter>
    let onToggleFilter: (SystemLogQuickFilter) -> Void
    let onClearFilters: () -> Void

    var body: some View {
        AppHorizontalFilterRow {
            Menu {
                Picker(AppStrings.SystemLogs.sectionPickerLabel, selection: $selectedSection) {
                    ForEach(sections) { section in
                        Text(section.title).tag(section)
                    }
                }
            } label: {
                AppFilterChip(
                    title: selectedSection.title,
                    systemImage: "rectangle.3.group",
                    isSelected: selectedSection != .all,
                    trailingSystemImage: "chevron.down"
                )
            }
            .accessibilityLabel(AppStrings.SystemLogs.sectionPickerLabel)

            Menu {
                ForEach(SystemLogQuickFilter.allCases) { filter in
                    Button {
                        onToggleFilter(filter)
                    } label: {
                        Label(
                            filter.title,
                            systemImage: selectedFilters.contains(filter) ? "checkmark" : (filter.systemImage ?? "circle")
                        )
                    }
                }

                if !selectedFilters.isEmpty {
                    Divider()
                    Button(AppStrings.SystemLogs.clearQuickFilters, role: .destructive) {
                        onClearFilters()
                    }
                }
            } label: {
                AppFilterChip(
                    title: selectedFilters.isEmpty ? AppStrings.SystemLogs.filtersTitle : "\(AppStrings.SystemLogs.filtersTitle) · \(selectedFilters.count)",
                    systemImage: "line.3.horizontal.decrease.circle",
                    isSelected: !selectedFilters.isEmpty,
                    trailingSystemImage: "chevron.down"
                )
            }
            .accessibilityLabel(AppStrings.SystemLogs.filtersTitle)

            AppSortMenu(
                selection: $sortOption,
                options: SystemLogSortOption.allCases,
                title: \.title,
                systemImage: \.systemImage
            )
        }
    }
}
