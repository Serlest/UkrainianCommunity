import Combine
import Foundation

@MainActor
final class MyRegistrationsViewModel: ObservableObject {
    @Published private(set) var events: [Event]
    @Published private(set) var isLoading: Bool
    @Published private(set) var error: AppError?
    @Published private(set) var pendingCancellationIDs = Set<String>()

    private let repository: EventRepository
    private let registrationMutator: EventRegistrationMutating
    private var loadTask: Task<Void, Never>?
    private var cancellationTasks: [String: Task<EventRegistrationMutationResult, Error>] = [:]
    private var cancellationOperationIDs: [String: UUID] = [:]
    private var sessionGeneration = 0
    private var hasLoaded = false
    private var lastLoadedAt: Date?

    init(
        repository: EventRepository,
        localEventReminderService: LocalEventReminderServiceProtocol? = nil,
        registrationMutator: EventRegistrationMutating? = nil
    ) {
        self.repository = repository
        if let registrationMutator {
            self.registrationMutator = registrationMutator
        } else {
            self.registrationMutator = repository
        }
        events = []
        isLoading = false
    }

    var registrationsCount: Int {
        events.count
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await startLoad(force: false)
    }

    func refresh() async {
        await startLoad(force: true)
    }

    func refreshIfStale(maxAge: TimeInterval = defaultRefreshStaleInterval) async {
        guard hasLoaded else {
            await loadIfNeeded()
            return
        }

        guard let lastLoadedAt else {
            await refresh()
            return
        }

        guard Date().timeIntervalSince(lastLoadedAt) > maxAge else { return }
        await refresh()
    }

    func resetForGuest() {
        invalidateCancellationOperations()
        loadTask?.cancel()
        loadTask = nil
        events = []
        isLoading = false
        error = nil
        hasLoaded = false
        lastLoadedAt = nil
    }

    func resetForAuthChange() {
        resetForGuest()
    }

    func synchronize(with sharedEvents: [Event]) {
        guard hasLoaded else { return }

        for event in sharedEvents {
            if event.registrationState == .registered {
                if let index = events.firstIndex(where: { $0.id == event.id }) {
                    events[index] = event
                } else {
                    events.append(event)
                }
            } else {
                events.removeAll { $0.id == event.id }
            }
        }

        events = events.deduplicatedEventsByID()
    }

    func cancelRegistration(for eventID: String) async {
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }
        guard !pendingCancellationIDs.contains(eventID) else { return }

        let event = events[index]
        let operationID = UUID()
        let generation = sessionGeneration
        pendingCancellationIDs.insert(eventID)
        cancellationOperationIDs[eventID] = operationID
        let task = Task<EventRegistrationMutationResult, Error> { [registrationMutator] in
            try await registrationMutator.cancelEventRegistration(id: eventID)
        }
        cancellationTasks[eventID] = task
        defer { finishCancellation(eventID, operationID: operationID, generation: generation) }

        do {
            let result = try await task.value
            guard result.eventID == eventID, result.registeredCount >= 0 else {
                throw EventRegistrationMutationError.unavailable
            }
            guard isCurrentCancellation(eventID, operationID: operationID, generation: generation),
                  !Task.isCancelled else { return }

            if result.registrationState == .registered {
                if let currentIndex = events.firstIndex(where: { $0.id == eventID }) {
                    events[currentIndex] = events[currentIndex].applyingRegistrationMutation(result)
                }
            } else {
                events.removeAll { $0.id == eventID }
            }
            if result.didChange {
                ActivityLogRecorder.recordEvent(event, actionType: .canceledEventRegistration)
            }
            error = nil
        } catch is CancellationError {
        } catch let mutationError as EventRegistrationMutationError {
            guard isCurrentCancellation(eventID, operationID: operationID, generation: generation) else { return }
            error = mutationError.appError
        } catch let appError as AppError {
            guard isCurrentCancellation(eventID, operationID: operationID, generation: generation) else { return }
            error = appError
        } catch {
            guard isCurrentCancellation(eventID, operationID: operationID, generation: generation) else { return }
            self.error = .unknown
        }
    }

    private func invalidateCancellationOperations() {
        sessionGeneration &+= 1
        cancellationTasks.values.forEach { $0.cancel() }
        cancellationTasks = [:]
        cancellationOperationIDs = [:]
        pendingCancellationIDs = []
    }

    private func finishCancellation(_ eventID: String, operationID: UUID, generation: Int) {
        guard isCurrentCancellation(eventID, operationID: operationID, generation: generation) else { return }
        pendingCancellationIDs.remove(eventID)
        cancellationOperationIDs[eventID] = nil
        cancellationTasks[eventID] = nil
    }

    private func isCurrentCancellation(_ eventID: String, operationID: UUID, generation: Int) -> Bool {
        sessionGeneration == generation && cancellationOperationIDs[eventID] == operationID
    }

    private func startLoad(force: Bool) async {
        let generation = sessionGeneration
        guard force || !hasLoaded else { return }

        if let loadTask {
            await loadTask.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoad(generation: generation)
        }
        loadTask = task
        await task.value
        guard sessionGeneration == generation else { return }
        self.loadTask = nil
    }

    private func performLoad(generation: Int) async {
        guard sessionGeneration == generation else { return }
        isLoading = true
        defer {
            if sessionGeneration == generation {
                isLoading = false
            }
        }

        do {
            let loadedEvents = try await repository.fetchRegisteredEvents()
            guard !Task.isCancelled, sessionGeneration == generation else { return }
            events = loadedEvents
            error = nil
            hasLoaded = true
            lastLoadedAt = Date()
        } catch is CancellationError {
        } catch let appError as AppError {
            guard !Task.isCancelled, sessionGeneration == generation else { return }
            error = appError
        } catch {
            guard !Task.isCancelled, sessionGeneration == generation else { return }
            self.error = .unknown
        }
    }
}
