import SwiftUI

struct SystemLogsAdvancedFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: SystemLogsViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    SectionHeaderBlock(
                        title: AppStrings.SystemLogs.advancedFiltersTitle,
                        subtitle: AppStrings.SystemLogs.advancedFiltersSubtitle
                    )

                    selectionSection(title: AppStrings.SystemLogs.periodTitle, systemImage: "calendar") {
                        ForEach(SystemLogDatePreset.allCases) { preset in
                            singleSelectionRow(
                                title: preset.title,
                                isSelected: viewModel.datePreset == preset
                            ) {
                                viewModel.datePreset = preset
                            }
                        }
                    }

                    selectionSection(title: AppStrings.SystemLogs.reviewStatusSection, systemImage: "checkmark.seal") {
                        ForEach(SystemLogReviewFilter.allCases) { filter in
                            singleSelectionRow(
                                title: filter.title,
                                isSelected: viewModel.reviewFilter == filter
                            ) {
                                viewModel.reviewFilter = filter
                            }
                        }
                    }

                    selectionSection(title: AppStrings.SystemLogs.severityLabel, systemImage: "exclamationmark.triangle") {
                        ForEach(SystemLogSeverity.allCases, id: \.self) { severity in
                            multipleSelectionRow(
                                title: SystemLogDisplayFormatting.severityTitle(severity),
                                tint: SystemLogDisplayFormatting.severityTint(severity),
                                isSelected: viewModel.selectedSeverities.contains(severity)
                            ) {
                                toggle(severity, in: &viewModel.selectedSeverities)
                            }
                        }
                    }

                    selectionSection(title: AppStrings.SystemLogs.categoryLabel, systemImage: "square.grid.2x2") {
                        ForEach(SystemLogCategory.allCases, id: \.self) { category in
                            multipleSelectionRow(
                                title: SystemLogDisplayFormatting.categoryTitle(category),
                                isSelected: viewModel.selectedCategories.contains(category)
                            ) {
                                toggle(category, in: &viewModel.selectedCategories)
                            }
                        }
                    }

                    selectionSection(title: AppStrings.SystemLogs.outcomeLabel, systemImage: "arrow.triangle.branch") {
                        ForEach(SystemLogOutcome.allCases, id: \.self) { outcome in
                            multipleSelectionRow(
                                title: SystemLogDisplayFormatting.outcomeTitle(outcome),
                                isSelected: viewModel.selectedOutcomes.contains(outcome)
                            ) {
                                toggle(outcome, in: &viewModel.selectedOutcomes)
                            }
                        }
                    }
                }
                .padding(.horizontal, AppTheme.pageHorizontal)
                .padding(.bottom, AppTheme.pushedScreenBottomPadding)
            }
            .background(AppTheme.groupedBackground.ignoresSafeArea())
            .navigationTitle(AppStrings.SystemLogs.filtersTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.SystemLogs.resetFilters) {
                        viewModel.clearAdvancedFilters()
                    }
                    .disabled(viewModel.advancedFilterCount == 0)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.Common.done) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
    }

    private func selectionSection<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: systemImage)
                    .font(AppTheme.sectionTitleFont)
                    .foregroundStyle(AppTheme.textPrimary)

                content()
            }
        }
    }

    private func singleSelectionRow(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        selectionRow(title: title, tint: AppTheme.accentPrimaryForeground, isSelected: isSelected, action: action)
    }

    private func multipleSelectionRow(
        title: String,
        tint: Color = AppTheme.accentPrimaryForeground,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        selectionRow(title: title, tint: tint, isSelected: isSelected, action: action)
    }

    private func selectionRow(
        title: String,
        tint: Color,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isSelected ? tint : AppTheme.textSecondary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func toggle<Value: Hashable>(_ value: Value, in selection: inout Set<Value>) {
        if selection.contains(value) {
            selection.remove(value)
        } else {
            selection.insert(value)
        }
    }
}
