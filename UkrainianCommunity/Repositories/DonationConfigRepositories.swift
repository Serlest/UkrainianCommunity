import Foundation

enum DonationConfigRepositories {
    static func makeDefault() -> DonationConfigRepository {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            return UITestDonationConfigRepository.shared
        }
        #endif
        return FirestoreDonationConfigRepository()
    }
}

#if DEBUG && targetEnvironment(simulator)
@MainActor
private final class UITestDonationConfigRepository: DonationConfigRepository {
    static let shared = UITestDonationConfigRepository()
    private var config = DonationConfig.defaults
    func fetchDonationConfig() async throws -> DonationConfig? { config }
    func saveDonationConfig(_ config: DonationConfig, updatedBy userID: String) async throws -> DonationConfig {
        self.config = config.normalizedForSaving()
        return self.config
    }
}
#endif
