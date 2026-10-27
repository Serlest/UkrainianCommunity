import Combine
import Foundation

@MainActor
final class DonationConfigViewModel: ObservableObject {
    @Published private(set) var config: DonationConfig = .defaults
    @Published private(set) var isLoading = false
    @Published private(set) var hasAttemptedLoad = false
    @Published private(set) var isSaving = false
    @Published private(set) var hasLoadedData = false
    @Published private(set) var needsReload = false
    @Published var statusMessage: String?
    @Published var statusStyle: InlineMessageStyle = .info

    private enum MessageOrigin { case read, mutation }
    private var messageOrigin: MessageOrigin?
    private let repository: DonationConfigRepository
    private var revision: UInt = 0
    private var listener: AppRealtimeListener?
    private var listenerID = UUID()
    private var pendingConfig: DonationConfig?
    private var editorGeneration = UUID()
    private var loadTask: Task<Void, Never>?

    init(repository: DonationConfigRepository) { self.repository = repository }

    func loadIfNeeded() async {
        startObserving()
        guard !hasLoadedData else { return }
        await load()
    }

    /// A terminal listener error needs a new registration, not only a one-off read.
    private func startObserving() {
        guard listener == nil else { return }
        let id = UUID(); listenerID = id
        listener = repository.listenDonationConfig { [weak self] config in
            guard let self, listenerID == id else { return }
            if isSaving { pendingConfig = config; return }
            let completesRequestedRead = isLoading
            revision &+= 1
            self.config = config
            hasAttemptedLoad = true; hasLoadedData = true; isLoading = false
            if completesRequestedRead {
                needsReload = false; statusMessage = nil; messageOrigin = nil
            } else { clearReadMessage() }
        } onError: { [weak self] _ in
            guard let self, listenerID == id else { return }
            listener?.cancel(); listener = nil
            // A read-side failure must not erase a conflict/unconfirmed write warning.
            if messageOrigin != .mutation {
                messageOrigin = .read; statusStyle = .error
                statusMessage = DonationLocalization.loadFailed()
            }
        }
    }

    func load() async {
        if let loadTask { await loadTask.value; return }
        guard !isSaving else { return }
        let task = Task { await performLoad() }
        loadTask = task
        await task.value
        loadTask = nil
    }

    private func performLoad() async {
        guard !isLoading, !isSaving else { return }
        startObserving()
        revision &+= 1
        let request = revision
        hasAttemptedLoad = true; isLoading = true
        clearReadMessage()
        defer { if request == revision { isLoading = false } }
        do {
            let loaded = try await RefreshRequest.run { [repository] in try await repository.fetchDonationConfig() } ?? .defaults
            guard request == revision, !Task.isCancelled else { return }
            config = loaded; hasLoadedData = true; needsReload = false
            statusMessage = nil; messageOrigin = nil
        } catch is CancellationError { return }
        catch {
            guard request == revision else { return }
            if messageOrigin != .mutation {
                messageOrigin = .read; statusStyle = .error
                statusMessage = DonationLocalization.loadFailed()
            }
        }
    }

    func invalidateEditor() {
        editorGeneration = UUID()
        statusMessage = nil; messageOrigin = nil
        // Public configuration is not private; keep its confirmed value and listener.
        // An in-flight write still owns isSaving until its actual outcome is known.
    }

    func save(_ input: DonationConfig, updatedBy userID: String?,
              isCurrent: @escaping @MainActor () -> Bool = { true }) async -> Bool {
        guard !isSaving, !needsReload, let userID, !userID.isEmpty, isCurrent() else { return false }
        let normalized = input.normalizedForSaving()
        guard normalized.validationIssue == nil else { return false }
        let generation = editorGeneration
        revision &+= 1
        isSaving = true; isLoading = false; statusMessage = nil; messageOrigin = nil
        defer {
            isSaving = false
            if let pendingConfig, (pendingConfig.updatedAt ?? .distantPast) >= (config.updatedAt ?? .distantPast) {
                config = pendingConfig
            }
            pendingConfig = nil
        }
        do {
            let saved = try await repository.saveDonationConfig(normalized, updatedBy: userID)
            // Do not let an old session complete a new editor's confirmation/navigation.
            guard generation == editorGeneration, isCurrent() else { return false }
            config = saved; hasLoadedData = true
            messageOrigin = .mutation
            statusStyle = .success; statusMessage = DonationLocalization.saveSucceeded()
            return true
        } catch {
            guard generation == editorGeneration, isCurrent() else { return false }
            messageOrigin = .mutation; statusStyle = .error
            switch error {
            case DonationConfigSaveError.conflict:
                needsReload = true; statusMessage = DonationEditorText.conflict
            case DonationConfigSaveError.unconfirmed:
                needsReload = true; statusMessage = DonationEditorText.unconfirmed
            default: statusMessage = DonationLocalization.saveFailed()
            }
        }
        return false
    }

    private func clearReadMessage() {
        if messageOrigin == .read { statusMessage = nil; messageOrigin = nil }
    }
}
