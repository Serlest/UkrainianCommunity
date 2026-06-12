import SwiftUI

struct OwnerAnalyticsView: View {
    private let repository: OwnerAnalyticsRepository
    @StateObject private var viewModel: OwnerAnalyticsViewModel
    @FocusState private var isSearchFocused: Bool

    init(repository: OwnerAnalyticsRepository) {
        self.repository = repository
        _viewModel = StateObject(wrappedValue: OwnerAnalyticsViewModel(repository: repository))
    }

    var body: some View {
        ProfileDestinationLayout(
            title: AppStrings.OwnerAnalytics.title,
            introSubtitle: AppStrings.OwnerAnalytics.subtitle
        ) {
            periodPicker
            searchField
            content
        }
        .task {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.load()
        }
    }

    private var periodPicker: some View {
        Picker(AppStrings.OwnerAnalytics.periodPicker, selection: Binding(
            get: { viewModel.selectedPeriod },
            set: { period in
                Task { await viewModel.selectPeriod(period) }
            }
        )) {
            ForEach(AnalyticsPeriod.allCases) { period in
                Text(period.analyticsTitle).tag(period)
            }
        }
        .pickerStyle(.segmented)
    }

    private var searchField: some View {
        AppGlassCard(padding: 12, spacing: 8, shadowRadius: 8, shadowY: 4) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppTheme.textSecondary)

