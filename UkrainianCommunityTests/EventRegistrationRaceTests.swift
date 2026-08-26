import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct EventRegistrationRaceTests {
    @Test func forcedEventDetailRefreshPreservesOtherCachedPages() async {
        let repository = ControlledEventRepository()
        let model = EventsViewModel(repository: repository)
        let old = makeEvent(id: "older-page", registeredCount: 1)
        let other = makeEvent(id: "another-page")
        model.events = [other, old]
        repository.events = [makeEvent(id: old.id, registeredCount: 8)]
        #expect(await model.loadEventIfNeeded(eventID: old.id, force: true))
        #expect(model.events.map(\.id) == [other.id, old.id])
        #expect(model.event(for: old.id)?.registeredCount == 8)
    }

    @Test func registrationRejectsDoubleTapAndUsesAuthoritativeResponse() async {
        let repository = ControlledEventRepository()
        let viewModel = EventsViewModel(repository: repository)
        let event = makeEvent(id: "registration-double-tap", registeredCount: 3)
        viewModel.events = [event]

        viewModel.toggleRegistration(for: event.id)
        #expect(viewModel.pendingEventRegistrationIDs == [event.id])
        viewModel.toggleRegistration(for: event.id)

        #expect(await eventually { repository.registrationRequestCount == 1 })
        #expect(repository.registrationRequestCount == 1)
        repository.completeRegistrationRequest(
            1,
            result: mutationResult(eventID: event.id, state: .registered, count: 8)
        )

        #expect(await eventually { viewModel.pendingEventRegistrationIDs.isEmpty })
        #expect(viewModel.event(for: event.id)?.registrationState == .registered)
        #expect(viewModel.event(for: event.id)?.registeredCount == 8)
    }

    @Test func registrationResolvesCurrentIndexAfterFeedReorder() async {
        let repository = ControlledEventRepository()
        let viewModel = EventsViewModel(repository: repository)
        let target = makeEvent(id: "registration-target")
        let other = makeEvent(id: "registration-other", registeredCount: 17)
        viewModel.events = [target, other]

        viewModel.toggleRegistration(for: target.id)
        #expect(await eventually { repository.registrationRequestCount == 1 })
        viewModel.events = [other, target]
        repository.completeRegistrationRequest(
            1,
            result: mutationResult(eventID: target.id, state: .registered, count: 4)
        )

        #expect(await eventually { viewModel.pendingEventRegistrationIDs.isEmpty })
        #expect(viewModel.events.map(\.id) == [other.id, target.id])
        #expect(viewModel.event(for: target.id)?.registeredCount == 4)
        #expect(viewModel.event(for: other.id)?.registeredCount == 17)
    }

    @Test func oldRegistrationCannotMutateOrClearNewSessionOperation() async {
        let repository = ControlledEventRepository()
        let viewModel = EventsViewModel(repository: repository)
        let eventID = "registration-shared-id"
        viewModel.events = [makeEvent(id: eventID)]

        viewModel.toggleRegistration(for: eventID)
        #expect(await eventually { repository.registrationRequestCount == 1 })

        viewModel.resetForAuthChange()
        viewModel.events = [makeEvent(id: eventID, registeredCount: 40)]
        viewModel.toggleRegistration(for: eventID)
        #expect(await eventually { repository.registrationRequestCount == 2 })
        #expect(viewModel.pendingEventRegistrationIDs == [eventID])

        repository.completeRegistrationRequest(
            1,
            result: mutationResult(eventID: eventID, state: .registered, count: 1)
        )
        #expect(await eventually { repository.completedRegistrationRequestCount == 1 })
        #expect(viewModel.pendingEventRegistrationIDs == [eventID])
        #expect(viewModel.event(for: eventID)?.registrationState == .notRegistered)
        #expect(viewModel.event(for: eventID)?.registeredCount == 40)

        repository.completeRegistrationRequest(
            2,
            result: mutationResult(eventID: eventID, state: .registered, count: 41)
        )
        #expect(await eventually { viewModel.pendingEventRegistrationIDs.isEmpty })
        #expect(viewModel.event(for: eventID)?.registrationState == .registered)
        #expect(viewModel.event(for: eventID)?.registeredCount == 41)
    }

    @Test func myRegistrationsIgnoresOldCancellationForNewSessionAndPendingState() async {
        let repository = ControlledEventRepository()
        let eventID = "my-registration-shared-id"
        repository.events = [makeEvent(id: eventID, registrationState: .registered, registeredCount: 5)]
        let viewModel = MyRegistrationsViewModel(repository: repository)
        await viewModel.refresh()

        let oldCancellation = Task { await viewModel.cancelRegistration(for: eventID) }
        #expect(await eventually { repository.registrationRequestCount == 1 })

        viewModel.resetForAuthChange()
        repository.events = [makeEvent(id: eventID, registrationState: .registered, registeredCount: 9)]
        await viewModel.refresh()
        let newCancellation = Task { await viewModel.cancelRegistration(for: eventID) }
        #expect(await eventually { repository.registrationRequestCount == 2 })
        #expect(viewModel.pendingCancellationIDs == [eventID])

        repository.completeRegistrationRequest(
            1,
            result: mutationResult(eventID: eventID, state: .notRegistered, count: 4)
        )
        #expect(await eventually { repository.completedRegistrationRequestCount == 1 })
        #expect(viewModel.pendingCancellationIDs == [eventID])
        #expect(viewModel.events.first?.registeredCount == 9)

        repository.completeRegistrationRequest(
            2,
            result: mutationResult(eventID: eventID, state: .notRegistered, count: 8)
        )
        await oldCancellation.value
        await newCancellation.value
        #expect(viewModel.pendingCancellationIDs.isEmpty)
        #expect(viewModel.events.isEmpty)
    }

    @Test func registrationFailureUsesDedicatedPresentationError() async {
        let repository = ControlledEventRepository()
        let viewModel = EventsViewModel(repository: repository)
        let event = makeEvent(id: "registration-full")
        viewModel.events = [event]

        viewModel.toggleRegistration(for: event.id)
        #expect(await eventually { repository.registrationRequestCount == 1 })
        repository.completeRegistrationRequest(1, error: .full)

        #expect(await eventually { viewModel.pendingEventRegistrationIDs.isEmpty })
        #expect(viewModel.registrationError == EventRegistrationPresentationError(eventID: event.id, reason: .full))
        #expect(viewModel.error == nil)
        #expect(readableEventRegistrationErrorText(.full) == AppStrings.Events.registrationFullError)
        #expect(readableEventRegistrationErrorText(.registrationNotRequired) == AppStrings.Events.registrationNotRequiredError)
        #expect(readableEventRegistrationErrorText(.eventCancelled) == AppStrings.Events.registrationCancelledError)
        #expect(readableEventRegistrationErrorText(.eventPast) == AppStrings.Events.registrationPastError)
        #expect(readableEventRegistrationErrorText(.permissionDenied) == AppStrings.Events.registrationPermissionError)
        #expect(readableEventRegistrationErrorText(.network) == AppStrings.Events.registrationNetworkError)
    }

    @Test func mismatchedRegistrationResponseIsRejectedWithoutMutation() async {
        let repository = ControlledEventRepository()
        let viewModel = EventsViewModel(repository: repository)
        let event = makeEvent(id: "registration-response-target", registeredCount: 6)
        viewModel.events = [event]

        viewModel.toggleRegistration(for: event.id)
        #expect(await eventually { repository.registrationRequestCount == 1 })
        repository.completeRegistrationRequest(
            1,
            result: mutationResult(eventID: "different-event", state: .registered, count: 99)
        )

        #expect(await eventually { viewModel.pendingEventRegistrationIDs.isEmpty })
        #expect(viewModel.event(for: event.id)?.registrationState == .notRegistered)
        #expect(viewModel.event(for: event.id)?.registeredCount == 6)
        #expect(viewModel.registrationError == EventRegistrationPresentationError(
            eventID: event.id,
            reason: .unavailable
        ))
    }

    @Test func registrationFunctionErrorsMapServerReasonsAndTransportFailures() {
        #expect(mappedFunctionError(code: 8, reason: "event-full") == .full)
        #expect(mappedFunctionError(code: 9, reason: "registration-not-required") == .registrationNotRequired)
        #expect(mappedFunctionError(code: 9, reason: "event-cancelled") == .eventCancelled)
        #expect(mappedFunctionError(code: 9, reason: "event-past") == .eventPast)
        #expect(mappedFunctionError(code: 7) == .permissionDenied)
        #expect(mappedFunctionError(code: 16) == .permissionDenied)
        #expect(mappedFunctionError(code: 5) == .notFound)
        #expect(mappedFunctionError(code: 14) == .network)

        let transportError = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        #expect(EventRegistrationFunctionErrorMapper.map(transportError) == .network)
    }

    @Test func eventLikeAndViewDoNotDoubleApplyStateLoadedByRefresh() async {
        let repository = ControlledEventRepository()
        let viewModel = EventsViewModel(repository: repository)
        let eventID = "event-server-interactions"
        viewModel.events = [makeEvent(id: eventID)]

        viewModel.toggleLike(for: eventID)
        viewModel.toggleLike(for: eventID)
        #expect(await eventually { repository.likeRequestCount == 1 })
        repository.events = [makeEvent(id: eventID, likeState: .liked, likeCount: 1)]
        await viewModel.refresh()
        repository.completeLikeRequest(1)
        #expect(await eventually { viewModel.pendingEventLikeIDs.isEmpty })
        #expect(viewModel.event(for: eventID)?.likeState == .liked)
        #expect(viewModel.event(for: eventID)?.likeCount == 1)

        viewModel.recordView(for: eventID)
        viewModel.recordView(for: eventID)
        #expect(await eventually { repository.viewRequestCount == 1 })
        repository.events = [makeEvent(id: eventID, likeState: .liked, likeCount: 1, viewCount: 1)]
        await viewModel.refresh()
        repository.completeViewRequest(1, didRecord: true)
        #expect(await eventually { viewModel.pendingEventViewIDs.isEmpty })
        #expect(viewModel.event(for: eventID)?.viewCount == 1)
    }

    @Test func bookmarkFailureDoesNotOverwriteRefreshedState() async {
        let repository = ControlledEventRepository()
        let viewModel = EventsViewModel(repository: repository)
        let eventID = "event-bookmark-refresh"
        viewModel.events = [makeEvent(id: eventID)]

        viewModel.toggleBookmark(for: eventID)
        #expect(await eventually { repository.bookmarkRequestCount == 1 })
        repository.events = [makeEvent(id: eventID, isBookmarked: true)]
        await viewModel.refresh()
        repository.completeBookmarkRequest(1, error: .network)

        #expect(await eventually { viewModel.pendingEventBookmarkIDs.isEmpty })
        #expect(viewModel.event(for: eventID)?.isBookmarked == true)
        #expect(viewModel.interactionError == .network)
    }

    @Test func commentLoadUpdateAndDeleteResolveCurrentEventAndCommentIDs() async {
        let repository = ControlledEventRepository()
        let viewModel = EventsViewModel(repository: repository)
        let eventID = "event-comments-target"
        let otherID = "event-comments-other"
        let original = makeComment(id: "comment-1", body: "Original")
        let sibling = makeComment(id: "comment-2", body: "Sibling")
        viewModel.events = [
            makeEvent(id: eventID),
            makeEvent(id: otherID, comments: [makeComment(id: "other-comment", body: "Other")])
        ]

        let loadTask = Task { await viewModel.loadComments(for: eventID, forceRefresh: true) }
        #expect(await eventually { repository.commentFetchRequestCount == 1 })
        viewModel.events.reverse()
        repository.completeCommentFetchRequest(1, comments: [original, sibling])
        await loadTask.value
        #expect(viewModel.event(for: eventID)?.comments.map(\.id) == [original.id, sibling.id])
        #expect(viewModel.event(for: otherID)?.comments.first?.id == "other-comment")

        let updateTask = Task { await viewModel.updateComment(eventID: eventID, commentID: original.id, text: "Updated") }
        #expect(await eventually { repository.commentUpdateRequestCount == 1 })
        viewModel.events.reverse()
        repository.completeCommentUpdateRequest(1, comment: makeComment(id: original.id, body: "Updated"))
        await updateTask.value
        #expect(viewModel.event(for: eventID)?.comments.first(where: { $0.id == original.id })?.body == "Updated")

        let deleteTask = Task { await viewModel.deleteComment(eventID: eventID, commentID: original.id) }
        #expect(await eventually { repository.commentDeleteRequestCount == 1 })
        viewModel.events.reverse()
        repository.completeCommentDeleteRequest(1)
        _ = await deleteTask.value
        #expect(viewModel.event(for: eventID)?.comments.map(\.id) == [sibling.id])
        #expect(viewModel.event(for: eventID)?.commentCount == 1)
    }

    @Test func failedEventCommentReturnsFailureWithoutAddingOrKeepingPending() async {
        let repository = ControlledEventRepository()
        let viewModel = EventsViewModel(repository: repository)
        viewModel.events = [makeEvent(id: "event")]
        let task = Task { await viewModel.addComment(to: "event", text: "Keep this", author: makeUser()) }
        #expect(await eventually { repository.commentAddRequestCount == 1 })
        repository.completeCommentAddRequest(1, comment: makeComment(id: "unused", body: "unused"), error: .network)
        #expect(await task.value == .failure(.network))
        #expect(viewModel.pendingEventCommentIDs.isEmpty)
        #expect(viewModel.event(for: "event")?.comments.isEmpty == true)
    }

    @Test func oldCommentCompletionCannotMutateOrClearNewSessionPending() async {
        let repository = ControlledEventRepository()
        let viewModel = EventsViewModel(repository: repository)
        let eventID = "event-comment-shared-id"
        let author = makeUser()
        viewModel.events = [makeEvent(id: eventID)]

        let oldTask = Task { await viewModel.addComment(to: eventID, text: "Old", author: author) }
        #expect(await eventually { repository.commentAddRequestCount == 1 })

        viewModel.resetForAuthChange()
        viewModel.events = [makeEvent(id: eventID)]
        let newTask = Task { await viewModel.addComment(to: eventID, text: "New", author: author) }
        #expect(await eventually { repository.commentAddRequestCount == 2 })
        #expect(viewModel.pendingEventCommentIDs == [eventID])

        repository.completeCommentAddRequest(1, comment: makeComment(id: "old-comment", body: "Old"))
        #expect(await eventually { repository.completedCommentAddRequestCount == 1 })
        #expect(viewModel.pendingEventCommentIDs == [eventID])
        #expect(viewModel.event(for: eventID)?.comments.isEmpty == true)

        repository.completeCommentAddRequest(2, comment: makeComment(id: "new-comment", body: "New"))
        _ = await oldTask.value
        _ = await newTask.value
        #expect(viewModel.pendingEventCommentIDs.isEmpty)
        #expect(viewModel.event(for: eventID)?.comments.map(\.id) == ["new-comment"])
    }

    private func makeEvent(
        id: String,
        registrationState: EventRegistrationState = .notRegistered,
        registeredCount: Int = 0,
        likeState: LikeState = .notLiked,
        likeCount: Int = 0,
        viewCount: Int = 0,
        isBookmarked: Bool = false,
        comments: [UkrainianCommunity.Comment] = []
    ) -> Event {
        Event(
            id: id,
            title: id,
            summary: "Summary",
            details: "Details",
            city: "Vienna",
            venue: "Venue",
            startDate: .now.addingTimeInterval(86_400),
            endDate: .now.addingTimeInterval(90_000),
            createdAt: .now,
            updatedAt: .now,
            capacity: 100,
            registeredCount: registeredCount,
            comments: comments,
            moderationStatus: .approved,
            registrationState: registrationState,
            likeCount: likeCount,
            likeState: likeState,
            viewCount: viewCount,
            isBookmarked: isBookmarked
        )
    }

    private func makeComment(id: String, body: String) -> UkrainianCommunity.Comment {
        UkrainianCommunity.Comment(id: id, authorName: "Author", body: body, createdAt: .now)
    }

    private func makeUser() -> AppUser {
        AppUser(
            id: "event-comment-author",
            fullName: "Comment Author",
            displayName: "Author",
            city: "Vienna",
            email: "author@example.com",
            bio: "",
            role: .user,
            blockState: .active,
            createdAt: .now,
            updatedAt: .now
        )
    }

    private func mutationResult(
        eventID: String,
        state: EventRegistrationState,
        count: Int,
        didChange: Bool = true
    ) -> EventRegistrationMutationResult {
        EventRegistrationMutationResult(
            eventID: eventID,
            registrationState: state,
            registeredCount: count,
            didChange: didChange
        )
    }

    private func mappedFunctionError(code: Int, reason: String? = nil) -> EventRegistrationMutationError {
        var userInfo: [String: Any] = [:]
        if let reason {
            userInfo["details"] = ["reason": reason]
        }
        return EventRegistrationFunctionErrorMapper.map(
            NSError(domain: "com.firebase.functions", code: code, userInfo: userInfo)
        )
    }

    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<1_000 {
            if condition() {
                return true
            }
            await Task.yield()
        }
        return condition()
    }
}

