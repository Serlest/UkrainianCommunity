import Foundation

struct FeaturedBannerSaveConflict: Error {}

protocol FeaturedBannerRepository {
    func fetchActiveBanners(
        for section: FeaturedBannerVisibleSection,
        federalState: AustrianFederalState?
    ) async throws -> [FeaturedBanner]

    func fetchAllBannersForOwner() async throws -> [FeaturedBanner]
    func saveBanner(_ banner: FeaturedBanner, isNew: Bool, expectedUpdatedAt: Date?, operationID: String) async throws
    func createBanner(_ banner: FeaturedBanner) async throws
    func updateBanner(_ banner: FeaturedBanner) async throws
    func setBannerActive(id: String, isActive: Bool, updatedBy userID: String) async throws
    func deleteBanner(id: String) async throws
}

extension FeaturedBannerRepository {
    func saveBanner(_ banner: FeaturedBanner, isNew: Bool, expectedUpdatedAt: Date?, operationID: String) async throws {
        if isNew { try await createBanner(banner) } else { try await updateBanner(banner) }
    }
}

extension Array where Element == FeaturedBanner {
    func eligibleFeaturedBanners(
        for section: FeaturedBannerVisibleSection,
        federalState: AustrianFederalState?
    ) -> [FeaturedBanner] {
        filter { banner in
            banner.isActive
                && banner.actionType.isSupported
                && !banner.requiresDataRepair
                && section.isSupported
                && banner.supportedVisibleSections.contains(section)
                && banner.matchesRegion(federalState)
        }
        .sortedByFeaturedBannerPriority()
    }

    func activeFeaturedBanners(
        for section: FeaturedBannerVisibleSection,
        federalState: AustrianFederalState?,
        now: Date = Date()
    ) -> [FeaturedBanner] {
        eligibleFeaturedBanners(for: section, federalState: federalState)
            .filter { $0.isVisible(on: now) }
    }

    private func sortedByFeaturedBannerPriority() -> [FeaturedBanner] {
        // Higher priority numbers appear first. updatedAt breaks ties so recent edits win within the same priority.
        sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }
            return lhs.updatedAt == rhs.updatedAt ? lhs.id < rhs.id : lhs.updatedAt > rhs.updatedAt
        }
    }
}
