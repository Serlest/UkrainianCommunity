import SwiftUI

struct AnalyticsContentDetailView: View {
    @StateObject private var viewModel: AnalyticsContentDetailViewModel

    init(
        repository: OwnerAnalyticsRepository,
        contentID: String,
        contentType: AnalyticsContentType,
        initialTitle: String,
        initialPeriod: AnalyticsPeriod = .today
    ) {
        _viewModel = StateObject(wrappedValue: AnalyticsContentDetailViewModel(
            repository: repository,
            contentID: contentID,
            contentType: contentType,
            initialTitle: initialTitle,
            initialPeriod: initialPeriod
        ))
    }

    var body: some View {
        AnalyticsDetailContainer(navigationTitle: AppStrings.OwnerAnalytics.detailAnalyticsTitle) {
            AppGroupedContentPlane {
                header
                periodPicker
                content
            }
        }
        .task(id: viewModel.selectedPeriod) { await viewModel.loadIfNeeded() }
        .refreshable { await viewModel.load() }
        .accessibilityIdentifier("screen.ownerAnalytics.contentDetail")
    }

    private var header: some View {
        OwnerAnalyticsSectionCard(
            title: viewModel.title,
            subtitle: viewModel.subtitle
        ) {
            if !viewModel.relatedChips.isEmpty {
                AnalyticsDetailChipFlow(chips: viewModel.relatedChips)
            }
        }
    }

    private var periodPicker: some View {
        AnalyticsDetailPeriodPicker(
            selectedPeriod: Binding(
                get: { viewModel.selectedPeriod },
                set: { period in viewModel.preparePeriodSelection(period) }
            )
        )
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
        } else {
            if viewModel.snapshot.resolvedCoverage.isPartial,
               let startsAt = viewModel.snapshot.resolvedCoverage.startsAt {
                OwnerAnalyticsPartialDataBanner(
                    message: AppStrings.OwnerAnalytics.detailPartialCoverage(
                        startDate: startsAt
                    )
                )
            }

            if !viewModel.hasContent {
                EmptyStateCard(
                    systemImage: "chart.bar.doc.horizontal",
                    title: AppStrings.OwnerAnalytics.noDetailAnalyticsTitle,
                    message: AppStrings.OwnerAnalytics.noDetailAnalyticsMessage
                )
            } else {
                loadedContent(staleErrorMessage: viewModel.errorMessage)
            }
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

        AnalyticsDetailFreshnessRow(updatedAt: viewModel.snapshot.updatedAt)

        OwnerAnalyticsSectionCard(title: AppStrings.OwnerAnalytics.overviewTitle) {
            AnalyticsDetailMetricGrid(items: viewModel.metricItems)

            if let registrationsPerTrackedViewText = viewModel.registrationsPerTrackedViewText {
                AnalyticsDetailValueRow(
                    title: AppStrings.OwnerAnalytics.registrationsPerTrackedView,
                    value: registrationsPerTrackedViewText,
                    systemImage: "arrow.triangle.branch"
                )
            }
        }

        AnalyticsDetailRegionSection(rows: viewModel.regionRows)
    }
}

struct AnalyticsOrganizationDetailView: View {
    private let repository: OwnerAnalyticsRepository
    @StateObject private var viewModel: AnalyticsOrganizationDetailViewModel

    init(
        repository: OwnerAnalyticsRepository,
        organizationID: String,
        initialTitle: String,
        initialPeriod: AnalyticsPeriod = .today
    ) {
        self.repository = repository
        _viewModel = StateObject(wrappedValue: AnalyticsOrganizationDetailViewModel(
            repository: repository,
            organizationID: organizationID,
            initialTitle: initialTitle,
            initialPeriod: initialPeriod
        ))
    }

    var body: some View {
        AnalyticsDetailContainer(navigationTitle: AppStrings.OwnerAnalytics.detailAnalyticsTitle) {
            AppGroupedContentPlane {
                header
                periodPicker
                searchField
                content
            }
        }
        .task(id: viewModel.selectedPeriod) { await viewModel.loadIfNeeded() }
        .refreshable { await viewModel.load() }
        .accessibilityIdentifier("screen.ownerAnalytics.organizationDetail")
    }

