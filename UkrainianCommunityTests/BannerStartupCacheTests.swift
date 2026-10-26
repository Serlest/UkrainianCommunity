import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct BannerStartupCacheTests {
    private let key = FeaturedBannerCache.Key(section: .home, federalState: .tirol)
    private func location() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("catalog.json") }
    private func banner(_ id: String = "cached", endsAt: Date? = nil) -> FeaturedBanner {
        FeaturedBanner(id: id, title: "Cached banner", imageURL: "https://example.com/image.jpg", visibleSections: [.home], endsAt: endsAt, createdAt: .now, updatedAt: .now, createdBy: "public-fixture", countdown: FeaturedBannerCountdown(targetDate: .now.addingTimeInterval(3600), label: "Time", germanLabel: "Zeit", completion: .hideCountdown), textAppearance: .init(titleColorHex: "#FFFFFF", subtitleColorHex: "#FFD43B"))
    }
    @Test func catalogSurvivesNewCacheInstanceWithCountdownColorsAndQueryIsolation() async throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let original = FeaturedBannerCache(persistenceURL: url)
        let value = banner()
        _ = original.store([value], for: key); await original.flush()
        let restarted = FeaturedBannerCache(persistenceURL: url)
        await restarted.restore()
        #expect(restarted.entry(for: key, maxAge: 1800)?.banners == [value])
        #expect(restarted.requiresRevalidation(for: key))
        #expect(restarted.entry(for: .init(section: .events, federalState: .tirol), maxAge: 1800) == nil)
        #expect(restarted.entry(for: .init(section: .home, federalState: .wien), maxAge: 1800) == nil)
        _ = restarted.store([], for: key); await restarted.flush()
        let third = FeaturedBannerCache(persistenceURL: url); await third.restore()
        #expect(third.entry(for: key, maxAge: 1800)?.banners.isEmpty == true)
        restarted.invalidateAll(); await restarted.flush()
        let removed = FeaturedBannerCache(persistenceURL: url); await removed.restore()
        #expect(removed.entry(for: key, maxAge: 1800) == nil)
    }
    @Test func startupPublishesCachedBannerBeforeSlowNetworkAndReplacesItWithEmptyServerResult() async throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let old = FeaturedBannerCache(persistenceURL: url)
        _ = old.store([banner()], for: key); await old.flush()
        let cache = FeaturedBannerCache(persistenceURL: url)
        let repo = SuspendedBannerFeed()
        let vm = FeaturedBannerListViewModel(repository: repo, cache: cache)
        let task = Task { await vm.loadIfNeeded(for: key.section, federalState: key.federalState) }
        while repo.pending == nil { await Task.yield() }
        #expect(vm.banners.map(\.id) == ["cached"])
        #expect(vm.isLoading)
        repo.finish(.success([])); await task.value
        #expect(vm.banners.isEmpty)
        #expect(vm.hasResolvedCurrentQuery)
        #expect(!vm.isLoading)
        await cache.flush()
        let restart = FeaturedBannerCache(persistenceURL: url); await restart.restore()
        #expect(restart.entry(for: key, maxAge: 1800)?.banners.isEmpty == true)
    }
    @Test func offlineFailureRetainsCachedContentButNeverDisplaysExpiredBanner() async throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let cache = FeaturedBannerCache(persistenceURL: url)
        _ = cache.store([banner(), banner("expired", endsAt: .now.addingTimeInterval(-1))], for: key); await cache.flush()
        let repo = SuspendedBannerFeed(), restarted = FeaturedBannerCache(persistenceURL: url)
        let vm = FeaturedBannerListViewModel(repository: repo, cache: restarted)
        let task = Task { await vm.loadIfNeeded(for: key.section, federalState: key.federalState) }
        while repo.pending == nil { await Task.yield() }
        #expect(vm.banners.map(\.id) == ["cached"])
        repo.finish(.failure(AppError.network)); await task.value
        #expect(vm.banners.map(\.id) == ["cached"])
    }
    @Test func overAgeFutureDatedAndCorruptCatalogsAreIgnored() async throws {
        let url = location(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let start = Date()
        let writer = FeaturedBannerCache(persistenceURL: url, now: { start })
        _ = writer.store([banner()], for: key); await writer.flush()
        let stale = FeaturedBannerCache(persistenceURL: url, now: { start.addingTimeInterval(86_401) }); await stale.restore()
        #expect(stale.entry(for: key, maxAge: 1_000_000) == nil)
        let future = FeaturedBannerCache(persistenceURL: url, now: { start.addingTimeInterval(-120) }); await future.restore()
        #expect(future.entry(for: key, maxAge: 1_000_000) == nil)
        try Data("broken".utf8).write(to: url)
        let corrupt = FeaturedBannerCache(persistenceURL: url); await corrupt.restore()
        #expect(corrupt.entry(for: key, maxAge: 1800) == nil)
    }
    @Test func artworkSurvivesRestartUsesRevisionAndEnforcesBudgetAndExpiry() async throws {
        let directory = location().deletingLastPathComponent(); defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FeaturedBannerImageCache(directory: directory, byteLimit: 100, maximumAge: 60)
        await cache.store(Data(repeating: 1, count: 70), for: "url|revision1")
        let restarted = FeaturedBannerImageCache(directory: directory, byteLimit: 100, maximumAge: 60)
        #expect(await restarted.data(for: "url|revision1") == Data(repeating: 1, count: 70))
        #expect(await restarted.data(for: "url|revision2") == nil)
        #expect(await restarted.data(for: "url|revision1", now: .now.addingTimeInterval(120)) == nil)
        await restarted.store(Data(repeating: 2, count: 70), for: "url|revision2")
        #expect(await restarted.data(for: "url|revision1") == nil)
        #expect(await restarted.data(for: "url|revision2") != nil)
        await restarted.store(Data(repeating: 3, count: 101), for: "too-large")
        #expect(await restarted.data(for: "too-large") == nil)
    }
}

@MainActor
private final class SuspendedBannerFeed: FeaturedBannerRepository {
    var pending: CheckedContinuation<[FeaturedBanner], Error>?
    func fetchActiveBanners(for section: FeaturedBannerVisibleSection, federalState: AustrianFederalState?) async throws -> [FeaturedBanner] { try await withCheckedThrowingContinuation { pending = $0 } }
    func finish(_ result: Result<[FeaturedBanner], Error>) { pending?.resume(with: result); pending = nil }
    func fetchAllBannersForOwner() async throws -> [FeaturedBanner] { [] }
    func createBanner(_ banner: FeaturedBanner) async throws { throw AppError.permissionDenied }
    func updateBanner(_ banner: FeaturedBanner) async throws { throw AppError.permissionDenied }
    func setBannerActive(id: String, isActive: Bool, updatedBy userID: String) async throws { throw AppError.permissionDenied }
    func deleteBanner(id: String) async throws { throw AppError.permissionDenied }
}