@MainActor
private final class ControlledEventRepository: @MainActor EventRepository {
    var events: [Event] = []
    private(set) var registrationRequestCount = 0
    private(set) var completedRegistrationRequestCount = 0
    private(set) var likeRequestCount = 0
    private(set) var viewRequestCount = 0
    private(set) var bookmarkRequestCount = 0
    private(set) var commentFetchRequestCount = 0
    private(set) var commentAddRequestCount = 0
    private(set) var completedCommentAddRequestCount = 0
    private(set) var commentUpdateRequestCount = 0
    private(set) var commentDeleteRequestCount = 0

    private var registrationContinuations: [Int: CheckedContinuation<EventRegistrationMutationResult, Error>] = [:]
    private var likeContinuations: [Int: CheckedContinuation<Void, Error>] = [:]
    private var viewContinuations: [Int: CheckedContinuation<Bool, Error>] = [:]
    private var bookmarkContinuations: [Int: CheckedContinuation<Void, Error>] = [:]
    private var commentFetchContinuations: [Int: CheckedContinuation<[UkrainianCommunity.Comment], Error>] = [:]
    private var commentAddContinuations: [Int: CheckedContinuation<UkrainianCommunity.Comment, Error>] = [:]
    private var commentUpdateContinuations: [Int: CheckedContinuation<UkrainianCommunity.Comment, Error>] = [:]
    private var commentDeleteContinuations: [Int: CheckedContinuation<Void, Error>] = [:]

