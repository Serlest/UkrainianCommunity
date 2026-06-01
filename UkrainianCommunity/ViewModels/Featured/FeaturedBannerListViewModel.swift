import Combine
import Foundation

nonisolated private let featuredBannerRefreshStaleInterval: TimeInterval = 300

@MainActor
final class FeaturedBannerListViewModel: ObservableObject {
    @Published private(set) var banners: [FeaturedBanner] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: AppError?

    private struct BannerQuery: Hashable {
        let section: FeaturedBannerVisibleSection
        let federalState: AustrianFederalState?
    }

    private struct CachedBanners {
        let banners: [FeaturedBanner]
        let lastLoadedAt: Date
    }

    private let repository: FeaturedBannerRepository
    private var cache: [BannerQuery: CachedBanners] = [:]
    private var loadTasks: [BannerQuery: Task<Void, Never>] = [:]
    private var loadingQueries = Set<BannerQuery>()
    private var currentQuery: BannerQuery?

    init(repository: FeaturedBannerRepository) {
        self.repository = repository
    }

    func loadIfNeeded(
        for section: FeaturedBannerVisibleSection,
        federalState: AustrianFederalState?
    ) async {
        let query = BannerQuery(section: section, federalState: federalState)
        currentQuery = query

        if let cached = cache[query] {
            applyCachedBanners(cached, for: query)
            return
        }

        await startLoad(for: query, force: false)
    }

    func refresh(
        for section: FeaturedBannerVisibleSection,
        federalState: AustrianFederalState?
    ) async {
        let query = BannerQuery(section: section, federalState: federalState)
        currentQuery = query
        await startLoad(for: query, force: true)
    }

    func refreshIfStale(
        for section: FeaturedBannerVisibleSection,
        federalState: AustrianFederalState?,
        maxAge: TimeInterval = featuredBannerRefreshStaleInterval
    ) async {
        let query = BannerQuery(section: section, federalState: federalState)
        currentQuery = query

        guard let cached = cache[query] else {
            await startLoad(for: query, force: false)
            return
        }

        applyCachedBanners(cached, for: query)
        guard Date().timeIntervalSince(cached.lastLoadedAt) > maxAge else { return }
        await startLoad(for: query, force: true)
    }

    func loadActiveBanners(
        for section: FeaturedBannerVisibleSection,
        federalState: AustrianFederalState?
    ) async {
        await refresh(for: section, federalState: federalState)
    }

    private func startLoad(for query: BannerQuery, force: Bool) async {
        if !force, let cached = cache[query] {
            applyCachedBanners(cached, for: query)
            return
        }

        if let loadTask = loadTasks[query] {
            await loadTask.value
            if let cached = cache[query] {
                applyCachedBanners(cached, for: query)
            }
            return
        }

        loadingQueries.insert(query)
        updateLoadingState()

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoad(for: query)
        }
        loadTasks[query] = task
        await task.value
        loadTasks[query] = nil
        loadingQueries.remove(query)
        updateLoadingState()
    }

    private func performLoad(for query: BannerQuery) async {
        do {
            let loadedBanners = try await repository.fetchActiveBanners(
                for: query.section,
                federalState: query.federalState
            )
            guard !Task.isCancelled else { return }

            let cached = CachedBanners(banners: loadedBanners, lastLoadedAt: Date())
            cache[query] = cached
            applyCachedBanners(cached, for: query)
            error = nil
        } catch is CancellationError {
        } catch let appError as AppError {
            guard !Task.isCancelled else { return }
            error = appError
        } catch {
            guard !Task.isCancelled else { return }
            self.error = .unknown
        }
    }

    private func applyCachedBanners(_ cached: CachedBanners, for query: BannerQuery) {
        guard currentQuery == query else { return }
        banners = cached.banners
    }

    private func updateLoadingState() {
        isLoading = !loadingQueries.isEmpty
    }
}
