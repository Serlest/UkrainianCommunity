import Combine
import Foundation

@MainActor
final class DonationConfigViewModel: ObservableObject {
    @Published private(set) var config: DonationConfig = .defaults
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published var statusMessage: String?
    @Published var statusStyle: InlineMessageStyle = .info

    private let repository: DonationConfigRepository
    private var hasLoaded = false

    init(repository: DonationConfigRepository) {
        self.repository = repository
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await load()
    }

    func load() async {
        isLoading = true
        statusMessage = nil
        defer { isLoading = false }

        do {
            config = try await repository.fetchDonationConfig() ?? .defaults
            hasLoaded = true
        } catch {
            statusStyle = .error
            statusMessage = DonationLocalization.loadFailed()
        }
    }

    func save(_ config: DonationConfig, updatedBy userID: String?) async -> Bool {
        guard !isSaving, let userID else { return false }

        isSaving = true
        statusMessage = nil
        defer { isSaving = false }

        do {
            try await repository.saveDonationConfig(config, updatedBy: userID)
            self.config = try await repository.fetchDonationConfig() ?? config
            hasLoaded = true
            statusStyle = .success
            statusMessage = DonationLocalization.saveSucceeded()
            return true
        } catch {
            statusStyle = .error
            statusMessage = DonationLocalization.saveFailed()
            return false
        }
    }
}