    func fetchEvents() async throws -> [Event] { events }
    func fetchEvent(id: String) async throws -> Event {
        guard let event = events.first(where: { $0.id == id }) else { throw AppError.notFound }
        return event
    }
    func fetchRegisteredEvents() async throws -> [Event] {
        events.filter { $0.registrationState == .registered }
    }
    func fetchPendingEvents() async throws -> [Event] { [] }
    func fetchOrganizationModerationEvents(organizationID: String) async throws -> [Event] { [] }
    func fetchOrganizationEventCount(organizationID: String) async throws -> Int { 0 }
    func createEvent(_ event: Event) async throws { events.append(event) }
    func updateEvent(_ event: Event) async throws {
        guard let index = events.firstIndex(where: { $0.id == event.id }) else { throw AppError.notFound }
        events[index] = event
    }
    func updateEventImageURL(id: String, imageURL: String?) async throws {}
    func deleteEvent(id: String) async throws { events.removeAll { $0.id == id } }

    func likeEvent(id: String) async throws { try await suspendLikeRequest() }
    func unlikeEvent(id: String) async throws { try await suspendLikeRequest() }
    func recordEventView(id: String) async throws -> Bool {
        viewRequestCount += 1
        let requestNumber = viewRequestCount
        return try await withCheckedThrowingContinuation { continuation in
            viewContinuations[requestNumber] = continuation
        }
    }

