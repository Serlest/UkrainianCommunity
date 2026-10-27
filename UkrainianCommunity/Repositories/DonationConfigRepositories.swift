import Foundation

enum DonationConfigRepositories {
    static func makeDefault() -> DonationConfigRepository {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") { return UITestDonationConfigRepository.shared }
        #endif
        return FirestoreDonationConfigRepository()
    }
}

#if DEBUG && targetEnvironment(simulator)
@MainActor private final class UITestDonationConfigRepository: DonationConfigRepository {
    static let shared = UITestDonationConfigRepository()
    private var config = DonationConfig.defaults
    private let scenario = ProcessInfo.processInfo.environment["UITestProjectSupport"] ?? ""
    private var firstSave = true
    private var readAttempts = 0
    init() {
        if ["enabled", "conflict", "unconfirmed"].contains(scenario) {
            config.isEnabled = true; config.donationURL = "https://example.org/support19"
            config.sourceRevision = "fixture-v1"; config.updatedBy = "owner-1"
        }
    }
    func fetchDonationConfig() async throws -> DonationConfig? {
        if scenario == "readRecovery" {
            readAttempts += 1
            // Parent and editor may coalesce their first request. Keep both possible
            // initial reads offline; the bounded UI retry then returns real fixture data.
            try await Task.sleep(for: .seconds(2))
            if readAttempts <= 2 { throw AppError.network }
        }
        return config
    }
    func saveDonationConfig(_ input: DonationConfig, updatedBy userID: String) async throws -> DonationConfig {
        if scenario == "conflict", firstSave {
            firstSave = false; config.titleUK = "Серверна версія19"; config.sourceRevision = "fixture-v2"
            throw DonationConfigSaveError.conflict
        }
        guard input.sourceRevision == config.sourceRevision else { throw DonationConfigSaveError.conflict }
        config = input.normalizedForSaving(); config.sourceRevision = UUID().uuidString
        config.updatedBy = userID; config.updatedAt = Date()
        if scenario == "unconfirmed", firstSave { firstSave = false; throw DonationConfigSaveError.unconfirmed }
        return config
    }
}
#endif
