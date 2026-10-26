#if DEBUG && targetEnvironment(simulator)
import SwiftUI

struct BannerStartupAuditHarness: View {
    @StateObject private var model: FeaturedBannerListViewModel
    private let cache: FeaturedBannerCache
    private let repository: BannerStartupAuditRepository
    @State private var seeded = false
    @State private var artworkReady = false
    init() {
        let id = ProcessInfo.processInfo.environment["UITestBannerStartupID"] ?? "isolated"
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BannerStartupAudit/" + id + "/catalog.json")
        let cache = FeaturedBannerCache(persistenceURL: url)
        let repo = BannerStartupAuditRepository()
        self.cache = cache
        self.repository = repo
        _model = StateObject(wrappedValue: FeaturedBannerListViewModel(repository: repo, cache: cache))
    }
    var body: some View {
        VStack(spacing: 16) {
            if ProcessInfo.processInfo.environment["UITestBannerStartupSeed"] == "1" {
                Text(seeded ? "Seed ready" : "Seeding").accessibilityIdentifier("bannerStartup.seed")
            } else {
                ForEach(model.banners) { banner in
                    FeaturedBannerCardView(banner: banner, onArtworkLoadStateChanged: { artworkReady = $0 })
                }
                Text(artworkReady ? "Artwork ready" : "Artwork pending").accessibilityIdentifier("bannerStartup.artwork")
                Text(model.isLoading ? "Network pending" : "Network complete").accessibilityIdentifier("bannerStartup.network")
                Button { repository.finish() } label: { Text(verbatim: "Return empty server response") }.accessibilityIdentifier("bannerStartup.finish")
            }
        }
        .padding().background(AppBackgroundView())
        .task {
            if ProcessInfo.processInfo.environment["UITestBannerStartupSeed"] == "1" {
                var banner = BannerAuditHarness14.fixtures()[0]
                banner = FeaturedBanner(id: banner.id, title: "Instant cached banner", imageURL: "http://127.0.0.1:1/unreachable.jpg", visibleSections: [.home], createdAt: banner.createdAt, updatedAt: banner.updatedAt, createdBy: "fixture", countdown: banner.countdown)
                _ = cache.store([banner], for: .init(section: .home, federalState: .tirol))
                if let data = BannerAuditHarness14.artwork.jpegData(compressionQuality: 0.85) {
                    let key = "\(banner.id)|\(banner.imageURL!)|\(banner.updatedAt.timeIntervalSince1970)"
                    await FeaturedBannerImageCache.shared.store(data, for: key)
                }
                await cache.flush()
                seeded = true
            } else {
                await model.loadIfNeeded(for: .home, federalState: .tirol)
            }
        }
    }
}
private final class BannerStartupAuditRepository: FeaturedBannerRepository {
    private var pending: CheckedContinuation<[FeaturedBanner], Error>?
    func fetchActiveBanners(for section: FeaturedBannerVisibleSection, federalState: AustrianFederalState?) async throws -> [FeaturedBanner] { try await withCheckedThrowingContinuation { pending = $0 } }
    func finish() { pending?.resume(returning: []); pending = nil }
    func fetchAllBannersForOwner() async throws -> [FeaturedBanner] { [] }
    func createBanner(_ banner: FeaturedBanner) async throws { throw AppError.permissionDenied }
    func updateBanner(_ banner: FeaturedBanner) async throws { throw AppError.permissionDenied }
    func setBannerActive(id: String, isActive: Bool, updatedBy userID: String) async throws { throw AppError.permissionDenied }
    func deleteBanner(id: String) async throws { throw AppError.permissionDenied }
}
#endif