    func fetchEventComments(eventID: String) async throws -> [UkrainianCommunity.Comment] {
        commentFetchRequestCount += 1
        let requestNumber = commentFetchRequestCount
        return try await withCheckedThrowingContinuation { continuation in
            commentFetchContinuations[requestNumber] = continuation
        }
    }

    func fetchEventRegistrations(eventID: String) async throws -> [EventRegistrationAttendee] { [] }

    func addEventComment(eventID: String, text: String, author: AppUser) async throws -> UkrainianCommunity.Comment {
        commentAddRequestCount += 1
        let requestNumber = commentAddRequestCount
        defer { completedCommentAddRequestCount += 1 }
        return try await withCheckedThrowingContinuation { continuation in
            commentAddContinuations[requestNumber] = continuation
        }
    }

    func updateEventComment(eventID: String, commentID: String, text: String) async throws -> UkrainianCommunity.Comment {
        commentUpdateRequestCount += 1
        let requestNumber = commentUpdateRequestCount
        return try await withCheckedThrowingContinuation { continuation in
            commentUpdateContinuations[requestNumber] = continuation
        }
    }

    func deleteEventComment(eventID: String, commentID: String) async throws {
        commentDeleteRequestCount += 1
        let requestNumber = commentDeleteRequestCount
        try await withCheckedThrowingContinuation { continuation in
            commentDeleteContinuations[requestNumber] = continuation
        }
    }

