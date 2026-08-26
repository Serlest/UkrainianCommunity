import SwiftUI

struct OwnerAnalyticsView: View {
    private let repository: OwnerAnalyticsRepository
    @StateObject private var viewModel: OwnerAnalyticsViewModel
    @FocusState private var isSearchFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(repository: OwnerAnalyticsRepository) {
        self.repository = repository
        _viewModel = StateObject(wrappedValue: OwnerAnalyticsViewModel(repository: repository))
    }

    var body: some View {
        ProfileDestinationLayout(
            title: AppStrings.OwnerAnalytics.title,
            introSubtitle: AppStrings.OwnerAnalytics.subtitle,
            contentSpacing: AppTheme.sectionSpacing
        ) {
            periodPicker
            searchField
            content
        }
        .task(id: viewModel.selectedPeriod) {
            await viewModel.loadIfNeeded()
        }
        .appRefreshable {
            await viewModel.load()
        }
        .accessibilityIdentifier("screen.ownerAnalytics")
    }

    private var periodPicker: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                periodPickerControl
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                periodPickerControl
                    .pickerStyle(.segmented)
            }
        }
    }

    private var periodPickerControl: some View {
        Picker(AppStrings.OwnerAnalytics.periodPicker, selection: Binding(
            get: { viewModel.selectedPeriod },
            set: { period in
                viewModel.preparePeriodSelection(period)
            }
        )) {
            ForEach(AnalyticsPeriod.allCases) { period in
                Text(period.analyticsTitle).tag(period)
            }
        }
        .accessibilityIdentifier("ownerAnalytics.periodPicker")
    }

    private var searchField: some View {
        AppGlassCard(padding: 12, spacing: 8, shadowRadius: 8, shadowY: 4) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppTheme.textSecondary)
                    .accessibilityHidden(true)

                TextField(AppStrings.OwnerAnalytics.searchPlaceholder, text: $viewModel.searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.subheadline)
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    .onSubmit { isSearchFocused = false }
                    .accessibilityIdentifier("ownerAnalytics.search")

                if !viewModel.searchText.isEmpty {
                    AppSearchClearButton {
                        viewModel.searchText = ""
                    }
                }
            }
            .frame(minHeight: AppTheme.searchControlHeight)
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && !viewModel.hasContent {
            LoadingStateCard(title: AppStrings.OwnerAnalytics.loading)
        } else if let errorMessage = viewModel.errorMessage, !viewModel.hasContent {
            ErrorStateCard(
                title: AppStrings.OwnerAnalytics.loadFailedTitle,
                message: errorMessage,
                retryTitle: AppStrings.OwnerAnalytics.retry
            ) {
                Task { await viewModel.load() }
            }
        } else if !viewModel.hasContent {
            if let partialDataMessage = viewModel.partialDataMessage {
                OwnerAnalyticsPartialDataBanner(message: partialDataMessage)
            }

            EmptyStateCard(
                systemImage: "chart.bar.doc.horizontal",
                title: AppStrings.OwnerAnalytics.emptyTitle,
                message: emptyMessage
            )
        } else {
            loadedContent(staleErrorMessage: viewModel.errorMessage)
        }
    }

    @ViewBuilder
    private func loadedContent(staleErrorMessage: String?) -> some View {
        if let staleErrorMessage {
            OwnerAnalyticsStaleDataBanner(
                message: AppStrings.OwnerAnalytics.staleData(staleErrorMessage),
                isRetrying: viewModel.isLoading
            ) {
                Task { await viewModel.load() }
            }
        }


        if let partialDataMessage = viewModel.partialDataMessage {
            OwnerAnalyticsPartialDataBanner(message: partialDataMessage)
        }

        OwnerAnalyticsFreshnessLabel(updatedAt: viewModel.snapshot.generatedAt)
            .accessibilityIdentifier("ownerAnalytics.updatedAt")

        if viewModel.hasActiveSearch && !viewModel.hasSearchResults {
            EmptyStateCard(
                systemImage: "magnifyingglass",
                title: AppStrings.OwnerAnalytics.searchEmptyTitle,
                message: AppStrings.OwnerAnalytics.searchEmptyMessage
            )
            .accessibilityIdentifier("ownerAnalytics.search.empty")
        } else {
            overviewSection

            if !viewModel.hasActiveSearch && viewModel.trendPoints.count > 1 {
                OwnerAnalyticsSectionCard(
                    title: AppStrings.OwnerAnalytics.trendSectionTitle,
                    subtitle: AppStrings.OwnerAnalytics.trendSubtitle
                ) {
                    OwnerAnalyticsTrendChart(
                        points: viewModel.trendPoints,
                        selectedMetric: $viewModel.selectedTrendMetric,
                        metricOptions: viewModel.trendMetricOptions
                    )
                }
            }

            actionsOverviewSection
            contentAnalyticsSection
            regionalActivitySection
            userAnalyticsSection

            if !viewModel.hasActiveSearch {
                OwnerAnalyticsSectionCard(title: AppStrings.OwnerAnalytics.methodologyTitle) {
                    Text(AppStrings.OwnerAnalytics.methodologyMessage)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var overviewSection: some View {
        if !viewModel.overviewMetricItems.isEmpty || !viewModel.contentViewMetricItems.isEmpty {
            OwnerAnalyticsSectionCard(
                title: AppStrings.OwnerAnalytics.overviewTitle,
                subtitle: viewModel.selectedPeriod.analyticsSummarySubtitle
            ) {
                if !viewModel.overviewMetricItems.isEmpty {
                    metricGrid(viewModel.overviewMetricItems, accentFirst: true)
                }

                if !viewModel.contentViewMetricItems.isEmpty {
                    VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                        Text(AppStrings.OwnerAnalytics.activityOverviewTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .accessibilityAddTraits(.isHeader)

                        metricGrid(viewModel.contentViewMetricItems, accentFirst: false)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var actionsOverviewSection: some View {
        if viewModel.snapshot.actionStats.hasData && !viewModel.actionMetricItems.isEmpty {
            OwnerAnalyticsSectionCard(
                title: AppStrings.OwnerAnalytics.actionsOverviewTitle,
                subtitle: AppStrings.OwnerAnalytics.actionsOverviewSubtitle
            ) {
                metricGrid(viewModel.actionMetricItems, accentFirst: false)
            }
        } else if !viewModel.hasActiveSearch {
            OwnerAnalyticsSectionCard(
                title: AppStrings.OwnerAnalytics.actionsOverviewTitle,
                subtitle: AppStrings.OwnerAnalytics.actionsOverviewSubtitle
            ) {
                OwnerAnalyticsInlineEmptyState(message: AppStrings.OwnerAnalytics.actionsOverviewEmpty)
            }
        }
    }

    @ViewBuilder
    private var userAnalyticsSection: some View {
        if viewModel.snapshot.userStats.hasData
            && (!viewModel.userMetricItems.isEmpty || !viewModel.userFederalStateRows.isEmpty) {
            OwnerAnalyticsSectionCard(
                title: AppStrings.OwnerAnalytics.userAnalyticsTitle,
                subtitle: AppStrings.OwnerAnalytics.userAnalyticsSubtitle
            ) {
                if viewModel.snapshot.userStats.resolvedLifecycleCoverage.isPartial,
                   let startsAt = viewModel.snapshot.userStats.resolvedLifecycleCoverage.startsAt {
                    OwnerAnalyticsPartialDataBanner(
                        message: AppStrings.OwnerAnalytics.lifecyclePartialCoverage(
                            startDate: startsAt
                        )
                    )
                    .accessibilityIdentifier("ownerAnalytics.lifecyclePartialData")
                }

                if !viewModel.userMetricItems.isEmpty {
                    metricGrid(viewModel.userMetricItems, accentFirst: false)
                }

                if !viewModel.hasActiveSearch && viewModel.userFederalStateRows.isEmpty {
                    OwnerAnalyticsInlineEmptyState(message: AppStrings.OwnerAnalytics.userFederalStatesEmpty)
                } else if !viewModel.userFederalStateRows.isEmpty {
                    VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                        Text(AppStrings.OwnerAnalytics.usersByFederalState)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .accessibilityAddTraits(.isHeader)

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
                                .accessibilityHint(AppStrings.OwnerAnalytics.openDetailHint)
                                .accessibilityIdentifier("ownerAnalytics.content.\(item.contentType.rawValue).\(item.contentID)")
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
        } else if !viewModel.hasActiveSearch {
            OwnerAnalyticsSectionCard(
                title: AppStrings.OwnerAnalytics.topContentEmptyTitle,
                subtitle: AppStrings.OwnerAnalytics.topContentSubtitle
            ) {
                OwnerAnalyticsInlineEmptyState(message: AppStrings.OwnerAnalytics.topContentEmptyMessage)
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
        } else if !viewModel.hasActiveSearch {
            OwnerAnalyticsSectionCard(
                title: AppStrings.OwnerAnalytics.regionActivityEmptyTitle,
                subtitle: AppStrings.OwnerAnalytics.regionActivitySubtitle
            ) {
                OwnerAnalyticsInlineEmptyState(message: AppStrings.OwnerAnalytics.regionActivityEmptyMessage)
            }
        }
    }

    private func metricGrid<T: Identifiable>(_ items: [T], accentFirst: Bool) -> some View where T: OwnerAnalyticsMetricDisplayable {
        AppAdaptiveGrid(
            minimumWidth: 140,
            maximumWidth: 240,
            spacing: AppTheme.eventsMetadataSpacing
        ) {
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
                initialTitle: item.analyticsDisplayTitle,
                initialPeriod: viewModel.selectedPeriod
            )
        } else {
            AnalyticsContentDetailView(
                repository: repository,
                contentID: item.contentID,
                contentType: item.contentType,
                initialTitle: item.analyticsDisplayTitle,
                initialPeriod: viewModel.selectedPeriod
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
