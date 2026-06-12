import SwiftUI

struct AnalyticsContentDetailView: View {
    @StateObject private var viewModel: AnalyticsContentDetailViewModel

    init(
        repository: OwnerAnalyticsRepository,
        contentID: String,
        contentType: AnalyticsContentType,
        initialTitle: String
    ) {
        _viewModel = StateObject(wrappedValue: AnalyticsContentDetailViewModel(
            repository: repository,
            contentID: contentID,
            contentType: contentType,
            initialTitle: initialTitle
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
        .task { await viewModel.loadIfNeeded() }
        .refreshable { await viewModel.load() }
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
                set: { period in Task { await viewModel.selectPeriod(period) } }
            )
        )
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
                title: AppStrings.OwnerAnalytics.noDetailAnalyticsTitle,
                message: AppStrings.OwnerAnalytics.noDetailAnalyticsMessage
            )
        } else {
            OwnerAnalyticsSectionCard(title: AppStrings.OwnerAnalytics.overviewTitle) {
                AnalyticsDetailMetricGrid(items: viewModel.metricItems)

                if let conversionRateText = viewModel.conversionRateText {
                    AnalyticsDetailValueRow(
                        title: AppStrings.OwnerAnalytics.conversionRate,
                        value: conversionRateText,
                        systemImage: "arrow.triangle.branch"
                    )
                }
            }

            AnalyticsDetailRegionSection(rows: viewModel.regionRows)
        }
    }
}

struct AnalyticsOrganizationDetailView: View {
    @StateObject private var viewModel: AnalyticsOrganizationDetailViewModel

    init(
        repository: OwnerAnalyticsRepository,
        organizationID: String,
        initialTitle: String
    ) {
        _viewModel = StateObject(wrappedValue: AnalyticsOrganizationDetailViewModel(
            repository: repository,
            organizationID: organizationID,
            initialTitle: initialTitle
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
        .task { await viewModel.loadIfNeeded() }
        .refreshable { await viewModel.load() }
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
                set: { period in Task { await viewModel.selectPeriod(period) } }
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
                title: AppStrings.OwnerAnalytics.noDetailAnalyticsTitle,
                message: AppStrings.OwnerAnalytics.noDetailAnalyticsMessage
            )
        } else if viewModel.hasActiveSearch && !viewModel.hasSearchResults {
            EmptyStateCard(
                systemImage: "magnifyingglass",
                title: AppStrings.OwnerAnalytics.searchEmptyTitle,
                message: AppStrings.OwnerAnalytics.searchEmptyMessage
            )
        } else {
            OwnerAnalyticsSectionCard(title: AppStrings.OwnerAnalytics.overviewTitle) {
                AnalyticsDetailMetricGrid(items: viewModel.metricItems)
            }

            AnalyticsOrganizationTopContentSection(
                title: AppStrings.OwnerAnalytics.topNews,
                items: viewModel.topNewsItems,
                hasMoreItems: viewModel.hasMoreTopNews,
                canCollapse: viewModel.canCollapseTopNews
            ) {
                viewModel.toggleTopNewsExpansion()
            }

            AnalyticsOrganizationTopContentSection(
                title: AppStrings.OwnerAnalytics.topEvents,
                items: viewModel.topEventsItems,
                hasMoreItems: viewModel.hasMoreTopEvents,
                canCollapse: viewModel.canCollapseTopEvents
            ) {
                viewModel.toggleTopEventsExpansion()
            }

            AnalyticsDetailRegionSection(rows: viewModel.regionRows)
        }
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

    var body: some View {
        Picker(AppStrings.OwnerAnalytics.periodPicker, selection: $selectedPeriod) {
            ForEach(AnalyticsPeriod.allCases) { period in
                Text(period.analyticsDetailTitle).tag(period)
            }
        }
        .pickerStyle(.segmented)
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

                TextField(AppStrings.OwnerAnalytics.searchPlaceholder, text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.subheadline)
                    .focused($isSearchFocused)
                    .submitLabel(.search)
                    .onSubmit { isSearchFocused = false }

                if !text.isEmpty {
                    Button {
                        text = ""
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
}

private struct AnalyticsDetailMetricGrid: View {
    let items: [OwnerAnalyticsDetailMetricItem]

    var body: some View {
        LazyVGrid(columns: columns, spacing: AppTheme.eventsMetadataSpacing) {
            ForEach(items) { item in
                OwnerAnalyticsMetricTile(
                    title: item.title,
                    value: item.value,
                    systemImage: item.systemImage
                )
            }
        }
    }

    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: AppTheme.eventsMetadataSpacing),
            GridItem(.flexible(), spacing: AppTheme.eventsMetadataSpacing)
        ]
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

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(width: 34, height: 34)
                .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)

            Spacer(minLength: 10)

            Text(value)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)
                .monospacedDigit()
        }
        .padding(.vertical, 6)
    }
}

private struct AnalyticsDetailRegionSection: View {
    let rows: [OwnerAnalyticsDetailRegionRowModel]

    var body: some View {
        OwnerAnalyticsSectionCard(
            title: AppStrings.OwnerAnalytics.regionActivityTitle,
            subtitle: AppStrings.OwnerAnalytics.regionActivitySubtitle
        ) {
            if rows.isEmpty {
                OwnerAnalyticsInlineEmptyState(message: AppStrings.OwnerAnalytics.regionActivityEmptyMessage)
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
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "mappin.and.ellipse")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(width: 34, height: 34)
                .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(row.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)

                if !row.breakdownLines.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(row.breakdownLines, id: \.self) { line in
                            Text(line)
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 2) {
                Text(row.total.formatted())
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)

                Text(AppStrings.OwnerAnalytics.views)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct AnalyticsOrganizationTopContentSection: View {
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
                        AnalyticsOrganizationTopContentRow(item: item)
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

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.contentType.analyticsDetailSystemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(width: 34, height: 34)
                .background(AppTheme.accentPrimarySoft, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(item.analyticsDisplayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if !item.analyticsMetadataText.isEmpty {
                    Text(item.analyticsMetadataText)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 2) {
                Text(item.primaryCount.formatted())
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)

                Text(AppStrings.OwnerAnalytics.views)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 6)
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
        case .guideArticle:
            "book.closed"
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
            metadata.append(category)
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
