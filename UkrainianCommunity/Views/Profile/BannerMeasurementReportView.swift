import SwiftUI
import Charts
import UniformTypeIdentifiers

struct BannerMeasurementReportView: View {
    @EnvironmentObject private var authState: AuthState
    @State private var isExporting = false
    @State private var exportDocument = BannerMeasurementCSVDocument(text: "")
    @State private var exportError: String?
    @StateObject private var viewModel: BannerMeasurementReportViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let bannerTitle: String?

    init(repository: BannerMeasurementReportRepository = FirestoreBannerMeasurementReportRepository(),
         bannerRepository: FeaturedBannerRepository, initialPeriod: AnalyticsPeriod,
         bannerID: String? = nil, bannerTitle: String? = nil) {
        self.bannerTitle = bannerTitle
        _viewModel = StateObject(wrappedValue: BannerMeasurementReportViewModel(
            repository: repository, bannerRepository: bannerRepository, initialPeriod: initialPeriod, bannerID: bannerID))
    }

    var body: some View {
        ProfileDestinationLayout(title: bannerTitle ?? AppStrings.BannerReport.title,
            introSubtitle: AppStrings.BannerReport.subtitle,
            scrollsIntroSubtitle: dynamicTypeSize.isAccessibilitySize) {
            if PermissionService.isAppOwner(user: authState.user) {
            AnalyticsReportFilterMenu(title: AppStrings.OwnerAnalytics.periodPicker,
                selectedTitle: AnalyticsPresentationText.bannerPeriod(viewModel.selectedPeriod),
                identifier: "bannerReport.period") {
                Picker(AppStrings.OwnerAnalytics.periodPicker, selection: $viewModel.selectedPeriod) {
                    ForEach(AnalyticsPeriod.allCases) { Text(AnalyticsPresentationText.bannerPeriod($0)).tag($0) }
                }
            }
            Text(AnalyticsPresentationText.utcExplanation).font(.footnote).foregroundStyle(AppTheme.textSecondary).lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            content
            } else { InlineMessageCard(style: .info, message: AppStrings.FeaturedManagement.permissionError).accessibilityIdentifier("bannerReport.denied") }
        }
        .fileExporter(isPresented: $isExporting, document: exportDocument,
            contentType: .commaSeparatedText, defaultFilename: "UAC-banners-UTC") { result in
            if case .failure(let error) = result { exportError = error.localizedDescription }
        }
        .task(id: "\(authState.user?.id ?? "none")|\(PermissionService.isAppOwner(user: authState.user))|\(viewModel.queryKey)") {
            guard PermissionService.isAppOwner(user: authState.user) else { viewModel.resetSession(); return }
            await viewModel.loadIfNeeded()
        }
        .analyticsRefreshLifecycle {
            guard PermissionService.isAppOwner(user: authState.user) else { return }; await viewModel.loadIfNeeded()
        }
        .appRefreshable {
            guard PermissionService.isAppOwner(user: authState.user) else { return }; await viewModel.load()
        }
        .accessibilityIdentifier("screen.bannerReport")
    }

