import Combine
import Foundation

@MainActor
final class FeaturedBannerListViewModel: ObservableObject {
    @Published private(set) var banners: [FeaturedBanner] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: AppError?

    private let repository: FeaturedBannerRepository

    init(repository: FeaturedBannerRepository) {
        self.repository = repository
    }

    func loadActiveBanners(
        for section: FeaturedBannerVisibleSection,
        federalState: AustrianFederalState?
    ) async {
        isLoading = true
        defer { isLoading = false }

        do {
            banners = try await repository.fetchActiveBanners(for: section, federalState: federalState)
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }
}
