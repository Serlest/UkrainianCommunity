import Combine
import Foundation

@MainActor
final class FeaturedBannerManagementViewModel: ObservableObject {
    @Published private(set) var banners: [FeaturedBanner] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: AppError?
    @Published private(set) var updatingBannerIDs: Set<String> = []

    private let repository: FeaturedBannerRepository
    private var loadTask: Task<Void, Never>?
    private var hasLoaded = false

    init(repository: FeaturedBannerRepository) {
        self.repository = repository
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await startLoad(force: false)
    }

    func loadBanners() async {
        await refresh()
    }

    func refresh() async {
        await startLoad(force: true)
    }

    func setActive(_ isActive: Bool, for banner: FeaturedBanner, updatedBy userID: String?) async {
        let trimmedUserID = userID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedUserID.isEmpty else {
            error = .permissionDenied
            return
        }

        updatingBannerIDs.insert(banner.id)
        defer { updatingBannerIDs.remove(banner.id) }

        do {
            try await repository.setBannerActive(id: banner.id, isActive: isActive, updatedBy: trimmedUserID)
            await refresh()
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    func archive(_ banner: FeaturedBanner, updatedBy userID: String?) async {
        let trimmedUserID = userID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedUserID.isEmpty else {
            error = .permissionDenied
            return
        }

        updatingBannerIDs.insert(banner.id)
        defer { updatingBannerIDs.remove(banner.id) }

        do {
            try await repository.archiveBanner(id: banner.id, updatedBy: trimmedUserID)
            await refresh()
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    func delete(_ banner: FeaturedBanner, requestedBy userID: String?) async {
        let trimmedUserID = userID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedUserID.isEmpty else {
            error = .permissionDenied
            return
        }

        updatingBannerIDs.insert(banner.id)
        defer { updatingBannerIDs.remove(banner.id) }

        do {
            try await repository.deleteBanner(id: banner.id)
            await refresh()
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    private func startLoad(force: Bool) async {
        guard force || !hasLoaded else { return }

        if let loadTask {
            await loadTask.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoad()
        }
        loadTask = task
        await task.value
        loadTask = nil
    }

    private func performLoad() async {
        isLoading = true
        defer { isLoading = false }

        do {
            banners = try await repository.fetchAllBannersForOwner()
            error = nil
            hasLoaded = true
        } catch is CancellationError {
        } catch let appError as AppError {
            guard !Task.isCancelled else { return }
            error = appError
        } catch {
            guard !Task.isCancelled else { return }
            self.error = .unknown
        }
    }
}