    func registerForEvent(id: String, actionCapture: AnalyticsActionCapture?) async throws -> EventRegistrationMutationResult {
        try await suspendRegistrationRequest()
    }

    func cancelEventRegistration(id: String) async throws -> EventRegistrationMutationResult {
        try await suspendRegistrationRequest()
    }

    func bookmarkEvent(id: String, actionCapture: AnalyticsActionCapture?) async throws { try await suspendBookmarkRequest() }
    func unbookmarkEvent(id: String) async throws { try await suspendBookmarkRequest() }
    func updateModerationStatus(id: String, newStatus: ModerationStatus) async throws {}

    func completeRegistrationRequest(
        _ requestNumber: Int,
        result: EventRegistrationMutationResult? = nil,
        error: EventRegistrationMutationError? = nil
    ) {
        guard let continuation = registrationContinuations.removeValue(forKey: requestNumber) else {
            Issue.record("Missing event registration continuation \(requestNumber)")
            return
        }
        if let error {
            continuation.resume(throwing: error)
        } else if let result {
            continuation.resume(returning: result)
        } else {
            Issue.record("Registration completion requires a result or error")
            continuation.resume(throwing: EventRegistrationMutationError.unavailable)
        }
    }

    func completeLikeRequest(_ requestNumber: Int, error: AppError? = nil) {
        Self.completeVoidRequest(&likeContinuations, requestNumber: requestNumber, error: error, purpose: "like")
    }

