import Combine
import Foundation

@MainActor
final class LegalHistoryViewModel: ObservableObject {
    @Published private(set) var documents: [LegalDocument] = []
    @Published private(set) var reference: LegalDocument
    @Published private(set) var hasLoaded = false
    @Published private(set) var loading = false
    @Published private(set) var error = false
    @Published private(set) var accessDenied = false
    var accessScope: () -> LegalAccessScope? = { nil }
    private let type: LegalDocumentType
    private let repository: LegalDocumentRepository
    private var cursor: Int?
    private var revision = UUID()
    private var failedReset = true
    var canLoadMore: Bool { hasLoaded && cursor != nil && !accessDenied }

    init(type: LegalDocumentType, active: LegalDocument, repository: LegalDocumentRepository) {
        self.type = type; reference = active; self.repository = repository
    }
    func clear() {
        revision = UUID(); documents = []; cursor = nil
        hasLoaded = false; loading = false; error = false; accessDenied = false
    }
    func retry() async { await load(reset: failedReset) }
    func load(reset: Bool = true) async {
        guard reset || (canLoadMore && !loading) else { return }
        let scope = accessScope()
        guard scope?.allowsOwner != false else { clear(); accessDenied = true; return }
        let id = UUID(); revision = id; loading = true; error = false; accessDenied = false
        defer { if revision == id { loading = false } }
        let before = reset ? nil : cursor, repository = repository, type = type
        do {
            let page: LegalVersionPage
            if reset {
                async let current = RefreshRequest.run { try await repository.fetchAuthoritativeActiveDocument(type: type) }
                async let history = RefreshRequest.run { try await repository.fetchVersionHistory(type: type, before: before) }
                let result = try await (current, history)
                guard revision == id, !Task.isCancelled else { return }
                guard scope == accessScope() else { clear(); return }
                reference = result.0; page = result.1
            } else {
                page = try await RefreshRequest.run { try await repository.fetchVersionHistory(type: type, before: before) }
            }
            guard revision == id, !Task.isCancelled else { return }
            guard scope == accessScope() else { clear(); return }
            if let next = page.nextBefore, let before, next >= before { throw AppError.validationFailed }
            if reset { documents = page.documents }
            else { let known = Set(documents.map(\.version)); documents += page.documents.filter { !known.contains($0.version) } }
            cursor = page.nextBefore; hasLoaded = true
        } catch is CancellationError { return }
        catch {
            guard revision == id else { return }
            guard scope == accessScope() else { clear(); return }
            if LegalReadFailure(error).withdrawsPrivateData { clear(); accessDenied = true; return }
            failedReset = reset; self.error = true; hasLoaded = true
        }
    }
}
