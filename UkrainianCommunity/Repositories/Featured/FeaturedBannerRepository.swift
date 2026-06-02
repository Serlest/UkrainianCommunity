import Foundation

protocol FeaturedBannerRepository {
    func fetchActiveBanners(
        for section: FeaturedBannerVisibleSection,
        federalState: AustrianFederalState?
    ) async throws -> [FeaturedBanner]

    func fetchAllBanners() async throws -> [FeaturedBanner]
    func fetchAllBannersForOwner() async throws -> [FeaturedBanner]
    func createBanner(_ banner: FeaturedBanner) async throws
    func updateBanner(_ banner: FeaturedBanner) async throws
    func setBannerActive(id: String, isActive: Bool, updatedBy userID: String) async throws
    func archiveBanner(id: String, updatedBy userID: String) async throws
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
                && banner.visibleSections.contains(section)
                && banner.isVisible(on: now)
                && banner.matchesRegion(federalState)
        }
        // Higher priority numbers appear first. updatedAt breaks ties so recent edits win within the same priority.
        .sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }
}

private extension FeaturedBanner {
    func isVisible(on date: Date) -> Bool {
        let startsBeforeNow = startsAt.map { $0 <= date } ?? true
        let endsAfterNow = endsAt.map { $0 >= date } ?? true
        return startsBeforeNow && endsAfterNow
    }

    func matchesRegion(_ selectedFederalState: AustrianFederalState?) -> Bool {
        switch regionScope {
        case .allAustria:
            return true
        case .federalState:
            guard let federalState, let selectedFederalState else { return false }
            return federalState == selectedFederalState
        }
    }
}
