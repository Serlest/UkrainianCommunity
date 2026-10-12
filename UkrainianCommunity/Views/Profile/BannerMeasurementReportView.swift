import SwiftUI

struct BannerMeasurementReportView: View {
    @StateObject private var viewModel: BannerMeasurementReportViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    init(
        repository: BannerMeasurementReportRepository = FirestoreBannerMeasurementReportRepository(),
        bannerRepository: FeaturedBannerRepository,
        initialPeriod: AnalyticsPeriod
    ) {
        _viewModel = StateObject(wrappedValue: BannerMeasurementReportViewModel(
            repository: repository, bannerRepository: bannerRepository, initialPeriod: initialPeriod
        ))
    }

    var body: some View {
        ProfileDestinationLayout(
            title: AppStrings.BannerReport.title,
            introSubtitle: AppStrings.BannerReport.subtitle,
            scrollsIntroSubtitle: dynamicTypeSize.isAccessibilitySize
        ) {
            if dynamicTypeSize.isAccessibilitySize {
                periodPicker.pickerStyle(.menu)
            } else {
                periodPicker.pickerStyle(.segmented)
            }

            content
        }
        .task(id: viewModel.selectedPeriod) { await viewModel.loadIfNeeded() }
        .appRefreshable { await viewModel.load() }
        .accessibilityIdentifier("screen.bannerReport")
    }

    private var periodPicker: some View {
        Picker(AppStrings.OwnerAnalytics.periodPicker, selection: $viewModel.selectedPeriod) {
            ForEach(AnalyticsPeriod.allCases) { period in
                Text(period.analyticsTitle).tag(period)
            }
        }
        .accessibilityIdentifier("bannerReport.period")
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.report == nil {
            LoadingStateCard(title: AppStrings.OwnerAnalytics.loading)
        } else if let error = viewModel.errorMessage, viewModel.report == nil {
            ErrorStateCard(
                title: AppStrings.OwnerAnalytics.loadFailedTitle,
                message: error,
                retryTitle: AppStrings.OwnerAnalytics.retry
            ) {
                Task { await viewModel.load() }
            }
        } else if let report = viewModel.report {
            if let error = viewModel.errorMessage {
                OwnerAnalyticsStaleDataBanner(
                    message: AppStrings.OwnerAnalytics.staleData(error),
                    isRetrying: viewModel.isLoading
                ) { Task { await viewModel.load() } }
            }

            OwnerAnalyticsFreshnessLabel(updatedAt: report.generatedAt)

            if report.banners.isEmpty {
                EmptyStateCard(
                    systemImage: "rectangle.on.rectangle",
                    title: AppStrings.BannerReport.emptyTitle,
                    message: AppStrings.BannerReport.emptyMessage
                )
            } else {
                OwnerAnalyticsSectionCard(title: AppStrings.BannerReport.overview) {
                    HStack(spacing: 12) {
                        OwnerAnalyticsMetricTile(
                            title: AppStrings.BannerReport.impressions,
                            value: report.totals.impressions,
                            systemImage: "eye"
                        )
                        OwnerAnalyticsMetricTile(
                            title: AppStrings.BannerReport.clicks,
                            value: report.totals.clicks,
                            systemImage: "hand.tap"
                        )
                    }
                    rateText(report.totals)
                }

                OwnerAnalyticsSectionCard(title: AppStrings.BannerReport.bySection) {
                    ForEach(FeaturedBannerVisibleSection.supportedCases) { section in
                        if let totals = report.sections[section] {
                            row(title: sectionTitle(section), totals: totals)
                        }
                    }
                }

                OwnerAnalyticsSectionCard(title: AppStrings.BannerReport.byBanner) {
                    if viewModel.namesUnavailable {
                        OwnerAnalyticsPartialDataBanner(message: AppStrings.BannerReport.namesUnavailable)
                    }
                    ForEach(report.banners) { banner in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(viewModel.title(for: banner.id))
                                .font(.headline)
                                .foregroundStyle(AppTheme.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            if viewModel.title(for: banner.id) != banner.id {
                                Text(banner.id)
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .textSelection(.enabled)
                            }
                            row(title: AppStrings.BannerReport.total, totals: banner.totals)
                            ForEach(FeaturedBannerVisibleSection.supportedCases) { section in
                                if let totals = banner.sections[section] {
                                    row(title: sectionTitle(section), totals: totals)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                        if banner.id != report.banners.last?.id { Divider() }
                    }
                }
            }

            OwnerAnalyticsSectionCard(title: AppStrings.OwnerAnalytics.methodologyTitle) {
                Text(AppStrings.BannerReport.methodology)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(title: String, totals: BannerMeasurementTotals) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .foregroundStyle(AppTheme.textPrimary)
            Spacer(minLength: 8)
            Text(AppStrings.BannerReport.row(
                impressions: OwnerAnalyticsFormatting.integer(totals.impressions, locale: locale),
                clicks: OwnerAnalyticsFormatting.integer(totals.clicks, locale: locale),
                rate: formattedRate(totals)
            ))
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(AppTheme.textSecondary)
            .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    private func rateText(_ totals: BannerMeasurementTotals) -> some View {
        Text(AppStrings.BannerReport.rateExplanation(formattedRate(totals)))
            .font(.footnote)
            .foregroundStyle(AppTheme.textSecondary)
    }

    private func formattedRate(_ totals: BannerMeasurementTotals) -> String {
        totals.clickRate.map { OwnerAnalyticsFormatting.percent($0, locale: locale) } ?? "—"
    }

    private func sectionTitle(_ section: FeaturedBannerVisibleSection) -> String {
        switch section {
        case .home: AppStrings.BannerReport.home
        case .events: AppStrings.BannerReport.events
        case .organizations: AppStrings.BannerReport.organizations
        case .directory: AppStrings.BannerReport.directory
        case .unsupportedLegacy: section.rawValue
        }
    }
}
