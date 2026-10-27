import Combine
import Foundation

@MainActor
final class LegalDocumentManagementViewModel: ObservableObject {
    @Published private(set) var states: [LegalDocumentType: LegalDocumentManagementState] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var failedTypes: Set<LegalDocumentType> = []
    @Published private(set) var accessDenied = false
    var accessScope: () -> LegalAccessScope? = { nil }
    private let repository: LegalDocumentRepository
    private var generation = UUID()
    private var flights: [LegalDocumentType: (UUID, Task<LegalDocumentManagementState, Error>)] = [:]

    init(repository: LegalDocumentRepository) { self.repository = repository }
    func clear() {
        generation = UUID()
        flights.values.forEach { $0.1.cancel() }; flights = [:]
        states = [:]; failedTypes = []; errorMessage = nil
        hasLoaded = false; isLoading = false; accessDenied = false
    }
    func load(types: [LegalDocumentType] = LegalDocumentType.allCases, force: Bool = false) async {
        let scope = accessScope(), epoch = generation
        guard scope?.allowsOwner != false else { clear(); accessDenied = true; return }
        accessDenied = false; errorMessage = nil
        var requests: [(LegalDocumentType, UUID, Task<LegalDocumentManagementState, Error>)] = []
        for type in types {
            if force { flights[type]?.1.cancel(); flights[type] = nil }
            let flight: (UUID, Task<LegalDocumentManagementState, Error>)
            if let existing = flights[type] { flight = existing }
            else {
                let id = UUID(), repository = repository
                let task = Task { @MainActor in
                    try await RefreshRequest.run { try await repository.fetchManagementState(type: type) }
                }
                flight = (id, task); flights[type] = flight
            }
            requests.append((type, flight.0, flight.1))
        }
        isLoading = !flights.isEmpty
        for (type, id, task) in requests {
            let result = await task.result
            guard epoch == generation else { return }
            guard scope == accessScope() else { clear(); return }
            guard flights[type]?.0 == id else { continue }
            flights[type] = nil
            switch result {
            case .success(let state): states[type] = state; failedTypes.remove(type)
            case .failure(let error):
                let kind = LegalReadFailure(error)
                if kind == .denied || kind == .session {
                    clear(); accessDenied = true; hasLoaded = true
                    errorMessage = AppStrings.LegalManagement.loadFailed
                    return
                }
                if !(error is CancellationError) { failedTypes.insert(type) }
            }
        }
        guard epoch == generation else { return }
        hasLoaded = true; isLoading = !flights.isEmpty
        errorMessage = states.isEmpty && !failedTypes.isEmpty ? AppStrings.LegalManagement.loadFailed : nil
    }
}