    func completeViewRequest(_ requestNumber: Int, didRecord: Bool, error: AppError? = nil) {
        guard let continuation = viewContinuations.removeValue(forKey: requestNumber) else {
            Issue.record("Missing event view continuation \(requestNumber)")
            return
        }
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume(returning: didRecord)
        }
    }

    func completeBookmarkRequest(_ requestNumber: Int, error: AppError? = nil) {
        Self.completeVoidRequest(&bookmarkContinuations, requestNumber: requestNumber, error: error, purpose: "bookmark")
    }

    func completeCommentFetchRequest(_ requestNumber: Int, comments: [UkrainianCommunity.Comment]) {
        guard let continuation = commentFetchContinuations.removeValue(forKey: requestNumber) else {
            Issue.record("Missing event comment fetch continuation \(requestNumber)")
            return
        }
        continuation.resume(returning: comments)
    }

    func completeCommentAddRequest(_ requestNumber: Int, comment: UkrainianCommunity.Comment, error: AppError? = nil) {
        guard let continuation = commentAddContinuations.removeValue(forKey: requestNumber) else {
            Issue.record("Missing event comment add continuation \(requestNumber)")
            return
        }
        if let error { continuation.resume(throwing: error) }
        else { continuation.resume(returning: comment) }
    }

    func completeCommentUpdateRequest(_ requestNumber: Int, comment: UkrainianCommunity.Comment) {
        guard let continuation = commentUpdateContinuations.removeValue(forKey: requestNumber) else {
            Issue.record("Missing event comment update continuation \(requestNumber)")
            return
        }
        continuation.resume(returning: comment)
    }

    func completeCommentDeleteRequest(_ requestNumber: Int, error: AppError? = nil) {
        Self.completeVoidRequest(
            &commentDeleteContinuations,
            requestNumber: requestNumber,
            error: error,
            purpose: "comment delete"
        )
    }

    private func suspendRegistrationRequest() async throws -> EventRegistrationMutationResult {
        registrationRequestCount += 1
        let requestNumber = registrationRequestCount
        defer { completedRegistrationRequestCount += 1 }
        return try await withCheckedThrowingContinuation { continuation in
            registrationContinuations[requestNumber] = continuation
        }
    }

    private func suspendLikeRequest() async throws {
        likeRequestCount += 1
        let requestNumber = likeRequestCount
        try await withCheckedThrowingContinuation { continuation in
            likeContinuations[requestNumber] = continuation
        }
    }

    private func suspendBookmarkRequest() async throws {
        bookmarkRequestCount += 1
        let requestNumber = bookmarkRequestCount
        try await withCheckedThrowingContinuation { continuation in
            bookmarkContinuations[requestNumber] = continuation
        }
    }

    private static func completeVoidRequest(
        _ continuations: inout [Int: CheckedContinuation<Void, Error>],
        requestNumber: Int,
        error: AppError?,
        purpose: String
    ) {
        guard let continuation = continuations.removeValue(forKey: requestNumber) else {
            Issue.record("Missing event \(purpose) continuation \(requestNumber)")
            return
        }
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume(returning: ())
        }
    }
}
