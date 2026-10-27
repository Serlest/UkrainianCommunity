import Foundation
import FirebaseCore
import FirebaseFirestore
import Testing
@testable import UkrainianCommunity

private final class DonationConfigRepositoryStub: DonationConfigRepository {
    var config: DonationConfig?
    var loadError: AppError?
    var saveError: Error?
    var suspendNextRead = false
    var pendingRead: CheckedContinuation<DonationConfig?, Error>?
    var onChange: (@MainActor (DonationConfig) -> Void)?

    func fetchDonationConfig() async throws -> DonationConfig? {
        if let loadError { throw loadError }
        if suspendNextRead {
            suspendNextRead = false
            return try await withCheckedThrowingContinuation { pendingRead = $0 }
        }
        return config
    }

    func saveDonationConfig(_ config: DonationConfig, updatedBy userID: String) async throws -> DonationConfig {
        if let saveError { throw saveError }
        self.config = config
        return config
    }
    func listenDonationConfig(onChange: @escaping @MainActor (DonationConfig) -> Void,
                              onError: @escaping @MainActor (AppError) -> Void) -> AppRealtimeListener? {
        self.onChange = onChange
        return nil
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


extension DonationConfigTests {
    @Test func normalizedFieldsAndLimitsAreConsistent() {
        var config = configuredDonation()
        config.donationURL = " HTTPS://EXAMPLE.ORG:443/help "
        config.titleUK = "  Назва  "
        let normalized = config.normalizedForSaving()
        #expect(normalized.donationURL == "https://example.org/help")
        #expect(normalized.titleUK == "Назва")
        #expect(normalized.validationIssue == nil)
        #expect(DonationConfig.normalizedDonationURL(from: "https://bücher.at") == "https://xn--bcher-kva.at")
        config.titleDE = String(repeating: "x", count: 121)
        #expect(config.normalizedForSaving().validationIssue == .tooLong)
        config.titleDE = "   "
        #expect(config.normalizedForSaving().validationIssue == .missingText)
        for url in ["https://-bad.example.org", "https://127.0.0.1", "https://example.org:8080", "https://example.c2"] {
            #expect(DonationConfig.normalizedDonationURL(from: url) == nil)
        }
    }

    @Test func revisionPreservesNanosecondsAndIgnoresDictionaryOrder() {
        let a: [String: Any] = ["updatedAt": Timestamp(seconds: 100, nanoseconds: 1), "isEnabled": true]
        let b: [String: Any] = ["isEnabled": true, "updatedAt": Timestamp(seconds: 100, nanoseconds: 2)]
        #expect(FirestoreDonationConfigRepository.revision(a) != FirestoreDonationConfigRepository.revision(b))
        #expect(FirestoreDonationConfigRepository.revision(a) == FirestoreDonationConfigRepository.revision(["isEnabled": true, "updatedAt": Timestamp(seconds: 100, nanoseconds: 1)]))
    }

    @Test func conflictRetainsCurrentConfigAndRequiresReload() async {
        let repository = DonationConfigRepositoryStub()
        repository.config = configuredDonation()
        let model = DonationConfigViewModel(repository: repository)
        await model.load()
        let original = model.config
        var edited = original; edited.titleUK = "Локальна правка"
        repository.saveError = DonationConfigSaveError.conflict
        #expect(await model.save(edited, updatedBy: "owner") == false)
        #expect(model.config == original)
        #expect(model.needsReload)
        #expect(model.statusMessage == DonationEditorText.conflict)
        repository.saveError = nil
        await model.load()
        #expect(!model.needsReload)
    }

    @Test func lateReadCannotOverwriteConfirmedSave() async throws {
        let repository = DonationConfigRepositoryStub()
        repository.config = configuredDonation()
        let model = DonationConfigViewModel(repository: repository)
        await model.load()
        let original = model.config
        repository.suspendNextRead = true
        let read = Task { await model.load() }
        for _ in 0..<100 where repository.pendingRead == nil { await Task.yield() }
        let pending = try #require(repository.pendingRead)
        var edited = original; edited.titleUK = "Нова назва"
        #expect(await model.save(edited, updatedBy: "owner"))
        pending.resume(returning: original)
        await read.value
        #expect(model.config.titleUK == "Нова назва")
    }

    @Test func authoritativeListenerUpdatesPublicConfig() async {
        let repository = DonationConfigRepositoryStub()
        repository.config = configuredDonation()
        let model = DonationConfigViewModel(repository: repository)
        await model.loadIfNeeded()
        var disabled = model.config; disabled.isEnabled = false
        repository.onChange?(disabled)
        #expect(!model.config.isEnabled)
        #expect(model.hasLoadedData)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["UACDonationEmulator"] == "1"))
    func realFirestoreTransactionRejectsStaleDraftAndStreamsChanges() async throws {
        let options = FirebaseOptions(googleAppID: "1:1234567890:ios:abcdef123456", gcmSenderID: "1234567890")
        options.projectID = "demo-uac-donation-client"
        options.apiKey = "A" + String(repeating: "0", count: 38)
        let name = "DonationCAS-" + UUID().uuidString
        FirebaseApp.configure(name: name, options: options)
        let app = try #require(FirebaseApp.app(name: name))
        let database = Firestore.firestore(app: app)
        database.useEmulator(withHost: "127.0.0.1", port: 8080)
        let settings = database.settings
        settings.isSSLEnabled = false
        database.settings = settings
        try await database.collection(DonationConfig.collectionPath).document(DonationConfig.documentID).delete()
        let repository = FirestoreDonationConfigRepository(database: database, diagnostics: .none)
        let first = try await repository.saveDonationConfig(configuredDonation(), updatedBy: "owner")
        var newer = first; newer.titleUK = "З іншого пристрою"
        let second = try await repository.saveDonationConfig(newer, updatedBy: "owner")
        #expect(second.sourceRevision != first.sourceRevision)
        var stale = first; stale.titleUK = "Застаріла правка"
        do {
            _ = try await repository.saveDonationConfig(stale, updatedBy: "owner")
            Issue.record("A stale draft must not overwrite another device")
        } catch DonationConfigSaveError.conflict {} catch { Issue.record("Unexpected error: \(error)") }
        let read = try #require(try await repository.fetchDonationConfig())
        #expect(read.titleUK == newer.titleUK)
        var observed: DonationConfig?
        let listener = repository.listenDonationConfig(onChange: { observed = $0 }, onError: { _ in })
        var last = second; last.isEnabled = false
        _ = try await repository.saveDonationConfig(last, updatedBy: "owner")
        for _ in 0..<100 {
            if observed?.isEnabled == false { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(observed?.isEnabled == false)
        listener?.cancel()
    }
}
