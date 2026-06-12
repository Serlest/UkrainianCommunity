import Combine
import Foundation

nonisolated let featuredBannerRefreshStaleInterval: TimeInterval = 1_800

@MainActor
final class FeaturedBannerListViewModel: ObservableObject {
    @Published private(set) var banners: [FeaturedBanner] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: AppError?

    private let repository: FeaturedBannerRepository
    private let cache: FeaturedBannerCache
    private var loadTasks: [FeaturedBannerCache.Key: Task<Void, Never>] = [:]
    private var loadingQueries = Set<FeaturedBannerCache.Key>()
    private var currentQuery: FeaturedBannerCache.Key?

    init(repository: FeaturedBannerRepository, cache: FeaturedBannerCache) {
        self.repository = repository
        self.cache = cache
    }

    func loadIfNeeded(
        for section: FeaturedBannerVisibleSection,
        federalState: AustrianFederalState?
    ) async {
        let query = FeaturedBannerCache.Key(section: section, federalState: federalState)
        currentQuery = query

        if let cached = cache.entry(for: query, maxAge: featuredBannerRefreshStaleInterval) {
            applyCachedBanners(cached, for: query)
            return
        }

        await startLoad(for: query, force: false)
    }

    func refresh(
        for section: FeaturedBannerVisibleSection,
        federalState: AustrianFederalState?
    ) async {
        let query = FeaturedBannerCache.Key(section: section, federalState: federalState)
        currentQuery = query
        await startLoad(for: query, force: true)
    }

    func refreshIfStale(
        for section: FeaturedBannerVisibleSection,
        federalState: AustrianFederalState?,
        maxAge: TimeInterval = featuredBannerRefreshStaleInterval
    ) async {
        let query = FeaturedBannerCache.Key(section: section, federalState: federalState)
        currentQuery = query

        guard let cached = cache.entry(for: query, maxAge: maxAge) else {
            await startLoad(for: query, force: false, maxAge: maxAge)
            return
        }

        applyCachedBanners(cached, for: query)
    }

    func loadActiveBanners(
        for section: FeaturedBannerVisibleSection,
        federalState: AustrianFederalState?
    ) async {
        await refresh(for: section, federalState: federalState)
    }

    private func startLoad(
        for query: FeaturedBannerCache.Key,
        force: Bool,
        maxAge: TimeInterval = featuredBannerRefreshStaleInterval
    ) async {
        if !force, let cached = cache.entry(for: query, maxAge: maxAge) {
            applyCachedBanners(cached, for: query)
            return
        }

        if let loadTask = loadTasks[query] {
            await loadTask.value
            if let cached = cache.entry(for: query, maxAge: maxAge) {
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

    private func performLoad(for query: FeaturedBannerCache.Key) async {
        do {
            let loadedBanners = try await repository.fetchActiveBanners(
                for: query.section,
                federalState: query.federalState
            )
            guard !Task.isCancelled else { return }

            let cached = cache.store(loadedBanners, for: query)
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

    private func applyCachedBanners(_ cached: FeaturedBannerCache.Entry, for query: FeaturedBannerCache.Key) {
        guard currentQuery == query else { return }
        banners = cached.banners
    }

    private func updateLoadingState() {
        isLoading = !loadingQueries.isEmpty
    }
}