    private var header: some View {
        OwnerAnalyticsSectionCard(
            title: viewModel.title,
            subtitle: AppStrings.OwnerAnalytics.organizationDetailSubtitle
        ) {
            if !viewModel.relatedChips.isEmpty {
                AnalyticsDetailChipFlow(chips: viewModel.relatedChips)
            }
        }
    }

    private var periodPicker: some View {
        AnalyticsDetailPeriodPicker(
            selectedPeriod: Binding(
                get: { viewModel.selectedPeriod },
                set: { period in viewModel.preparePeriodSelection(period) }
            )
        )
    }

    private var searchField: some View {
        AnalyticsDetailSearchField(text: $viewModel.searchText)
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
        } else {
            if viewModel.snapshot.resolvedCoverage.isPartial,
               let startsAt = viewModel.snapshot.resolvedCoverage.startsAt {
                OwnerAnalyticsPartialDataBanner(
                    message: AppStrings.OwnerAnalytics.detailPartialCoverage(
                        startDate: startsAt
                    )
                )
            }

            if !viewModel.hasContent {
                EmptyStateCard(
                    systemImage: "chart.bar.doc.horizontal",
                    title: AppStrings.OwnerAnalytics.noDetailAnalyticsTitle,
                    message: AppStrings.OwnerAnalytics.noDetailAnalyticsMessage
                )
            } else {
                loadedContent(staleErrorMessage: viewModel.errorMessage)
            }
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

        AnalyticsDetailFreshnessRow(updatedAt: viewModel.snapshot.updatedAt)

        if viewModel.hasActiveSearch && !viewModel.hasSearchResults {
            EmptyStateCard(
                systemImage: "magnifyingglass",
                title: AppStrings.OwnerAnalytics.searchEmptyTitle,
                message: AppStrings.OwnerAnalytics.searchEmptyMessage
            )
            .accessibilityIdentifier("ownerAnalytics.detail.search.empty")
        } else {
            if !viewModel.metricItems.isEmpty {
                OwnerAnalyticsSectionCard(title: AppStrings.OwnerAnalytics.overviewTitle) {
                    AnalyticsDetailMetricGrid(items: viewModel.metricItems)
                }
            }

            if !viewModel.hasActiveSearch || !viewModel.topNewsItems.isEmpty {
                AnalyticsOrganizationTopContentSection(
                    repository: repository,
                    selectedPeriod: viewModel.selectedPeriod,
                    title: AppStrings.OwnerAnalytics.topNews,
                    items: viewModel.topNewsItems,
                    hasMoreItems: viewModel.hasMoreTopNews,
                    canCollapse: viewModel.canCollapseTopNews
                ) {
                    viewModel.toggleTopNewsExpansion()
                }
            }

            if !viewModel.hasActiveSearch || !viewModel.topEventsItems.isEmpty {
                AnalyticsOrganizationTopContentSection(
                    repository: repository,
                    selectedPeriod: viewModel.selectedPeriod,
                    title: AppStrings.OwnerAnalytics.topEvents,
                    items: viewModel.topEventsItems,
                    hasMoreItems: viewModel.hasMoreTopEvents,
                    canCollapse: viewModel.canCollapseTopEvents
                ) {
                    viewModel.toggleTopEventsExpansion()
                }
            }

            if !viewModel.hasActiveSearch || !viewModel.regionRows.isEmpty {
                AnalyticsDetailRegionSection(rows: viewModel.regionRows)
            }
        }
    }
}

private struct AnalyticsDetailFreshnessRow: View {
    let updatedAt: Date?

    var body: some View {
        OwnerAnalyticsFreshnessLabel(updatedAt: updatedAt)
    }
}

private struct AnalyticsDetailContainer<Content: View>: View {
    let navigationTitle: String
    @ViewBuilder let content: Content

    var body: some View {
        PushedScreenShell(title: navigationTitle) {
            content
        }
    }
}

