import Combine
import Foundation

@MainActor
final class RegistrationLegalDocumentsViewModel: ObservableObject {
    @Published private(set) var terms: LegalDocument?
    @Published private(set) var privacy: LegalDocument?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let repository: LegalDocumentRepository
    private var loadGeneration = 0
    private var lastLoadedAt: Date?
    private var inFlight: Task<(terms: LegalDocument, privacy: LegalDocument), Error>?
    private let readTimeout: Duration

    init(repository: LegalDocumentRepository? = nil, readTimeout: Duration = .seconds(15)) {
        self.repository = repository ?? FirestoreLegalDocumentRepository()
        self.readTimeout = readTimeout
    }

    var isReady: Bool { terms != nil && privacy != nil && errorMessage == nil && !isLoading }

    var versionKey: String {
        [terms?.version ?? "", privacy?.version ?? ""].joined(separator: "|")
    }

    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil

        do {
            let documents = try await fetchLatest()
            guard generation == loadGeneration else { return }
            terms = documents.terms
            privacy = documents.privacy
            lastLoadedAt = Date()
        } catch {
            guard generation == loadGeneration else { return }
            lastLoadedAt = nil
            errorMessage = AuthFailureMessage.text(for: error, fallback: AppStrings.LegalCompliance.loadFailed)
        }

        if generation == loadGeneration { isLoading = false }
    }

    func refreshIfStale() async {
        guard !isLoading,
              lastLoadedAt.map({ Date().timeIntervalSince($0) < 5 * 60 }) != true else { return }
        await load()
    }

    func refreshForSubmission() async throws -> (terms: LegalDocument, privacy: LegalDocument) {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        errorMessage = nil
        do {
            let documents = try await fetchLatest()
            if generation == loadGeneration {
                terms = documents.terms
                privacy = documents.privacy
                lastLoadedAt = Date()
                isLoading = false
            }
            return documents
        } catch {
            if generation == loadGeneration {
                lastLoadedAt = nil
                errorMessage = AuthFailureMessage.text(for: error, fallback: AppStrings.LegalCompliance.loadFailed)
                isLoading = false
            }
            throw error
        }
    }

    private func fetchLatest() async throws -> (terms: LegalDocument, privacy: LegalDocument) {
        if let inFlight { return try await inFlight.value }
        let request = Task { @MainActor in
            async let termsDocument = RefreshRequest.run(timeout: readTimeout) {
                try await self.repository.fetchAuthoritativeActiveDocument(type: .terms)
            }
            async let privacyDocument = RefreshRequest.run(timeout: readTimeout) {
                try await self.repository.fetchAuthoritativeActiveDocument(type: .privacy)
            }
            let documents = try await (termsDocument, privacyDocument)
            guard documents.0.type == .terms, documents.1.type == .privacy,
                  documents.0.contentHash != nil, documents.1.contentHash != nil else {
                throw AppError.validationFailed
            }
            return (terms: documents.0, privacy: documents.1)
        }
        inFlight = request
        defer { inFlight = nil }
        return try await request.value
    }
}