    @ViewBuilder private var content: some View {
        if viewModel.bannerUnavailable {
            EmptyStateCard(systemImage: "rectangle.slash", title: AppStrings.BannerReport.removed,
                           message: AppStrings.BannerReport.removedMessage)
        } else if let report = viewModel.visibleReport {
            if let error = viewModel.errorMessage {
                OwnerAnalyticsStaleDataBanner(message: AppStrings.OwnerAnalytics.staleData(error),
                    isRetrying: viewModel.isLoading) { Task { await viewModel.load() } }
            }
            OwnerAnalyticsFreshnessLabel(updatedAt: report.generatedAt)
            BannerAnalyticsMetricsView(totals: report.totals)
            filters
            if report.counts.isEmpty {
                Text(AppStrings.BannerReport.emptyMessage).font(.footnote).foregroundStyle(AppTheme.textSecondary)
            }
            BannerAnalyticsTrendView(report: report)
            OwnerAnalyticsSectionCard(title: AppStrings.BannerReport.byRegion) {
                Text(AppStrings.BannerReport.regionExplanation).font(.footnote).foregroundStyle(AppTheme.textSecondary)
                ForEach(report.regions.keys.sorted(), id: \.self) { region in
                    BannerAnalyticsValueRow(title: AppStrings.BannerReport.regionTitle(region), totals: report.regions[region]!)
                }
                if report.regions.isEmpty { Text(AppStrings.BannerReport.noMatchingData).foregroundStyle(AppTheme.textSecondary) }
            }
            OwnerAnalyticsSectionCard(title: AppStrings.BannerReport.bySection) {
                ForEach(FeaturedBannerVisibleSection.supportedCases) { section in
                    BannerAnalyticsValueRow(title: sectionTitle(section), totals: report.sections[section] ?? .init())
                }
            }
            if viewModel.fixedBannerID == nil {
                OwnerAnalyticsSectionCard(title: AppStrings.BannerReport.byBanner) {
                    ForEach(viewModel.displayedBanners) { banner in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(viewModel.title(for: banner.id)).font(.headline).foregroundStyle(AppTheme.textPrimary)
                            Text(banner.isActive ? AppStrings.FeaturedManagement.activeToggle : AppStrings.BannerReport.inactive)
                                .font(.caption).foregroundStyle(AppTheme.textSecondary)
                            if viewModel.selectedBannerID != nil {
                                BannerAnalyticsValueRow(title: AppStrings.BannerReport.total, totals: report.totals)
                            } else {
                                NavigationLink {
                                    BannerMeasurementReportView(repository: viewModel.repository,
                                        bannerRepository: viewModel.bannerRepository, initialPeriod: viewModel.selectedPeriod,
                                        bannerID: banner.id, bannerTitle: viewModel.title(for: banner.id))
                                } label: { Label(AppStrings.OwnerAnalytics.detailAnalyticsTitle, systemImage: "chart.bar") }
                                .tint(AppTheme.accentPrimaryForeground)
                            }
                        }.padding(.vertical, 6)
                    }
                    if viewModel.displayedBanners.isEmpty { Text(AppStrings.BannerReport.noCurrentBanners).foregroundStyle(AppTheme.textSecondary) }
                }
            }
            Button {
                guard let export = viewModel.exportReport() else { return }
                exportDocument = BannerMeasurementCSVDocument(text: export.csv(titles:
                    viewModel.bannerTitles.merging(["removed": AppStrings.BannerReport.removedTotals, "all": AppStrings.BannerReport.allBanners]) { a, _ in a }))
                isExporting = true
            } label: { Label(AppStrings.BannerReport.exportCSV, systemImage: "square.and.arrow.up") }
            .buttonStyle(.bordered).accessibilityIdentifier("bannerReport.export")
            if let exportError { InlineMessageCard(style: .error, message: exportError) }
            OwnerAnalyticsSectionCard(title: AppStrings.OwnerAnalytics.methodologyTitle) {
                Text(AppStrings.BannerReport.coverage)
                Text(AppStrings.BannerReport.ctrNote)
                Text(AppStrings.BannerReport.methodology)
                Text(AppStrings.BannerReport.historyNote)
            }.font(.footnote).foregroundStyle(AppTheme.textSecondary)
        } else if let error = viewModel.errorMessage {
            ErrorStateCard(title: AppStrings.OwnerAnalytics.loadFailedTitle, message: error,
                           retryTitle: AppStrings.Action.retry) { Task { await viewModel.load() } }
        } else { LoadingStateCard(title: AppStrings.OwnerAnalytics.loading) }
    }

    private var filters: some View {
        OwnerAnalyticsSectionCard(title: AppStrings.BannerReport.filters) {
            if viewModel.fixedBannerID == nil {
                AnalyticsReportFilterMenu(title: AppStrings.BannerReport.byBanner,
                    selectedTitle: viewModel.selectedBannerID.map { viewModel.title(for: $0) } ?? AppStrings.BannerReport.allBanners,
                    identifier: "bannerReport.bannerFilter") {
                    Picker(AppStrings.BannerReport.byBanner, selection: $viewModel.selectedBannerID) {
                        Text(AppStrings.BannerReport.allBanners).tag(String?.none)
                        ForEach(viewModel.availableBanners) { Text(viewModel.title(for: $0.id)).tag(Optional($0.id)) }
                    }
                }
            }
            AnalyticsReportFilterMenu(title: AppStrings.BannerReport.byRegion,
                selectedTitle: viewModel.selectedRegion.map { AppStrings.BannerReport.regionTitle($0) } ?? AppStrings.BannerReport.allRegions,
                identifier: "bannerReport.regionFilter") {
                Picker(AppStrings.BannerReport.byRegion, selection: $viewModel.selectedRegion) {
                    Text(AppStrings.BannerReport.allRegions).tag(String?.none)
                    ForEach((viewModel.report?.regions.keys.sorted() ?? []), id: \.self) { Text(AppStrings.BannerReport.regionTitle($0)).tag(Optional($0)) }
                }
            }
            AnalyticsReportFilterMenu(title: AppStrings.BannerReport.bySection,
                selectedTitle: viewModel.selectedSection.map { sectionTitle($0) } ?? AppStrings.BannerReport.allSections,
                identifier: "bannerReport.sectionFilter") {
                Picker(AppStrings.BannerReport.bySection, selection: $viewModel.selectedSection) {
                    Text(AppStrings.BannerReport.allSections).tag(FeaturedBannerVisibleSection?.none)
                    ForEach(FeaturedBannerVisibleSection.supportedCases) { Text(sectionTitle($0)).tag(Optional($0)) }
                }
            }
            if viewModel.selectedBannerID != nil || viewModel.selectedRegion != nil || viewModel.selectedSection != nil {
                Button(AppStrings.BannerReport.resetFilters) {
                    viewModel.selectedBannerID = nil; viewModel.selectedRegion = nil; viewModel.selectedSection = nil
                }
            }
        }.tint(AppTheme.accentPrimaryForeground)
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

struct BannerAnalyticsMetricsView: View {
    let totals: BannerMeasurementTotals
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        LazyVGrid(columns: dynamicTypeSize >= .xxLarge
                  ? [GridItem(.flexible(), alignment: .top)]
                  : [GridItem(.adaptive(minimum: 160), alignment: .top)], alignment: .leading, spacing: 12) {
            OwnerAnalyticsMetricTile(title: AppStrings.BannerReport.impressions, value: totals.impressions, systemImage: "eye")
            OwnerAnalyticsMetricTile(title: AppStrings.BannerReport.clicks, value: totals.clicks, systemImage: "hand.tap")
            OwnerAnalyticsMetricTile(title: AppStrings.BannerReport.ctr, value: 0, systemImage: "percent",
                formattedValue: totals.clickRate.map { OwnerAnalyticsFormatting.percent($0, locale: locale) } ?? "—")
        }
    }
}