private struct AnalyticsDetailPeriodPicker: View {
    @Binding var selectedPeriod: AnalyticsPeriod
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                picker
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                picker
                    .pickerStyle(.segmented)
            }
        }
    }

    private var picker: some View {
        Picker(AppStrings.OwnerAnalytics.periodPicker, selection: $selectedPeriod) {
            ForEach(AnalyticsPeriod.allCases) { period in
                Text(period.analyticsDetailTitle).tag(period)
            }
        }
        .accessibilityIdentifier("ownerAnalytics.detail.periodPicker")
    }
}

private struct AnalyticsDetailSearchField: View {
    @Binding var text: String
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        AppGlassCard(padding: 12, spacing: 8, shadowRadius: 8, shadowY: 4) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppTheme.textSecondary)
                    .accessibilityHidden(true)

                TextField(AppStrings.OwnerAnalytics.searchPlaceholder, text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.subheadline)
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    .onSubmit { isSearchFocused = false }
                    .accessibilityIdentifier("ownerAnalytics.detail.search")

                if !text.isEmpty {
                    AppSearchClearButton {
                        text = ""
                    }
                }
            }
            .frame(minHeight: AppTheme.searchControlHeight)
        }
    }
}

private struct AnalyticsDetailMetricGrid: View {
    let items: [OwnerAnalyticsDetailMetricItem]

    var body: some View {
        AppAdaptiveGrid(
            minimumWidth: 140,
            maximumWidth: 240,
            spacing: AppTheme.eventsMetadataSpacing
        ) {
            ForEach(items) { item in
                OwnerAnalyticsMetricTile(
                    title: item.title,
                    value: item.value,
                    systemImage: item.systemImage
                )
            }
        }
    }

}

private struct AnalyticsDetailChipFlow: View {
    let chips: [OwnerAnalyticsDetailChipModel]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(chips) { chip in
                AppInfoChip(
                    title: chip.title,
                    systemImage: chip.systemImage,
                    size: .small
                )
            }
        }
    }
}

