import Combine
import Foundation

nonisolated let featuredBannerRefreshStaleInterval: TimeInterval = 1_800

@MainActor
final class FeaturedBannerListViewModel: ObservableObject {
    private struct LoadOperation {
        let id: UUID
        let task: Task<Void, Never>
    }

    @Published private(set) var banners: [FeaturedBanner] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: AppError?

    private let repository: FeaturedBannerRepository
    private let cache: FeaturedBannerCache
    private var loadOperations: [FeaturedBannerCache.Key: LoadOperation] = [:]
    private var loadingQueries = Set<FeaturedBannerCache.Key>()
    private var currentQuery: FeaturedBannerCache.Key?
    private var contentChangeCancellable: AnyCancellable?

    init(repository: FeaturedBannerRepository, cache: FeaturedBannerCache) {
        self.repository = repository
        self.cache = cache
        contentChangeCancellable = NotificationCenter.default
            .publisher(for: .featuredBannersChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.refreshCurrentQuery()
                }
            }
    }

    func loadIfNeeded(
        for section: FeaturedBannerVisibleSection,
        federalState: AustrianFederalState?
    ) async {
        let query = FeaturedBannerCache.Key(section: section, federalState: federalState)
        selectQuery(query)

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
        selectQuery(query)
        await startLoad(for: query, force: true)
    }

    func refreshIfStale(
        for section: FeaturedBannerVisibleSection,
        federalState: AustrianFederalState?,
        maxAge: TimeInterval = featuredBannerRefreshStaleInterval
    ) async {
        let query = FeaturedBannerCache.Key(section: section, federalState: federalState)
        selectQuery(query)

        guard let cached = cache.entry(for: query, maxAge: maxAge) else {
            await startLoad(for: query, force: false, maxAge: maxAge)
            return
        }

        applyCachedBanners(cached, for: query)
    }

    private func refreshCurrentQuery() async {
        guard let currentQuery else { return }
        await startLoad(for: currentQuery, force: true)
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

        if let existingOperation = loadOperations[query] {
            if force {
                existingOperation.task.cancel()
            } else {
                await existingOperation.task.value
                if let cached = cache.entry(for: query, maxAge: maxAge) {
                    applyCachedBanners(cached, for: query)
                }
                return
            }
        }

        loadingQueries.insert(query)
        updateLoadingState()

        let operationID = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoad(for: query)
        }
        loadOperations[query] = LoadOperation(id: operationID, task: task)
        await task.value

        // A forced refresh can replace an in-flight operation. Only the most
        // recent operation is allowed to clear the loading state for its key.
        guard loadOperations[query]?.id == operationID else { return }
        loadOperations[query] = nil
        loadingQueries.remove(query)
        updateLoadingState()
    }

    private func performLoad(for query: FeaturedBannerCache.Key) async {
        do {
            let loadedBanners = try await RefreshRequest.run { [self] in try await repository.fetchActiveBanners(
                for: query.section,
                federalState: query.federalState
            ) }
            guard !Task.isCancelled else { return }

            let cached = cache.store(loadedBanners, for: query)
            applyCachedBanners(cached, for: query)
            if currentQuery == query {
                error = nil
            }
        } catch is CancellationError {
        } catch let appError as AppError {
            guard !Task.isCancelled else { return }
            guard currentQuery == query else { return }
            error = appError
        } catch {
            guard !Task.isCancelled else { return }
            guard currentQuery == query else { return }
            self.error = .unknown
        }
    }

    private func selectQuery(_ query: FeaturedBannerCache.Key) {
        guard currentQuery != query else { return }
        currentQuery = query
        banners = []
        error = nil
    }

    private func applyCachedBanners(_ cached: FeaturedBannerCache.Entry, for query: FeaturedBannerCache.Key) {
        guard currentQuery == query else { return }
        banners = cached.banners
    }

    private func updateLoadingState() {
        isLoading = !loadingQueries.isEmpty
    }
}
