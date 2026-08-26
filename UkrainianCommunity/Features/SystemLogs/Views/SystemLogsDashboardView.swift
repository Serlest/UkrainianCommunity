import SwiftUI

struct SystemLogsDashboardView: View {
    @StateObject private var viewModel: SystemLogsViewModel
    @FocusState private var isSearchFocused: Bool
    @State private var isConfirmingClear = false
    @State private var logPendingDeletion: SystemLogEntry?
    @State private var isShowingAdvancedFilters = false
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
                SystemLogsOverviewCards(metrics: viewModel.overviewMetrics) { metric in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.applyMetric(id: metric.id)
                    }
                }
                Text(AppStrings.SystemLogs.loadedMetricsNote)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } trailingContent: {
            HStack(spacing: AppTheme.eventsMetadataSpacing) {
                if viewModel.isLoading || viewModel.isClearingLogs || viewModel.isMarkingVisibleReviewed {
                    ProgressView()
                        .controlSize(.small)
                }

                if !viewModel.logs.isEmpty {
                    actionsMenu
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
        .onChange(of: viewModel.sortOption) {
            Task { await viewModel.refresh() }
        }
        .refreshable {
            await viewModel.refresh()
        }
        .sheet(isPresented: $isShowingAdvancedFilters) {
            SystemLogsAdvancedFilterSheet(viewModel: viewModel)
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
        .confirmationDialog(
            AppStrings.SystemLogs.deleteConfirmationTitle,
            isPresented: Binding(
                get: { logPendingDeletion != nil },
                set: { if !$0 { logPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(AppStrings.Action.delete, role: .destructive) {
                guard let log = logPendingDeletion else { return }
                logPendingDeletion = nil
                Task { await viewModel.deleteLog(id: log.id) }
            }
            Button(AppStrings.Common.cancel, role: .cancel) { logPendingDeletion = nil }
        } message: {
            Text(AppStrings.SystemLogs.deleteConfirmationMessage)
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
        VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
            SystemLogsFilterBar(
                selectedSection: $viewModel.selectedSection,
                sortOption: $viewModel.sortOption,
                sections: viewModel.accessMode.visibleSections,
                selectedFilters: viewModel.selectedFilters,
                advancedFilterCount: viewModel.advancedFilterCount,
                onToggleFilter: { filter in
                    viewModel.toggleFilter(filter)
                },
                onClearFilters: { viewModel.clearQuickFilters() },
                onShowAdvancedFilters: { isShowingAdvancedFilters = true }
            )

            if viewModel.hasActiveFilters {
                HStack(spacing: 8) {
                    Label(AppStrings.SystemLogs.filteredLoadedScope, systemImage: "line.3.horizontal.decrease.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)

                    Spacer(minLength: 8)

                    Button(AppStrings.SystemLogs.resetFilters) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.clearSearchAndFilters()
                        }
                    }
                    .font(.caption.weight(.semibold))
                }
            }
        }
    }

    private var actionsMenu: some View {
        Menu {
            Button {
                Task { await viewModel.refresh() }
            } label: {
                Label(AppStrings.SystemLogs.refresh, systemImage: "arrow.clockwise")
            }

            if !viewModel.unreviewedVisibleLogs.isEmpty {
                Button {
                    Task { await viewModel.markVisibleReviewed() }
                } label: {
                    Label(AppStrings.SystemLogs.markVisibleReviewed, systemImage: "checkmark.seal")
                }
                .disabled(viewModel.isMarkingVisibleReviewed)
            }

            if viewModel.accessMode == .owner {
                Divider()
                Button(role: .destructive) {
                    isConfirmingClear = true
                } label: {
                    Label(AppStrings.SystemLogs.clearAll, systemImage: "trash")
                }
                .disabled(viewModel.isClearingLogs)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .frame(width: AppTheme.minimumInteractiveTarget, height: AppTheme.minimumInteractiveTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(AppStrings.SystemLogs.actionsMenu)
        .accessibilityIdentifier("systemLogs.actions")
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

                if let bulkReviewErrorMessage = viewModel.bulkReviewErrorMessage {
                    InlineMessageCard(style: .error, message: bulkReviewErrorMessage)
                }

                DashboardSectionHeader(
                    title: AppStrings.SystemLogs.records,
                    subtitle: "\(viewModel.visibleLogs.count) \(AppStrings.SystemLogs.recordsCountSuffix)"
                )

                if viewModel.groupedVisibleLogs.isEmpty {
                    logsList(viewModel.visibleLogs)
                } else {
                    ForEach(viewModel.groupedVisibleLogs) { group in
                        DashboardSectionHeader(
                            title: group.title,
                            subtitle: "\(group.logs.count) \(AppStrings.SystemLogs.recordsCountSuffix)"
                        )
                        logsList(group.logs)
                    }
                }

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

    private func logsList(_ logs: [SystemLogEntry]) -> some View {
        SystemLogsListView(
            logs: logs,
            deletingIDs: viewModel.deletingLogIDs,
            deleteAction: viewModel.accessMode == .owner ? { logPendingDeletion = $0 } : nil,
            reviewAction: { log in
                Task { await viewModel.markReviewed(logID: log.id) }
            },
            destination: { log in
                SystemLogDetailRoute(
                    viewModel: viewModel,
                    logID: log.id,
                    fallbackLog: log
                )
            }
        )
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
