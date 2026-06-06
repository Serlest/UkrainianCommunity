import Foundation

struct MockDonationConfigRepository: DonationConfigRepository {
    func fetchDonationConfig() async throws -> DonationConfig? {
        nil
    }

    func saveDonationConfig(_ config: DonationConfig, updatedBy userID: String) async throws {}
}
