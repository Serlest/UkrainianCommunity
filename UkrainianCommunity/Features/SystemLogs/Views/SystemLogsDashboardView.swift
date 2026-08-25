import SwiftUI

struct SystemLogsDashboardView: View {
    @StateObject private var viewModel: SystemLogsViewModel
    @FocusState private var isSearchFocused: Bool
    @State private var isConfirmingClear = false
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
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                SystemLogsOverviewCards(metrics: viewModel.overviewMetrics)
                Text(AppStrings.SystemLogs.loadedMetricsNote)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } trailingContent: {
            HStack(spacing: AppTheme.eventsMetadataSpacing) {
                if viewModel.isLoading || viewModel.isClearingLogs {
                    ProgressView()
                        .controlSize(.small)
                }

                if viewModel.accessMode == .owner, !viewModel.logs.isEmpty {
                    AppGlassIconButton(
                        systemImage: "trash",
                        accessibilityLabel: AppStrings.SystemLogs.clearAll,
                        role: .destructive
                    ) {
                        isConfirmingClear = true
                    }
                    .disabled(viewModel.isClearingLogs)
                    .accessibilityIdentifier("systemLogs.clearAll")
                }
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
        .confirmationDialog(
            AppStrings.SystemLogs.clearConfirmationTitle,
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button(AppStrings.SystemLogs.clearAll, role: .destructive) {
                Task { await viewModel.clearAllLogs() }
            }
            Button(AppStrings.Common.cancel, role: .cancel) {}
        } message: {
            Text(AppStrings.SystemLogs.clearConfirmationMessage)
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
                AppSearchClearButton {
                    viewModel.searchText = ""
                }
            }
        }
        .padding(.horizontal, AppTheme.inputHorizontalPadding)
        .frame(minHeight: AppTheme.searchControlHeight)
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
            },
            onClearFilters: { viewModel.clearQuickFilters() }
        )
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage = viewModel.errorMessage, viewModel.logs.isEmpty {
            ErrorStateCard(
                title: viewModel.accessMode.title,
                message: errorMessage,
                retryTitle: AppStrings.Action.retry
            ) {
                Task { await viewModel.refresh() }
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
                if let errorMessage = viewModel.errorMessage {
                    InlineMessageCard(style: .error, message: errorMessage)
                }

                if let clearLogsErrorMessage = viewModel.clearLogsErrorMessage {
                    InlineMessageCard(style: .error, message: clearLogsErrorMessage)
                }

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

                if viewModel.canLoadMore {
                    PrimaryActionButton(
                        title: AppStrings.SystemLogs.loadMore,
                        loadingTitle: AppStrings.SystemLogs.loadingMore,
                        isLoading: viewModel.isLoadingNextPage,
                        systemImage: "arrow.down.circle"
                    ) {
                        Task { await viewModel.loadNextPage() }
                    }
                }

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

                if !viewModel.logs.isEmpty {
                    Button(AppStrings.SystemLogs.clearFilters) {
                        viewModel.clearSearchAndFilters()
                    }
                    .buttonStyle(.bordered)
                    .tint(AppTheme.accentPrimary)
                }
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