struct BannerAnalyticsValueRow: View {
    let title: String
    let totals: BannerMeasurementTotals
    @Environment(\.locale) private var locale
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(AppTheme.textPrimary)
            Text(AppStrings.BannerReport.row(impressions: OwnerAnalyticsFormatting.integer(totals.impressions, locale: locale),
                clicks: OwnerAnalyticsFormatting.integer(totals.clicks, locale: locale),
                rate: totals.clickRate.map { OwnerAnalyticsFormatting.percent($0, locale: locale) } ?? "—"))
                .font(.footnote.monospacedDigit()).foregroundStyle(AppTheme.textSecondary)
        }.fixedSize(horizontal: false, vertical: true).accessibilityElement(children: .combine)
    }
}

struct BannerAnalyticsTrendView: View {
    let report: BannerMeasurementReport
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    private let utc = TimeZone(secondsFromGMT: 0)!

    private var dayLabelStyle: Date.FormatStyle {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return Date.FormatStyle(locale: locale, calendar: calendar, timeZone: utc)
            .day(.twoDigits).month(.twoDigits)
    }

    var body: some View {
        OwnerAnalyticsSectionCard(title: AppStrings.BannerReport.byDay) {
            Chart(report.timeline) { day in
                if let date = day.utcDate {
                    BarMark(x: .value("UTC", date, unit: .day), y: .value(AppStrings.BannerReport.impressions, day.totals.impressions))
                        .foregroundStyle(by: .value("metric", AppStrings.BannerReport.impressions))
                        .position(by: .value("metric", AppStrings.BannerReport.impressions))
                    BarMark(x: .value("UTC", date, unit: .day), y: .value(AppStrings.BannerReport.clicks, day.totals.clicks))
                        .foregroundStyle(by: .value("metric", AppStrings.BannerReport.clicks))
                        .position(by: .value("metric", AppStrings.BannerReport.clicks))
                }
            }
            .chartForegroundStyleScale([AppStrings.BannerReport.impressions: AppTheme.accentPrimaryForeground,
                                        AppStrings.BannerReport.clicks: AppTheme.accentSupportForeground])
            .chartLegend(.hidden)
            // A date scale lets Charts choose sparse ticks. Categorical string
            // days produced all30 labels on the physical phone despite sampled values.
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: dynamicTypeSize.isAccessibilitySize ? 2 : 4)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) { Text(date, format: dayLabelStyle).font(.caption2) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: dynamicTypeSize.isAccessibilitySize ? 2 : 5)) { _ in
                    AxisGridLine()
                    AxisValueLabel().font(.caption2)
                }
            }
            .environment(\.timeZone, utc)
            .environment(\.calendar, dayLabelStyle.calendar)
            .frame(height: dynamicTypeSize.isAccessibilitySize ? 240 : 160)
            .accessibilityLabel(AppStrings.BannerReport.byDay)
            legend
            DisclosureGroup(AppStrings.BannerReport.dailyDetails) {
                ForEach(report.days) { BannerAnalyticsValueRow(title: $0.id, totals: $0.totals) }
            }.tint(AppTheme.accentPrimaryForeground)
        }
    }

    private var legend: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        return layout {
            legendItem(AppStrings.BannerReport.impressions, color: AppTheme.accentPrimaryForeground)
            legendItem(AppStrings.BannerReport.clicks, color: AppTheme.accentSupportForeground)
        }
    }

    private func legendItem(_ title: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
            Text(title).font(.caption).foregroundStyle(AppTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct BannerAnalyticsOverviewSection: View {
    let period: AnalyticsPeriod
    var repository: BannerMeasurementReportRepository = FirestoreBannerMeasurementReportRepository()
    var refreshID = 0
    @State private var loadingKey: String?
    @State private var lastLoadedAt: Date?
    @State private var report: BannerMeasurementReport?
    @State private var error: String?
    @State private var isLoading = false
    @State private var loadID: UUID?
    var body: some View {
        OwnerAnalyticsSectionCard(title: AppStrings.BannerReport.title, subtitle: AnalyticsPresentationText.bannerPeriod(period)) {
            if let report, report.period == period {
                BannerAnalyticsMetricsView(totals: report.totals)
                Text(AnalyticsPresentationText.utcExplanation).font(.footnote).foregroundStyle(AppTheme.textSecondary).lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                Text(AppStrings.BannerReport.coverageShort).font(.footnote).foregroundStyle(AppTheme.textSecondary)
                OwnerAnalyticsFreshnessLabel(updatedAt: report.generatedAt)
                BannerAnalyticsTrendView(report: report)
            } else if isLoading { LoadingStateCard(title: nil) }
            if let error { Text(error).font(.footnote).foregroundStyle(AppTheme.textSecondary) }
            if error != nil { Button(AppStrings.Action.retry) { Task { await load() } } }
        }.task(id: "\(period.rawValue)|\(refreshID)") { await load() }
        .analyticsRefreshLifecycle(id: period.rawValue) {
            if report?.period != period || lastLoadedAt.map({ Date().timeIntervalSince($0) >= 60
                || FirestoreBannerMeasurementReportRepository.utcDayRange(period: .today, now: $0).0 != FirestoreBannerMeasurementReportRepository.utcDayRange(period: .today, now: Date()).0 }) ?? true {
                await load()
            }
        }
        .accessibilityIdentifier("ownerAnalytics.bannerOverview")
    }
    private func load() async {
        let key = "\(period.rawValue)|\(refreshID)"
        guard !isLoading || loadingKey != key else { return }
        loadingKey = key
        let selected = period
        let id = UUID()
        loadID = id
        isLoading = true; error = nil
        defer { if loadID == id { isLoading = false } }
        do {
            let loaded = try await RefreshRequest.run { try await repository.fetch(period: selected) }
            guard !Task.isCancelled, loadID == id else { return }
            lastLoadedAt = Date()
            report = loaded
        } catch { guard !Task.isCancelled, loadID == id else { return }; self.error = OwnerAnalyticsErrorPresentation.message(for: error) }
    }
}

struct RegisteredUserCountCard: View {
    var refreshID = 0
    var load: () async throws -> Int = RegisteredUserCountReader.fetch
    var dataUpdatedAt: () -> Date? = { nil }
    @State private var count: Int?
    @State private var updatedAt: Date?
    @State private var failed = false
    @State private var isLoading = false
    @State private var loadID: UUID?
    var body: some View {
        OwnerAnalyticsSectionCard(title: AnalyticsPresentationText.currentTitle) {
            if let count {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: "person.3").foregroundStyle(AppTheme.accentPrimaryForeground)
                    Text(count, format: .number).font(.largeTitle.bold()).monospacedDigit()
                        .foregroundStyle(AppTheme.textPrimary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(AppStrings.OwnerAnalytics.totalUsers)
                .accessibilityValue(String(count))
                .accessibilityIdentifier("ownerAnalytics.metric.person.3")
            }
            else { Text("—").font(.title2).foregroundStyle(AppTheme.textPrimary) }
            if let updatedAt { OwnerAnalyticsFreshnessLabel(updatedAt: updatedAt) }
            Text(failed ? AppStrings.OwnerAnalytics.loadFailedTitle : AnalyticsPresentationText.currentNote)
                .font(.footnote).foregroundStyle(AppTheme.textSecondary)
            if failed { Button(AppStrings.Action.retry) { Task { await reload() } } }
        }.task(id: refreshID) { await reload() }
        .analyticsRefreshLifecycle {
            if updatedAt.map({ Date().timeIntervalSince($0) >= 60 }) ?? true { await reload() }
        }
    }
    private func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let id = UUID()
        loadID = id
        do {
            let value = try await RefreshRequest.run { try await load() }
            guard !Task.isCancelled, loadID == id else { return }
            count = value; updatedAt = dataUpdatedAt() ?? Date(); failed = false
        } catch { guard !Task.isCancelled, loadID == id else { return }; failed = true }
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
