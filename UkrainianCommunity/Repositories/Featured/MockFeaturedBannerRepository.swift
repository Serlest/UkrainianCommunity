import Foundation

final class MockFeaturedBannerRepository: FeaturedBannerRepository {
    private let validationService = FeaturedBannerValidationService()
    private var banners: [FeaturedBanner]

    init(banners: [FeaturedBanner] = MockFeaturedBannerRepository.defaultBanners()) {
        self.banners = banners
    }

    func fetchActiveBanners(
        for section: FeaturedBannerVisibleSection,
        federalState: AustrianFederalState?
    ) async throws -> [FeaturedBanner] {
        banners.activeFeaturedBanners(for: section, federalState: federalState)
    }

    func fetchAllBanners() async throws -> [FeaturedBanner] {
        try await fetchAllBannersForOwner()
    }

    func fetchAllBannersForOwner() async throws -> [FeaturedBanner] {
        banners.sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    func createBanner(_ banner: FeaturedBanner) async throws {
        try validationService.validate(banner)
        guard !banners.contains(where: { $0.id == banner.id }) else {
            throw AppError.validationFailed
        }
        banners.append(banner)
    }

    func updateBanner(_ banner: FeaturedBanner) async throws {
        try validationService.validate(banner)
        guard let index = banners.firstIndex(where: { $0.id == banner.id }) else {
            throw AppError.notFound
        }
        banners[index] = banner
    }

    func setBannerActive(id: String, isActive: Bool, updatedBy userID: String) async throws {
        guard let index = banners.firstIndex(where: { $0.id == id }) else {
            throw AppError.notFound
        }

        let existingBanner = banners[index]
        banners[index] = FeaturedBanner(
            id: existingBanner.id,
            title: existingBanner.title,
            subtitle: existingBanner.subtitle,
            imageURL: existingBanner.imageURL,
            actionType: existingBanner.actionType,
            actionTargetID: existingBanner.actionTargetID,
            externalURL: existingBanner.externalURL,
            regionScope: existingBanner.regionScope,
            federalState: existingBanner.federalState,
            visibleSections: existingBanner.visibleSections,
            displayDurationSeconds: existingBanner.displayDurationSeconds,
            priority: existingBanner.priority,
            isActive: isActive,
            startsAt: existingBanner.startsAt,
            endsAt: existingBanner.endsAt,
            createdAt: existingBanner.createdAt,
            updatedAt: Date(),
            createdBy: existingBanner.createdBy,
            updatedBy: userID
        )
    }

    func archiveBanner(id: String, updatedBy userID: String) async throws {
        try await setBannerActive(id: id, isActive: false, updatedBy: userID)
    }

    func deleteBanner(id: String) async throws {
        let originalCount = banners.count
        banners.removeAll { $0.id == id }
        if banners.count == originalCount {
            throw AppError.notFound
        }
    }

    private static func defaultBanners(now: Date = Date()) -> [FeaturedBanner] {
        [
            FeaturedBanner(
                id: "featured-emergency-support",
                title: "Emergency support contacts",
                subtitle: "Fast access to urgent help and community support resources.",
                imageURL: "https://example.com/featured/emergency-support.jpg",
                actionType: .emergency,
                regionScope: .allAustria,
                visibleSections: [.home, .guide],
                displayDurationSeconds: 5,
                priority: 90,
                startsAt: now.addingTimeInterval(-3_600),
                endsAt: now.addingTimeInterval(86_400),
                createdAt: now.addingTimeInterval(-7_200),
                updatedAt: now.addingTimeInterval(-3_600),
                createdBy: "mock-owner"
            ),
            FeaturedBanner(
                id: "featured-tirol-event",
                title: "Community meetup in Tirol",
                subtitle: "A regional gathering for families, volunteers, and local organizations.",
                imageURL: "https://example.com/featured/tirol-event.jpg",
                actionType: .event,
                actionTargetID: "mock-event-tirol-meetup",
                regionScope: .federalState,
                federalState: .tirol,
                visibleSections: [.home, .events],
                displayDurationSeconds: 7,
                priority: 60,
                startsAt: now.addingTimeInterval(-86_400),
                endsAt: now.addingTimeInterval(172_800),
                createdAt: now.addingTimeInterval(-172_800),
                updatedAt: now.addingTimeInterval(-7_200),
                createdBy: "mock-owner",
                updatedBy: "mock-editor"
            ),
            FeaturedBanner(
                id: "featured-partner-advice",
                title: "Partner legal advice hours",
                subtitle: "Book a consultation with a verified partner organization.",
                imageURL: "https://example.com/featured/partner-advice.jpg",
                actionType: .partner,
                externalURL: "https://example.com/legal-advice",
                regionScope: .allAustria,
                visibleSections: [.organizations, .guide],
                displayDurationSeconds: 6,
                priority: 40,
                startsAt: now.addingTimeInterval(-3_600),
                endsAt: now.addingTimeInterval(604_800),
                createdAt: now.addingTimeInterval(-86_400),
                updatedAt: now.addingTimeInterval(-3_600),
                createdBy: "mock-owner"
            ),
            FeaturedBanner(
                id: "featured-expired-announcement",
                title: "Expired paperwork deadline",
                subtitle: "A past announcement retained for management and reporting flows.",
                imageURL: "https://example.com/featured/expired-paperwork-deadline.jpg",
                actionType: .announcement,
                regionScope: .allAustria,
                visibleSections: [.home],
                displayDurationSeconds: 4,
                priority: 100,
                startsAt: now.addingTimeInterval(-604_800),
                endsAt: now.addingTimeInterval(-86_400),
                createdAt: now.addingTimeInterval(-691_200),
                updatedAt: now.addingTimeInterval(-604_800),
                createdBy: "mock-owner"
            ),
            FeaturedBanner(
                id: "featured-inactive-guide",
                title: "Inactive guide spotlight",
                subtitle: "A draft spotlight for upcoming practical guidance.",
                imageURL: "https://example.com/featured/inactive-guide.jpg",
                actionType: .guide,
                actionTargetID: "mock-guide-inactive",
                regionScope: .allAustria,
                visibleSections: [.guide],
                displayDurationSeconds: 6,
                priority: 80,
                isActive: false,
                createdAt: now.addingTimeInterval(-172_800),
                updatedAt: now.addingTimeInterval(-86_400),
                createdBy: "mock-owner"
            )
        ]
    }
}
