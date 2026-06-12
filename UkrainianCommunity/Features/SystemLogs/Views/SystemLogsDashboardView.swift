import SwiftUI

struct SystemLogsDashboardView: View {
    @StateObject private var viewModel: SystemLogsViewModel
    @FocusState private var isSearchFocused: Bool
    private let embedsInNavigationStack: Bool

    @MainActor
    init(
        viewModel: SystemLogsViewModel? = nil,
        accessMode: SystemLogsAccessMode = .owner,
        embedsInNavigationStack: Bool = true
    ) {
        _viewModel = StateObject(wrappedValue: viewModel ?? SystemLogsViewModel(accessMode: accessMode))
        self.embedsInNavigationStack = embedsInNavigationStack
    }

    var body: some View {
        Group {
            if embedsInNavigationStack {
                NavigationStack {
                    dashboardContent
                }
            } else {
                dashboardContent
            }
        }
    }

    private var dashboardContent: some View {
        AdminScreenShell(
            title: viewModel.accessMode.title,
            subtitle: viewModel.accessMode.subtitle,
            showsBackButton: !embedsInNavigationStack,
            tabBarHidden: false
        ) {
            searchBar
        } metrics: {
            SystemLogsOverviewCards(metrics: viewModel.overviewMetrics)
        } trailingContent: {
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 3)
            }
        } content: {
            filters
            content
        }
        .task {
            viewModel.ensureSelectedSectionIsVisible()
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    private var searchBar: some View {
        HStack(spacing: AppTheme.eventsMetadataSpacing) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)

            TextField(AppStrings.SystemLogs.searchPlaceholder, text: $viewModel.searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.subheadline)
                .foregroundStyle(AppTheme.textPrimary)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .onSubmit { isSearchFocused = false }

            if !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    viewModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppStrings.SystemLogs.clearSearch)
            }
        }
        .padding(.horizontal, AppTheme.inputHorizontalPadding)
        .frame(height: AppTheme.searchControlHeight)
        .background(AppTheme.surfaceControl.opacity(0.55), in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle)
        }
    }

    private var filters: some View {
        SystemLogsFilterBar(
            selectedSection: $viewModel.selectedSection,
            sections: viewModel.accessMode.visibleSections,
            selectedFilters: viewModel.selectedFilters,
            onToggleFilter: { filter in
                viewModel.toggleFilter(filter)
            }
        )
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage = viewModel.errorMessage {
            SoftContentCard(padding: 16) {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accentDestructive)
            }
        } else if viewModel.isLoading && viewModel.logs.isEmpty {
            SoftContentCard(padding: 16) {
                HStack(spacing: AppTheme.eventsMetadataSpacing) {
                    ProgressView()
                        .controlSize(.small)

                    Text(AppStrings.SystemLogs.loading)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }
        } else if viewModel.visibleLogs.isEmpty && !viewModel.isLoading {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                DashboardSectionHeader(
                    title: AppStrings.SystemLogs.records,
                    subtitle: "\(viewModel.visibleLogs.count) \(AppStrings.SystemLogs.recordsCountSuffix)"
                )

                SystemLogsListView(
                    logs: viewModel.visibleLogs,
                    destination: { log in
                        SystemLogDetailRoute(
                            viewModel: viewModel,
                            logID: log.id,
                            fallbackLog: log
                        )
                    }
                )
            }
        }
    }

    private var emptyState: some View {
        SoftContentCard(padding: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label(viewModel.logs.isEmpty ? AppStrings.SystemLogs.emptyTitle : AppStrings.SystemLogs.filteredEmptyTitle, systemImage: "doc.text.magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)

                Text(viewModel.logs.isEmpty ? AppStrings.SystemLogs.emptyMessage : AppStrings.SystemLogs.filteredEmptyMessage)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }
}

private struct SystemLogDetailRoute: View {
    @ObservedObject var viewModel: SystemLogsViewModel
    let logID: String
    let fallbackLog: SystemLogEntry

    var body: some View {
        let currentLog = viewModel.log(id: logID) ?? fallbackLog
        SystemLogDetailView(
            log: currentLog,
            isMarkingReviewed: viewModel.reviewingLogIDs.contains(logID),
            reviewErrorMessage: viewModel.reviewErrorMessage(for: logID),
            onMarkReviewed: {
                await viewModel.markReviewed(logID: logID)
            }
        )
    }
}

#Preview {
    SystemLogsDashboardView(
        viewModel: SystemLogsViewModel(repository: MockSystemLogRepository())
    )
}
