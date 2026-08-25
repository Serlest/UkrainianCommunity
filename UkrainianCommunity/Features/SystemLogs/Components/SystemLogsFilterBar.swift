import SwiftUI

struct SystemLogsFilterBar: View {
    @Binding var selectedSection: SystemLogDashboardSection
    let sections: [SystemLogDashboardSection]
    let selectedFilters: Set<SystemLogQuickFilter>
    let onToggleFilter: (SystemLogQuickFilter) -> Void
    let onClearFilters: () -> Void

    var body: some View {
        HStack(spacing: AppTheme.eventsMetadataSpacing) {
            Menu {
                Picker(AppStrings.SystemLogs.sectionPickerLabel, selection: $selectedSection) {
                    ForEach(sections) { section in
                        Text(section.title).tag(section)
                    }
                }
            } label: {
                HStack(spacing: AppTheme.eventsMetadataSpacing) {
                    Label(selectedSection.title, systemImage: "rectangle.3.group")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(AppTheme.textPrimary)
                .padding(.horizontal, AppTheme.inputHorizontalPadding)
                .frame(maxWidth: .infinity, minHeight: AppTheme.searchControlHeight)
                .background(AppTheme.surfaceControl.opacity(0.55), in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                        .strokeBorder(AppTheme.borderSubtle)
                }
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
                HStack(spacing: AppTheme.eventsMetadataSpacing) {
                    Label(AppStrings.SystemLogs.filtersTitle, systemImage: "line.3.horizontal.decrease.circle")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    if !selectedFilters.isEmpty {
                        Text("\(selectedFilters.count)")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppTheme.accentPrimary)
                    }
                }
                .foregroundStyle(AppTheme.textPrimary)
                .padding(.horizontal, AppTheme.inputHorizontalPadding)
                .frame(maxWidth: .infinity, minHeight: AppTheme.searchControlHeight)
                .background(AppTheme.surfaceControl.opacity(0.55), in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                        .strokeBorder(AppTheme.borderSubtle)
                }
            }
            .accessibilityLabel(AppStrings.SystemLogs.filtersTitle)
        }
    }
}
