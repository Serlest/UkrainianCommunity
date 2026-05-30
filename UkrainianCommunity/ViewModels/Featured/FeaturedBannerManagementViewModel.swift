import Combine
import Foundation

@MainActor
final class FeaturedBannerManagementViewModel: ObservableObject {
    @Published private(set) var banners: [FeaturedBanner] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: AppError?
    @Published private(set) var updatingBannerIDs: Set<String> = []

    private let repository: FeaturedBannerRepository

    init(repository: FeaturedBannerRepository) {
        self.repository = repository
    }

    func loadBanners() async {
        isLoading = true
        defer { isLoading = false }

        do {
            banners = try await repository.fetchAllBannersForOwner()
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    func refresh() async {
        await loadBanners()
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
}
