import Combine
import Foundation

@MainActor
final class MyRegistrationsViewModel: ObservableObject {
    @Published private(set) var events: [Event]
    @Published private(set) var isLoading: Bool
    @Published private(set) var error: AppError?
    @Published private(set) var pendingCancellationIDs = Set<String>()

    private let repository: EventRepository
    private var loadTask: Task<Void, Never>?
    private var hasLoaded = false
    private var lastLoadedAt: Date?

    init(
        repository: EventRepository,
        localEventReminderService: LocalEventReminderServiceProtocol? = nil
    ) {
        self.repository = repository
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
        events = []
        error = nil
        hasLoaded = false
        lastLoadedAt = nil
        pendingCancellationIDs = []
    }

    func resetForAuthChange() {
        resetForGuest()
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
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
        pendingCancellationIDs.insert(eventID)
        defer { pendingCancellationIDs.remove(eventID) }

        do {
            try await repository.cancelEventRegistration(id: eventID)
            ActivityLogRecorder.recordEvent(event, actionType: .canceledEventRegistration)
            events.removeAll { $0.id == eventID }
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    private func startLoad(force: Bool) async {
        guard force || !hasLoaded else { return }

        if let loadTask {
            await loadTask.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoad()
        }
        loadTask = task
        await task.value
        self.loadTask = nil
    }

    private func performLoad() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let loadedEvents = try await repository.fetchRegisteredEvents()
            guard !Task.isCancelled else { return }
            events = loadedEvents
            error = nil
            hasLoaded = true
            lastLoadedAt = Date()
        } catch is CancellationError {
        } catch let appError as AppError {
            guard !Task.isCancelled else { return }
            error = appError
        } catch {
            guard !Task.isCancelled else { return }
            self.error = .unknown
        }
    }
}
