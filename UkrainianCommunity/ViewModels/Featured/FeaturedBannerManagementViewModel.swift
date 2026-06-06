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
            replaceBanner(banner.settingActive(isActive, updatedBy: trimmedUserID))
            error = nil
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
            replaceBanner(banner.settingActive(false, updatedBy: trimmedUserID))
            error = nil
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
            banners.removeAll { $0.id == banner.id }
            error = nil
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

    private func replaceBanner(_ banner: FeaturedBanner) {
        guard let index = banners.firstIndex(where: { $0.id == banner.id }) else { return }
        banners[index] = banner
        sortBanners()
    }

    private func sortBanners() {
        banners.sort { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }
}

private extension FeaturedBanner {
    func settingActive(_ isActive: Bool, updatedBy userID: String) -> FeaturedBanner {
        FeaturedBanner(
            id: id,
            internalName: internalName,
            title: title,
            subtitle: subtitle,
            imageURL: imageURL,
            actionType: actionType,
            actionTargetID: actionTargetID,
            externalURL: externalURL,
            regionScope: regionScope,
            federalState: federalState,
            visibleSections: visibleSections,
            displayDurationSeconds: displayDurationSeconds,
            priority: priority,
            isActive: isActive,
            startsAt: startsAt,
            endsAt: endsAt,
            createdAt: createdAt,
            updatedAt: Date(),
            createdBy: createdBy,
            updatedBy: userID
        )
    }
}