private struct AnalyticsDetailValueRow: View {
    let title: String
    let value: String
    let systemImage: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    label
                    valueText
                        .padding(.leading, 46)
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    label
                    Spacer(minLength: 10)
                    valueText
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    private var label: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimaryForeground)
                .frame(width: 34, height: 34)
                .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var valueText: some View {
        Text(value)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(AppTheme.textPrimary)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct AnalyticsDetailRegionSection: View {
    let rows: [OwnerAnalyticsDetailRegionRowModel]

    var body: some View {
        OwnerAnalyticsSectionCard(
            title: AppStrings.OwnerAnalytics.detailRegionActivityTitle,
            subtitle: AppStrings.OwnerAnalytics.detailRegionActivitySubtitle
        ) {
            if rows.isEmpty {
                OwnerAnalyticsInlineEmptyState(
                    message: AppStrings.OwnerAnalytics.detailRegionActivityEmptyMessage
                )
            } else {
                VStack(spacing: AppTheme.eventsMetadataSpacing) {
                    ForEach(rows) { row in
                        AnalyticsDetailRegionRow(row: row)
                    }
                }
            }
        }
    }
}

private struct AnalyticsDetailRegionRow: View {
    let row: OwnerAnalyticsDetailRegionRowModel

    var body: some View {
        OwnerAnalyticsResponsiveValueRow(
            value: row.signalCount,
            label: AppStrings.OwnerAnalytics.trackedSignals
        ) {
            Image(systemName: "mappin.and.ellipse")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimaryForeground)
                .frame(width: 34, height: 34)
                .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(row.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                if !row.breakdownLines.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(row.breakdownLines, id: \.self) { line in
                            Text(line)
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.title)
        .accessibilityValue(([
            AppStrings.OwnerAnalytics.metricValue(
                AppStrings.OwnerAnalytics.trackedSignals,
                row.signalCount
            )
        ] + row.breakdownLines).joined(separator: ", "))
        .accessibilityIdentifier("ownerAnalytics.detail.region.\(row.id)")
    }
}

private struct AnalyticsOrganizationTopContentSection: View {
    let repository: OwnerAnalyticsRepository
    let selectedPeriod: AnalyticsPeriod
    let title: String
    let items: [AnalyticsOrganizationTopContentItem]
    let hasMoreItems: Bool
    let canCollapse: Bool
    let toggleExpansion: () -> Void

    var body: some View {
        OwnerAnalyticsSectionCard(title: title) {
            if items.isEmpty {
                OwnerAnalyticsInlineEmptyState(message: AppStrings.OwnerAnalytics.noDetailAnalyticsMessage)
            } else {
                VStack(spacing: AppTheme.eventsMetadataSpacing) {
                    ForEach(items) { item in
                        NavigationLink {
                            AnalyticsContentDetailView(
                                repository: repository,
                                contentID: item.contentID,
                                contentType: item.contentType,
                                initialTitle: item.analyticsDisplayTitle,
                                initialPeriod: selectedPeriod
                            )
                        } label: {
                            AnalyticsOrganizationTopContentRow(item: item)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("ownerAnalytics.detail.content.\(item.contentType.rawValue).\(item.contentID)")
                    }

                    if hasMoreItems || canCollapse {
                        OwnerAnalyticsShowMoreButton(
                            title: canCollapse ? AppStrings.OwnerAnalytics.showLess : AppStrings.OwnerAnalytics.showMore,
                            systemImage: canCollapse ? "chevron.up" : "chevron.down",
                            action: toggleExpansion
                        )
                    }
                }
            }
        }
    }
}

private struct AnalyticsOrganizationTopContentRow: View {
    let item: AnalyticsOrganizationTopContentItem
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        OwnerAnalyticsResponsiveValueRow(
            value: item.viewCount,
            label: AppStrings.OwnerAnalytics.views
        ) {
            Image(systemName: item.contentType.analyticsDetailSystemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimaryForeground)
                .frame(width: 34, height: 34)
                .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.analyticsDisplayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)

                if !item.analyticsMetadataText.isEmpty {
                    Text(item.analyticsMetadataText)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.analyticsDisplayTitle)
        .accessibilityValue([
            AppStrings.OwnerAnalytics.metricValue(AppStrings.OwnerAnalytics.views, item.viewCount),
            item.analyticsMetadataText
        ].filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityHint(AppStrings.OwnerAnalytics.openDetailHint)
    }
}

extension OwnerAnalyticsDetailMetricItem: OwnerAnalyticsMetricDisplayable {}

private extension AnalyticsPeriod {
    var analyticsDetailTitle: String {
        switch self {
        case .today:
            AppStrings.OwnerAnalytics.periodToday
        case .sevenDays:
            AppStrings.OwnerAnalytics.periodSevenDays
        case .thirtyDays:
            AppStrings.OwnerAnalytics.periodThirtyDays
        }
    }
}

private extension AnalyticsContentType {
    var analyticsDetailSystemImage: String {
        switch self {
        case .news:
            "newspaper"
        case .event:
            "calendar"
        case .organization:
            "building.2"
        }
    }
}

private extension AnalyticsOrganizationTopContentItem {
    var analyticsDisplayTitle: String {
        title.isAnalyticsUnavailableTitle(comparedTo: contentID) ? AppStrings.OwnerAnalytics.titleUnavailable : title
    }

    var analyticsMetadataText: String {
        var metadata = [contentType.analyticsTitle]
        if let federalState {
            metadata.append(AppStrings.FederalStates.title(for: federalState))
        } else if let regionScope {
            switch regionScope {
            case .austria:
                metadata.append(AppStrings.OwnerAnalytics.regionAustria)
            case .federalState:
                metadata.append(AppStrings.OwnerAnalytics.regionFederalState)
            case .city:
                metadata.append(AppStrings.OwnerAnalytics.regionCity)
            }
        }
        if let category, !category.isEmpty {
            metadata.append(OwnerAnalyticsFormatting.categoryTitle(
                rawValue: category,
                contentType: contentType
            ))
        }
        return metadata.joined(separator: " · ")
    }
}

#Preview {
    NavigationStack {
        AnalyticsOrganizationDetailView(
            repository: MockOwnerAnalyticsRepository(),
            organizationID: "org-ukrainian-center-vienna",
            initialTitle: "Ukrainian Community Center Vienna"
        )
    }
}
