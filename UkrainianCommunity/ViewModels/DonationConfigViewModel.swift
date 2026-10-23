import Combine
import Foundation

@MainActor
final class DonationConfigViewModel: ObservableObject {
    @Published private(set) var config: DonationConfig = .defaults
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var hasLoadedData = false
    @Published private(set) var needsReload = false
    @Published var statusMessage: String?
    @Published var statusStyle: InlineMessageStyle = .info

    private let repository: DonationConfigRepository
    private var hasLoaded = false
    private var revision: UInt = 0
    private var listener: AppRealtimeListener?
    private var pendingConfig: DonationConfig?

    init(repository: DonationConfigRepository) { self.repository = repository }

    func loadIfNeeded() async {
        startObserving()
        guard !hasLoaded else { return }
        await load()
    }

    private func startObserving() {
        guard listener == nil else { return }
        listener = repository.listenDonationConfig { [weak self] config in
            guard let self else { return }
            if isSaving { pendingConfig = config; return }
            revision &+= 1
            self.config = config
            hasLoaded = true; hasLoadedData = true; isLoading = false; needsReload = false
        } onError: { [weak self] _ in
            self?.statusStyle = .error
            self?.statusMessage = DonationLocalization.loadFailed()
        }
    }

    func load() async {
        guard !isLoading, !isSaving else { return }
        startObserving()
        revision &+= 1
        let request = revision
        isLoading = true
        statusMessage = nil
        defer { if request == revision { isLoading = false } }
        do {
            let loaded = try await RefreshRequest.run { [repository] in try await repository.fetchDonationConfig() } ?? .defaults
            guard request == revision, !Task.isCancelled else { return }
            config = loaded; hasLoaded = true; hasLoadedData = true; needsReload = false
        } catch is CancellationError { return }
        catch {
            guard request == revision else { return }
            statusStyle = .error; statusMessage = DonationLocalization.loadFailed()
        }
    }

    func save(_ input: DonationConfig, updatedBy userID: String?) async -> Bool {
        guard !isSaving, !needsReload, let userID, !userID.isEmpty else { return false }
        let normalized = input.normalizedForSaving()
        guard normalized.validationIssue == nil else { return false }
        revision &+= 1
        isSaving = true; isLoading = false; statusMessage = nil
        defer {
            isSaving = false
            if let pendingConfig, (pendingConfig.updatedAt ?? .distantPast) >= (config.updatedAt ?? .distantPast) {
                config = pendingConfig
            }
            pendingConfig = nil
        }
        do {
            let saved = try await repository.saveDonationConfig(normalized, updatedBy: userID)
            config = saved; hasLoaded = true; hasLoadedData = true
            statusStyle = .success; statusMessage = DonationLocalization.saveSucceeded()
            return true
        } catch DonationConfigSaveError.conflict {
            needsReload = true
            statusStyle = .error; statusMessage = DonationEditorText.conflict
        } catch DonationConfigSaveError.unconfirmed {
            needsReload = true
            statusStyle = .error; statusMessage = DonationEditorText.unconfirmed
        } catch {
            statusStyle = .error; statusMessage = DonationLocalization.saveFailed()
        }
        return false
    }
}
