import Foundation
import Testing
@testable import UkrainianCommunity

private final class DonationConfigRepositoryStub: DonationConfigRepository {
    var config: DonationConfig?
    var loadError: AppError?

    func fetchDonationConfig() async throws -> DonationConfig? {
        if let loadError { throw loadError }
        return config
    }

    func saveDonationConfig(_ config: DonationConfig, updatedBy userID: String) async throws {
        self.config = config
    }
}

@MainActor
struct DonationConfigTests {
    @Test func failedInitialLoadDoesNotExposeDefaultConfigAsLoadedData() async {
        let repository = DonationConfigRepositoryStub()
        repository.loadError = .network
        let viewModel = DonationConfigViewModel(repository: repository)

        await viewModel.loadIfNeeded()

        #expect(viewModel.hasLoadedData == false)
        #expect(viewModel.statusMessage == DonationLocalization.loadFailed())
    }

    @Test func validConfigBecomesAvailableAfterRetry() async {
        let repository = DonationConfigRepositoryStub()
        repository.loadError = .network
        repository.config = configuredDonation()
        let viewModel = DonationConfigViewModel(repository: repository)

        await viewModel.load()
        repository.loadError = nil
        await viewModel.load()

        #expect(viewModel.hasLoadedData)
        #expect(viewModel.config.isEnabled)
        #expect(viewModel.config.validDonationURL?.host == "example.org")
    }

    @Test func donationURLNormalizationRejectsUnsafeSchemesAndCredentials() {
        #expect(DonationConfig.normalizedDonationURL(from: "example.org/help") == "https://example.org/help")
        #expect(DonationConfig.normalizedDonationURL(from: "http://example.org") == nil)
        #expect(DonationConfig.normalizedDonationURL(from: "https://user:password@example.org") == nil)
    }

    private func configuredDonation() -> DonationConfig {
        var config = DonationConfig.defaults
        config.isEnabled = true
        config.donationURL = "https://example.org/donate"
        return config
    }
}