                TextField(AppStrings.OwnerAnalytics.searchPlaceholder, text: $viewModel.searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.subheadline)
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    .onSubmit { isSearchFocused = false }

                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AppStrings.Search.clear)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && !viewModel.hasContent {
            LoadingStateCard(title: AppStrings.OwnerAnalytics.loading)
        } else if let errorMessage = viewModel.errorMessage {
            ErrorStateCard(
                title: AppStrings.OwnerAnalytics.loadFailedTitle,
                message: errorMessage,
                retryTitle: AppStrings.OwnerAnalytics.retry
            ) {
                Task { await viewModel.load() }
            }
        } else if !viewModel.hasContent {
            EmptyStateCard(
                systemImage: "chart.bar.doc.horizontal",
                title: AppStrings.OwnerAnalytics.emptyTitle,
                message: emptyMessage
            )
        } else if viewModel.hasActiveSearch && !viewModel.hasSearchResults {
            EmptyStateCard(
                systemImage: "magnifyingglass",
                title: AppStrings.OwnerAnalytics.searchEmptyTitle,
                message: AppStrings.OwnerAnalytics.searchEmptyMessage
            )
        } else {
            overviewSection
            contentAnalyticsSection
            regionalActivitySection
            userAnalyticsSection
            actionsOverviewSection
        }
    }

    private var overviewSection: some View {
        OwnerAnalyticsSectionCard(
            title: AppStrings.OwnerAnalytics.overviewTitle,
            subtitle: viewModel.selectedPeriod.analyticsSummarySubtitle
        ) {
            metricGrid(viewModel.overviewMetricItems, accentFirst: true)

            if !viewModel.contentViewMetricItems.isEmpty {
                VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                    Text(AppStrings.OwnerAnalytics.activityOverviewTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    metricGrid(viewModel.contentViewMetricItems, accentFirst: false)
                }
            }
        }
    }

    @ViewBuilder
    private var actionsOverviewSection: some View {
        if viewModel.snapshot.actionStats.hasData {
            OwnerAnalyticsSectionCard(
                title: AppStrings.OwnerAnalytics.actionsOverviewTitle,
                subtitle: AppStrings.OwnerAnalytics.actionsOverviewSubtitle
            ) {
                metricGrid(viewModel.actionMetricItems, accentFirst: false)
            }
        }
    }

    @ViewBuilder
    private var userAnalyticsSection: some View {
        if viewModel.snapshot.userStats.hasData {
            OwnerAnalyticsSectionCard(
                title: AppStrings.OwnerAnalytics.userAnalyticsTitle,
                subtitle: AppStrings.OwnerAnalytics.userAnalyticsSubtitle
            ) {
                metricGrid(viewModel.userMetricItems, accentFirst: false)

                if viewModel.userFederalStateRows.isEmpty {
                    OwnerAnalyticsInlineEmptyState(message: AppStrings.OwnerAnalytics.userFederalStatesEmpty)
                } else {
                    VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                        Text(AppStrings.OwnerAnalytics.usersByFederalState)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)

                        VStack(spacing: AppTheme.eventsMetadataSpacing) {
                            ForEach(viewModel.userFederalStateRows) { row in
                                OwnerAnalyticsFederalStateUserRow(row: row)
                            }

                            if viewModel.hasMoreUserFederalStateRows || viewModel.canCollapseUserFederalStateRows {
                                OwnerAnalyticsShowMoreButton(
                                    title: viewModel.canCollapseUserFederalStateRows ? AppStrings.OwnerAnalytics.showLess : AppStrings.OwnerAnalytics.showMore,
                                    systemImage: viewModel.canCollapseUserFederalStateRows ? "chevron.up" : "chevron.down"
                                ) {
                                    viewModel.toggleUserFederalStateExpansion()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var contentAnalyticsSection: some View {
        if !viewModel.topContentSections.isEmpty {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                SectionHeaderBlock(
                    title: AppStrings.OwnerAnalytics.topContentTitle,
                    subtitle: AppStrings.OwnerAnalytics.topContentSubtitle
                )

                ForEach(viewModel.topContentSections) { section in
                    OwnerAnalyticsSectionCard(title: section.title) {
                        VStack(spacing: AppTheme.eventsMetadataSpacing) {
                            ForEach(section.items) { item in
                                NavigationLink {
                                    analyticsDetailDestination(for: item)
                                } label: {
                                    OwnerAnalyticsContentRow(item: item)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }

                            if section.hasHiddenItems || section.canCollapse {
                                OwnerAnalyticsShowMoreButton(
                                    title: section.canCollapse ? AppStrings.OwnerAnalytics.showLess : AppStrings.OwnerAnalytics.showMore,
                                    systemImage: section.canCollapse ? "chevron.up" : "chevron.down"
                                ) {
                                    viewModel.toggleContentSectionExpansion(section.contentType)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var regionalActivitySection: some View {
        if !viewModel.regionRows.isEmpty {
            OwnerAnalyticsSectionCard(
                title: AppStrings.OwnerAnalytics.regionActivityTitle,
                subtitle: AppStrings.OwnerAnalytics.regionActivitySubtitle
            ) {
                VStack(spacing: AppTheme.eventsMetadataSpacing) {
                    ForEach(viewModel.regionRows) { row in
                        OwnerAnalyticsRegionRow(row: row)
                    }

                    if viewModel.hasMoreRegionRows || viewModel.canCollapseRegionRows {
                        OwnerAnalyticsShowMoreButton(
                            title: viewModel.canCollapseRegionRows ? AppStrings.OwnerAnalytics.showLess : AppStrings.OwnerAnalytics.showMore,
                            systemImage: viewModel.canCollapseRegionRows ? "chevron.up" : "chevron.down"
                        ) {
                            viewModel.toggleRegionExpansion()
                        }
                    }
                }
            }
        }
    }

    private func metricGrid<T: Identifiable>(_ items: [T], accentFirst: Bool) -> some View where T: OwnerAnalyticsMetricDisplayable {
        LazyVGrid(columns: metricColumns, spacing: AppTheme.eventsMetadataSpacing) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                OwnerAnalyticsMetricTile(
                    title: item.title,
                    value: item.value,
                    previousValue: item.previousValue,
                    systemImage: item.systemImage,
                    accentStyle: accentFirst && index == 0
                )
            }
        }
    }

    private var metricColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: AppTheme.eventsMetadataSpacing),
            GridItem(.flexible(), spacing: AppTheme.eventsMetadataSpacing)
        ]
    }

    private var emptyMessage: String {
        switch viewModel.selectedPeriod {
        case .today:
            return AppStrings.OwnerAnalytics.emptyTodayMessage
        case .sevenDays, .thirtyDays:
            return AppStrings.OwnerAnalytics.emptyRollupMessage
        }
    }

    @ViewBuilder
    private func analyticsDetailDestination(for item: AnalyticsTopContentItem) -> some View {
        if item.contentType == .organization {
            AnalyticsOrganizationDetailView(
                repository: repository,
                organizationID: item.organizationID ?? item.contentID,
                initialTitle: item.analyticsDisplayTitle
            )
        } else {
            AnalyticsContentDetailView(
                repository: repository,
                contentID: item.contentID,
                contentType: item.contentType,
                initialTitle: item.analyticsDisplayTitle
            )
        }
    }
}

protocol OwnerAnalyticsMetricDisplayable {
    var title: String { get }
    var value: Int { get }
    var previousValue: Int? { get }
    var systemImage: String { get }
}

extension OwnerAnalyticsMetricDisplayable {
    var previousValue: Int? { nil }
}

extension OwnerAnalyticsOverviewMetricItem: OwnerAnalyticsMetricDisplayable {}
extension OwnerAnalyticsUserMetricItem: OwnerAnalyticsMetricDisplayable {}

private extension AnalyticsPeriod {
    var analyticsTitle: String {
        switch self {
        case .today:
            AppStrings.OwnerAnalytics.periodToday
        case .sevenDays:
            AppStrings.OwnerAnalytics.periodSevenDays
        case .thirtyDays:
            AppStrings.OwnerAnalytics.periodThirtyDays
        }
    }

    var analyticsSummarySubtitle: String {
        switch self {
        case .today:
            AppStrings.OwnerAnalytics.todaySummarySubtitle
        case .sevenDays:
            AppStrings.OwnerAnalytics.sevenDaysSummarySubtitle
        case .thirtyDays:
            AppStrings.OwnerAnalytics.thirtyDaysSummarySubtitle
        }
    }
}

#Preview {
    NavigationStack {
        OwnerAnalyticsView(repository: MockOwnerAnalyticsRepository())
    }
}
