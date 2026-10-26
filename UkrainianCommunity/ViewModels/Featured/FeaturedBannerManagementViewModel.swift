import Combine
import Foundation

@MainActor
final class FeaturedBannerManagementViewModel: ObservableObject {
    @Published private(set) var banners: [FeaturedBanner] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: AppError?
    @Published private(set) var updatingBannerIDs: Set<String> = []

    private let repository: FeaturedBannerRepository
    private let publicCache: FeaturedBannerCache?
    private var loadTask: Task<Void, Never>?
    private var loadID: UUID?
    private var hasLoaded = false
    private var session = UUID()
    private var mutationRevision = 0

    init(
        repository: FeaturedBannerRepository,
        publicCache: FeaturedBannerCache? = nil
    ) {
        self.repository = repository
        self.publicCache = publicCache
    }

    func resetSession() {
        session = UUID(); loadID = nil; loadTask?.cancel(); loadTask = nil; hasLoaded = false
        banners = []; error = nil; updatingBannerIDs = []; isLoading = false
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await startLoad(force: false)
    }

    func refresh() async {
        await startLoad(force: true)
    }

    func setActive(_ isActive: Bool, for banner: FeaturedBanner, updatedBy userID: String?) async {
        if banner.hasUnsupportedLegacyConfiguration {
            guard banner.isActive, !isActive else {
                error = .validationFailed
                return
            }
        }

        let trimmedUserID = userID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedUserID.isEmpty else {
            error = .permissionDenied
            return
        }

        guard !updatingBannerIDs.contains(banner.id) else { return }
        let generation = session
        mutationRevision += 1
        updatingBannerIDs.insert(banner.id)
        defer { if generation == session { updatingBannerIDs.remove(banner.id); mutationRevision += 1 } }

        do {
            try await repository.setBannerActive(id: banner.id, isActive: isActive, updatedBy: trimmedUserID)
            guard generation == session else { return }
            replaceBanner(banner.settingActive(isActive, updatedBy: trimmedUserID))
            invalidatePublicCache()
            AppContentChangeBus.postFeaturedBannersChanged()
            error = nil
        } catch let appError as AppError {
            guard generation == session else { return }
            error = appError
        } catch {
            guard generation == session else { return }
            self.error = .unknown
        }
    }

    func delete(_ banner: FeaturedBanner, requestedBy userID: String?) async {
        let trimmedUserID = userID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedUserID.isEmpty else {
            error = .permissionDenied
            return
        }

        guard !updatingBannerIDs.contains(banner.id) else { return }
        let generation = session
        mutationRevision += 1
        updatingBannerIDs.insert(banner.id)
        defer { if generation == session { updatingBannerIDs.remove(banner.id); mutationRevision += 1 } }

        do {
            try await repository.deleteBanner(id: banner.id)
            guard generation == session else { return }
            banners.removeAll { $0.id == banner.id }
            invalidatePublicCache()
            AppContentChangeBus.postFeaturedBannersChanged()
            error = nil
            // Storage cleanup is server-owned; another banner may still share this asset.
        } catch let appError as AppError {
            guard generation == session else { return }
            error = appError
        } catch {
            guard generation == session else { return }
            self.error = .unknown
        }
    }

    func invalidatePublicCache() {
        publicCache?.invalidateAll()
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
        let id = UUID(); loadID = id
        loadTask = task
        await task.value
        if loadID == id { loadTask = nil; loadID = nil }
    }

    private func performLoad() async {
        let generation = session
        let revision = mutationRevision
        isLoading = true
        defer { if generation == session { isLoading = false } }

        do {
            let loaded = try await RefreshRequest.run { [self] in try await repository.fetchAllBannersForOwner() }
            guard generation == session, revision == mutationRevision, !Task.isCancelled else { return }
            banners = loaded
            error = nil
            hasLoaded = true
        } catch is CancellationError {
        } catch let appError as AppError {
            guard !Task.isCancelled, generation == session else { return }
            error = appError
        } catch {
            guard !Task.isCancelled, generation == session else { return }
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
            return lhs.updatedAt == rhs.updatedAt ? lhs.id < rhs.id : lhs.updatedAt > rhs.updatedAt
        }
    }
}

private extension FeaturedBanner {
    func settingActive(_ isActive: Bool, updatedBy userID: String) -> FeaturedBanner {
        FeaturedBanner(
            id: id,
            internalName: internalName,
            localizations: localizations,
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
            updatedBy: userID,
            countdown: countdown,
            requiresDataRepair: requiresDataRepair
        )
    }
}
