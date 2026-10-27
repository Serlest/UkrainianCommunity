import Combine
import Foundation

@MainActor
final class BannerMeasurementReportViewModel: ObservableObject {
    let fixedBannerID: String?
    @Published private(set) var availableBanners: [FeaturedBanner] = []
    @Published private(set) var bannerUnavailable = false
    @Published var selectedBannerID: String?
    @Published var selectedRegion: String?
    @Published var selectedSection: FeaturedBannerVisibleSection?
    var visibleReport: BannerMeasurementReport? {
        guard let report, report.period == selectedPeriod, loadedBannerID == effectiveBannerID else { return nil }
        return report.filtered(bannerID: effectiveBannerID, region: selectedRegion, section: selectedSection)
    }

    @Published var selectedPeriod: AnalyticsPeriod
    @Published private(set) var report: BannerMeasurementReport?
    @Published private(set) var bannerTitles: [String: String] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var namesUnavailable = false

    let repository: BannerMeasurementReportRepository
    let bannerRepository: FeaturedBannerRepository
    private var loadingQueryKey: String?
    private var loadID: UUID?
    private var loadedBannerID: String?
    private let now: () -> Date
    private let cacheTTL: TimeInterval
    private var loadedAt: Date?
    var effectiveBannerID: String? { fixedBannerID ?? selectedBannerID }
    var queryKey: String { "\(selectedPeriod.rawValue)|\(effectiveBannerID ?? "all")" }

    init(
        repository: BannerMeasurementReportRepository,
        bannerRepository: FeaturedBannerRepository,
        initialPeriod: AnalyticsPeriod,
        bannerID: String? = nil,
        cacheTTL: TimeInterval = 60, now: @escaping () -> Date = Date.init
    ) {
        self.now = now
        self.cacheTTL = cacheTTL
        fixedBannerID = bannerID
        self.repository = repository
        self.bannerRepository = bannerRepository
        selectedPeriod = initialPeriod
    }

    func resetSession() {
        loadID = nil; loadingQueryKey = nil; loadedAt = nil; loadedBannerID = nil
        report = nil; bannerTitles = [:]; availableBanners = []; bannerUnavailable = false
        namesUnavailable = false; errorMessage = nil; isLoading = false
        selectedBannerID = nil; selectedRegion = nil; selectedSection = nil
    }

    func loadIfNeeded() async {
        guard !isLoading || loadingQueryKey != queryKey else { return }
        if report?.period == selectedPeriod, loadedBannerID == effectiveBannerID,
           let loadedAt, now().timeIntervalSince(loadedAt) < cacheTTL,
           FirestoreBannerMeasurementReportRepository.utcDayRange(period: .today, now: loadedAt).0
                == FirestoreBannerMeasurementReportRepository.utcDayRange(period: .today, now: now()).0 { return }
        await load()
    }

    func load() async {
        loadingQueryKey = queryKey
        let period = selectedPeriod
        let bannerID = effectiveBannerID
        let id = UUID()
        loadID = id
        isLoading = true
        errorMessage = nil
        if report?.period != period || loadedBannerID != bannerID { report = nil }
        defer { if loadID == id { isLoading = false } }

        do {
            async let measurements = repository.fetch(period: period, bannerID: bannerID)
            async let catalog = bannerRepository.fetchAllBannersForOwner()
            let (loaded, banners) = try await (measurements, catalog)
            guard !Task.isCancelled, selectedPeriod == period, effectiveBannerID == bannerID, loadID == id else { return }
            loadedAt = now()
            loadedBannerID = bannerID
            availableBanners = banners
            bannerTitles = Dictionary(uniqueKeysWithValues: banners.map { ($0.id, $0.internalName.flatMap { $0.isEmpty ? nil : $0 } ?? $0.localizedTitle) })
            bannerUnavailable = fixedBannerID.map { id in !banners.contains { $0.id == id } } ?? false
            report = bannerUnavailable ? nil : loaded
            namesUnavailable = false
            if let selectedBannerID, !banners.contains(where: { $0.id == selectedBannerID }) { self.selectedBannerID = nil }
            if let selectedRegion, loaded.regions[selectedRegion] == nil { self.selectedRegion = nil }
        } catch {
            guard !Task.isCancelled, selectedPeriod == period, effectiveBannerID == bannerID, loadID == id else { return }
            errorMessage = OwnerAnalyticsErrorPresentation.message(for: error)
        }
    }

    var displayedBanners: [FeaturedBanner] {
        availableBanners.filter { banner in
            guard let id = fixedBannerID ?? selectedBannerID else { return true }
            return banner.id == id
        }
    }

    func exportReport() -> BannerMeasurementReport? {
        guard let visibleReport else { return nil }
        let currentIDs = Set(availableBanners.map(\.id))
        let counts = visibleReport.counts.map { count in
            BannerMeasurementDailyCount(day: count.day,
                bannerID: count.bannerID == "all" || currentIDs.contains(count.bannerID) ? count.bannerID : "removed",
                section: count.section, impressions: count.impressions, clicks: count.clicks,
                displayRegion: count.displayRegion)
        }
        return BannerMeasurementReport(period: visibleReport.period, counts: counts, generatedAt: visibleReport.generatedAt, periodAnchor: visibleReport.periodAnchor)
    }

    func title(for bannerID: String) -> String {
        bannerTitles[bannerID] ?? bannerID
    }
}
