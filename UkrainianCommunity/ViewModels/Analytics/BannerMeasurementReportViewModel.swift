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
        report?.filtered(bannerID: fixedBannerID ?? selectedBannerID, region: selectedRegion, section: selectedSection)
    }

    @Published var selectedPeriod: AnalyticsPeriod
    @Published private(set) var report: BannerMeasurementReport?
    @Published private(set) var bannerTitles: [String: String] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var namesUnavailable = false

    private let repository: BannerMeasurementReportRepository
    private let bannerRepository: FeaturedBannerRepository
    private var loadID: UUID?

    init(
        repository: BannerMeasurementReportRepository,
        bannerRepository: FeaturedBannerRepository,
        initialPeriod: AnalyticsPeriod,
        bannerID: String? = nil
    ) {
        fixedBannerID = bannerID
        self.repository = repository
        self.bannerRepository = bannerRepository
        selectedPeriod = initialPeriod
    }

    func loadIfNeeded() async {
        guard report?.period != selectedPeriod else { return }
        await load()
    }

    func load() async {
        let period = selectedPeriod
        let id = UUID()
        loadID = id
        isLoading = true
        errorMessage = nil
        if report?.period != period { report = nil }
        defer { if loadID == id { isLoading = false } }

        do {
            async let measurements = repository.fetch(period: period, bannerID: fixedBannerID)
            async let catalog = bannerRepository.fetchAllBannersForOwner()
            let (loaded, banners) = try await (measurements, catalog)
            guard !Task.isCancelled, selectedPeriod == period, loadID == id else { return }
            availableBanners = banners
            bannerTitles = Dictionary(uniqueKeysWithValues: banners.map { ($0.id, $0.internalName.flatMap { $0.isEmpty ? nil : $0 } ?? $0.localizedTitle) })
            bannerUnavailable = fixedBannerID.map { id in !banners.contains { $0.id == id } } ?? false
            report = bannerUnavailable ? nil : loaded
            namesUnavailable = false
            if let selectedBannerID, !banners.contains(where: { $0.id == selectedBannerID }) { self.selectedBannerID = nil }
            if let selectedRegion, loaded.regions[selectedRegion] == nil { self.selectedRegion = nil }
        } catch {
            guard !Task.isCancelled, selectedPeriod == period, loadID == id else { return }
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
                bannerID: currentIDs.contains(count.bannerID) ? count.bannerID : "removed",
                section: count.section, impressions: count.impressions, clicks: count.clicks,
                displayRegion: count.displayRegion)
        }
        return BannerMeasurementReport(period: visibleReport.period, counts: counts, generatedAt: visibleReport.generatedAt)
    }

    func title(for bannerID: String) -> String {
        bannerTitles[bannerID] ?? bannerID
    }
}
