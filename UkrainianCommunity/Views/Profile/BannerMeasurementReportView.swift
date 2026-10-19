import SwiftUI
import Charts
import UniformTypeIdentifiers

struct BannerMeasurementReportView: View {
    @State private var isExporting = false
    @State private var exportDocument = BannerMeasurementCSVDocument(text: "")
    @State private var exportError: String?
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
        .fileExporter(isPresented: $isExporting, document: exportDocument,
                      contentType: .commaSeparatedText, defaultFilename: "UAC-banners-UTC") { result in
            if case .failure(let error) = result { exportError = error.localizedDescription }
        }
        .task(id: viewModel.selectedPeriod) { await viewModel.loadIfNeeded() }
        .appRefreshable { await viewModel.load() }
        .accessibilityIdentifier("screen.bannerReport")
    }

    @ViewBuilder private var filters: some View {
        if let source = viewModel.report, !source.banners.isEmpty {
            OwnerAnalyticsSectionCard(title: AppStrings.BannerReport.filters) {
                Picker(AppStrings.BannerReport.byBanner, selection: $viewModel.selectedBannerID) {
                    Text(AppStrings.BannerReport.allBanners).tag(String?.none)
                    ForEach(source.banners) { banner in
                        Text(viewModel.title(for: banner.id)).tag(Optional(banner.id))
                    }
                }.tint(AppTheme.accentPrimaryForeground).accessibilityIdentifier("bannerReport.bannerFilter")
                Picker(AppStrings.BannerReport.byRegion, selection: $viewModel.selectedRegion) {
                    Text(AppStrings.BannerReport.allRegions).tag(String?.none)
                    ForEach(source.regions.keys.sorted(), id: \.self) { region in
                        Text(AppStrings.BannerReport.regionTitle(region)).tag(Optional(region))
                    }
                }.tint(AppTheme.accentPrimaryForeground).accessibilityIdentifier("bannerReport.regionFilter")
                Picker(AppStrings.BannerReport.bySection, selection: $viewModel.selectedSection) {
                    Text(AppStrings.BannerReport.allSections).tag(FeaturedBannerVisibleSection?.none)
                    ForEach(FeaturedBannerVisibleSection.supportedCases) { section in
                        Text(sectionTitle(section)).tag(Optional(section))
                    }
                }.tint(AppTheme.accentPrimaryForeground).accessibilityIdentifier("bannerReport.sectionFilter")
                if viewModel.selectedBannerID != nil || viewModel.selectedRegion != nil || viewModel.selectedSection != nil {
                    Button(AppStrings.BannerReport.resetFilters) {
                        viewModel.selectedBannerID = nil
                        viewModel.selectedRegion = nil
                        viewModel.selectedSection = nil
                    }
                }
            }.pickerStyle(.menu)
        }
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
        } else if let report = viewModel.visibleReport {
            if let error = viewModel.errorMessage {
                OwnerAnalyticsStaleDataBanner(
                    message: AppStrings.OwnerAnalytics.staleData(error),
                    isRetrying: viewModel.isLoading
                ) { Task { await viewModel.load() } }
            }

            OwnerAnalyticsFreshnessLabel(updatedAt: report.generatedAt)
            if let exportError { InlineMessageCard(style: .error, message: exportError) }


            if report.banners.isEmpty {
                filters
                EmptyStateCard(
                    systemImage: "rectangle.on.rectangle",
                    title: AppStrings.BannerReport.noMatchingData,
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

                filters
            if !report.banners.isEmpty {
                Button {
                    exportError = nil
                    exportDocument = BannerMeasurementCSVDocument(text: report.csv(titles: viewModel.bannerTitles))
                    isExporting = true
                } label: { Label(AppStrings.BannerReport.exportCSV, systemImage: "square.and.arrow.up").foregroundStyle(AppTheme.accentPrimaryForeground) }
                .buttonStyle(.bordered)
                .tint(AppTheme.accentPrimaryForeground)
                .accessibilityIdentifier("bannerReport.export")
            }

                OwnerAnalyticsSectionCard(title: AppStrings.BannerReport.bySection) {
                    ForEach(FeaturedBannerVisibleSection.supportedCases) { section in
                        if let totals = report.sections[section] {
                            row(title: sectionTitle(section), totals: totals)
                        }
                    }
                }

                OwnerAnalyticsSectionCard(title: AppStrings.BannerReport.byRegion) {
                    Text(AppStrings.BannerReport.regionExplanation)
                        .font(.footnote).foregroundStyle(AppTheme.textSecondary)
                    ForEach(report.regions.keys.sorted(), id: \.self) { region in
                        if let totals = report.regions[region] {
                            row(title: AppStrings.BannerReport.regionTitle(region), totals: totals)
                        }
                    }
                }

                OwnerAnalyticsSectionCard(title: AppStrings.BannerReport.byDay) {
                    Chart(report.timeline) { day in
                        BarMark(x: .value("UTC", day.id), y: .value(AppStrings.BannerReport.impressions, day.totals.impressions))
                            .foregroundStyle(by: .value(AppStrings.BannerReport.overview, AppStrings.BannerReport.impressions))
                            .position(by: .value(AppStrings.BannerReport.overview, AppStrings.BannerReport.impressions))
                        BarMark(x: .value("UTC", day.id), y: .value(AppStrings.BannerReport.clicks, day.totals.clicks))
                            .foregroundStyle(by: .value(AppStrings.BannerReport.overview, AppStrings.BannerReport.clicks))
                            .position(by: .value(AppStrings.BannerReport.overview, AppStrings.BannerReport.clicks))
                    }
                    .chartForegroundStyleScale([AppStrings.BannerReport.impressions: AppTheme.accentPrimaryForeground,
                                                AppStrings.BannerReport.clicks: AppTheme.accentSupportForeground])
                    .chartXAxis { AxisMarks(values: report.timeline.enumerated().compactMap { index, day in
                        index % max(1, report.timeline.count / 4) == 0 ? day.id : nil
                    }) { value in
                        AxisValueLabel { if let day = value.as(String.self) { Text(String(day.suffix(5))) } }
                    } }
                    .frame(height: 180)
                    .accessibilityLabel(AppStrings.BannerReport.byDay)
                    DisclosureGroup(AppStrings.BannerReport.dailyDetails) {
                        ForEach(report.days) { day in row(title: day.id, totals: day.totals) }
                    }.tint(AppTheme.accentPrimaryForeground)
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
                Text(AppStrings.BannerReport.coverage)
                    .font(.footnote).foregroundStyle(AppTheme.textSecondary)
                Text(AppStrings.BannerReport.ctrNote)
                    .font(.footnote).foregroundStyle(AppTheme.textSecondary)
                Text(AppStrings.BannerReport.methodology)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(title: String, totals: BannerMeasurementTotals) -> some View {
        ViewThatFits(in: .horizontal) {
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
          VStack(alignment: .leading, spacing: 4) {
              Text(title).foregroundStyle(AppTheme.textPrimary)
              Text(AppStrings.BannerReport.row(
                impressions: OwnerAnalyticsFormatting.integer(totals.impressions, locale: locale),
                clicks: OwnerAnalyticsFormatting.integer(totals.clicks, locale: locale), rate: formattedRate(totals)))
                  .foregroundStyle(AppTheme.textSecondary)
          }
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


struct BannerMeasurementCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(data: configuration.file.regularFileContents ?? Data(), encoding: .utf8) ?? ""
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
