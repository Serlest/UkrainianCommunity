import SwiftUI

struct SystemLogsFilterBar: View {
    @Binding var selectedSection: SystemLogDashboardSection
    let sections: [SystemLogDashboardSection]
    let selectedFilters: Set<SystemLogQuickFilter>
    let onToggleFilter: (SystemLogQuickFilter) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
            Picker(AppStrings.SystemLogs.sectionPickerLabel, selection: $selectedSection) {
                ForEach(sections) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)

            AppHorizontalFilterRow {
                ForEach(SystemLogQuickFilter.allCases) { filter in
                    Button {
                        onToggleFilter(filter)
                    } label: {
                        AppFilterChip(
                            title: filter.title,
                            systemImage: filter.systemImage,
                            isSelected: selectedFilters.contains(filter)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, -AppTheme.eventsMetadataSpacing)
        }
    }
}
