import Combine
import Foundation

@MainActor
final class BannerMeasurementReportViewModel: ObservableObject {
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
        initialPeriod: AnalyticsPeriod
    ) {
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
            let loaded = try await repository.fetch(period: period)
            guard selectedPeriod == period, loadID == id else { return }
            report = loaded
            bannerTitles = [:]
            namesUnavailable = false
            if loaded.banners.isEmpty {
                return
            }
            do {
                let banners = try await bannerRepository.fetchAllBannersForOwner()
                guard selectedPeriod == period, loadID == id else { return }
                bannerTitles = Dictionary(uniqueKeysWithValues: banners.map { banner in
                    (banner.id, banner.internalName.flatMap { $0.isEmpty ? nil : $0 } ?? banner.localizedTitle)
                })
                namesUnavailable = false
            } catch {
                guard selectedPeriod == period, loadID == id else { return }
                bannerTitles = [:]
                namesUnavailable = true
            }
        } catch {
            guard selectedPeriod == period, loadID == id else { return }
            errorMessage = error.localizedDescription
        }
    }

    func title(for bannerID: String) -> String {
        bannerTitles[bannerID] ?? bannerID
    }
}
