import Combine
import FirebaseAuth
import Foundation

@MainActor
final class MyRegistrationsViewModel: ObservableObject {
    @Published private(set) var events: [Event]
    @Published private(set) var isLoading: Bool
    @Published private(set) var error: AppError?
    @Published private(set) var pendingCancellationIDs = Set<String>()

    @Published private(set) var hasMore = false
    @Published private(set) var isLoadingMore = false
    private var cursor: RegistrationPageCursor?
    private enum Override { case event(Event), removed }
    private var changesDuringLoad: [String: Override] = [:]

    private let repository: EventRepository
    private let registrationMutator: EventRegistrationMutating
    private let analyticsService: AnalyticsTracking
    private let localEventReminderService: LocalEventReminderServiceProtocol?
    private let reminderUserID: @MainActor () -> String?
    private var loadTask: Task<Void, Never>?
    private var cancellationTasks: [String: Task<EventRegistrationMutationResult, Error>] = [:]
    private var cancellationOperationIDs: [String: UUID] = [:]
    private var sessionGeneration = 0
    private var hasLoaded = false
    private var lastLoadedAt: Date?

    init(
        repository: EventRepository,
        localEventReminderService: LocalEventReminderServiceProtocol? = nil,
        registrationMutator: EventRegistrationMutating? = nil,
        analyticsService: AnalyticsTracking = NoopAnalyticsService(),
        reminderUserID: @escaping @MainActor () -> String? = { AuthService.shared.currentUser?.uid }
    ) {
        self.repository = repository
        self.localEventReminderService = localEventReminderService
        self.analyticsService = analyticsService
        self.reminderUserID = reminderUserID
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

    func loadMore() async {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        await startLoad(force: true, append: true)
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
        cursor = nil; hasMore = false; isLoadingMore = false; changesDuringLoad = [:]
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
        guard hasLoaded || isLoading || isLoadingMore else { return }

        for event in sharedEvents {
            if isLoading || isLoadingMore { changesDuringLoad[event.id] = event.registrationState == .registered ? .event(event) : .removed }
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

    func removeRegistrationEvent(id: String) {
        if isLoading || isLoadingMore { changesDuringLoad[id] = .removed }
        cancellationTasks[id]?.cancel()
        cancellationTasks[id] = nil
        cancellationOperationIDs[id] = nil
        pendingCancellationIDs.remove(id)
        events.removeAll { $0.id == id }
    }

    func cancelRegistration(for eventID: String) async {
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }
        guard !pendingCancellationIDs.contains(eventID) else { return }

        let event = events[index]
        let actionEvent = AppAnalyticsEvent.eventCancelRegistration(event: event, sourceScreen: "my_registrations")
        let actionCapture = analyticsService.actionCapture(for: actionEvent)
        let operationID = UUID()
        let generation = sessionGeneration
        pendingCancellationIDs.insert(eventID)
        cancellationOperationIDs[eventID] = operationID
        let task = Task<EventRegistrationMutationResult, Error> { [registrationMutator] in
            try await registrationMutator.cancelEventRegistration(id: eventID, actionCapture: actionCapture)
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

            if isLoading || isLoadingMore {
                changesDuringLoad[eventID] = result.registrationState == .registered ? .event(event.applyingRegistrationMutation(result)) : .removed
            }
            if result.registrationState == .registered {
                if let currentIndex = events.firstIndex(where: { $0.id == eventID }) {
                    events[currentIndex] = events[currentIndex].applyingRegistrationMutation(result)
                }
            } else {
                events.removeAll { $0.id == eventID }
            }
            if result.didChange {
                ActivityLogRecorder.recordEvent(event, actionType: .canceledEventRegistration)
                analyticsService.track(actionEvent, actionCapture: actionCapture)
            }
            if result.registrationState != .registered,
               let localEventReminderService, let userID = reminderUserID() {
                localEventReminderService.cancelEventReminder(eventID: eventID, userID: userID)
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

    private func startLoad(force: Bool, append: Bool = false) async {
        let generation = sessionGeneration
        guard force || !hasLoaded else { return }

        if let loadTask {
            await loadTask.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoad(generation: generation, append: append)
        }
        loadTask = task
        await task.value
        guard sessionGeneration == generation else { return }
        self.loadTask = nil
    }

    private func performLoad(generation: Int, append: Bool) async {
        guard sessionGeneration == generation else { return }
        isLoading = !append
        isLoadingMore = append
        changesDuringLoad = [:]
        let pageCursor = append ? cursor : nil
        defer {
            if sessionGeneration == generation {
                isLoading = false; isLoadingMore = false; changesDuringLoad = [:]
            }
        }

        do {
            let page = try await RefreshRequest.run { [repository] in try await repository.fetchRegisteredEventsPage(limit: 20, after: pageCursor) }
            guard !Task.isCancelled, sessionGeneration == generation else { return }
            var merged = Dictionary((append ? events : []).map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            for event in page.items { merged[event.id] = event }
            for (id, change) in changesDuringLoad {
                switch change {
                case .event(let event): merged[id] = event
                case .removed: merged[id] = nil
                }
            }
            events = Array(merged.values).sorted { $0.id < $1.id }
            cursor = page.nextCursor
            hasMore = page.hasMore && page.nextCursor != nil
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
