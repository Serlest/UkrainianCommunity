import Foundation

protocol FeaturedBannerRepository {
    func fetchActiveBanners(
        for section: FeaturedBannerVisibleSection,
        federalState: AustrianFederalState?
    ) async throws -> [FeaturedBanner]

    func fetchAllBannersForOwner() async throws -> [FeaturedBanner]
    func createBanner(_ banner: FeaturedBanner) async throws
    func updateBanner(_ banner: FeaturedBanner) async throws
    func setBannerActive(id: String, isActive: Bool, updatedBy userID: String) async throws
    func deleteBanner(id: String) async throws
}

extension Array where Element == FeaturedBanner {
    func activeFeaturedBanners(
        for section: FeaturedBannerVisibleSection,
        federalState: AustrianFederalState?,
        now: Date = Date()
    ) -> [FeaturedBanner] {
        filter { banner in
            banner.isActive
                && banner.actionType.isSupported
                && !banner.requiresDataRepair
                && section.isSupported
                && banner.supportedVisibleSections.contains(section)
                && banner.isVisible(on: now)
                && banner.matchesRegion(federalState)
        }
        // Higher priority numbers appear first. updatedAt breaks ties so recent edits win within the same priority.
        .sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }
            return lhs.updatedAt == rhs.updatedAt ? lhs.id < rhs.id : lhs.updatedAt > rhs.updatedAt
        }
    }
}
