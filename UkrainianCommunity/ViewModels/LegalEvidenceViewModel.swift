import Combine
import Foundation

@MainActor
final class LegalEvidenceViewModel: ObservableObject {
    @Published private(set) var events: [LegalEvidenceEvent] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published var searchText = ""
    @Published var filter: LegalEvidenceFilter = .all

    private let repository: LegalEvidenceRepository

    init(repository: LegalEvidenceRepository) {
        self.repository = repository
    }

    var filteredEvents: [LegalEvidenceEvent] {
        events.filter { filter.includes($0.eventType) && $0.matches(searchText) }
    }

    var hasLoadedContent: Bool { !events.isEmpty }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            events = try await repository.fetchRecentEvidence(limit: 200)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = AppStrings.LegalEvidence.loadFailed
        }
    }
}
