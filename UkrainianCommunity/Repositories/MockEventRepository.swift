import Foundation

struct MockEventRepository: EventRepository {
    private let store = MockRepositoryStore.shared

    func fetchEvents() async throws -> [Event] {
        await store.events
            .filter { $0.moderationStatus == .approved }
            .sorted { $0.startDate < $1.startDate }
    }

    func fetchRegisteredEvents() async throws -> [Event] {
        await store.events
            .filter { $0.moderationStatus == .approved && $0.registrationState == .registered }
            .sorted { $0.startDate < $1.startDate }
    }

    func fetchEvent(id: String) async throws -> Event {
        guard let event = await store.events.first(where: { $0.id == id }) else {
            throw AppError.notFound
        }
        return event
    }

    func fetchPendingEvents() async throws -> [Event] {
        await store.pendingEvents()
    }

    func fetchOrganizationModerationEvents(organizationID: String) async throws -> [Event] {
        await store.organizationModerationEvents(organizationID: organizationID)
    }

    func fetchOrganizationEventCount(organizationID: String) async throws -> Int {
        await store.organizationEventCount(organizationID: organizationID)
    }

    func createEvent(_ event: Event) async throws {
        await store.createEvent(event)
    }

    func updateEvent(_ event: Event) async throws {
        try await store.updateEvent(event)
    }

    func updateEventImageURL(id: String, imageURL: String?) async throws {
        try await store.updateEventImageURL(id: id, imageURL: imageURL)
    }

    func deleteEvent(id: String) async throws {
        try await store.deleteEvent(id: id)
    }

    func likeEvent(id: String) async throws {
        try await store.toggleEventLike(id: id, isLiked: true)
    }

    func unlikeEvent(id: String) async throws {
        try await store.toggleEventLike(id: id, isLiked: false)
    }

    func recordEventView(id: String) async throws -> Bool {
        try await store.recordEventView(id: id)
    }

    func fetchEventComments(eventID: String) async throws -> [Comment] {
        try await store.eventComments(eventID: eventID)
    }

    func fetchEventRegistrations(eventID: String) async throws -> [EventRegistrationAttendee] {
        try await store.eventRegistrations(eventID: eventID)
    }

    func registerForEvent(id: String) async throws {
        try await store.setEventRegistration(id: id, isRegistered: true)
    }

    func cancelEventRegistration(id: String) async throws {
        try await store.setEventRegistration(id: id, isRegistered: false)
    }

    func bookmarkEvent(id: String) async throws {
        try await store.setEventBookmark(id: id, isBookmarked: true)
    }

    func unbookmarkEvent(id: String) async throws {
        try await store.setEventBookmark(id: id, isBookmarked: false)
    }

    func updateModerationStatus(id: String, newStatus: ModerationStatus) async throws {
        try await store.updateEventModerationStatus(id: id, newStatus: newStatus)
    }

    func addEventComment(eventID: String, text: String, author: AppUser) async throws -> Comment {
        try await store.addEventComment(eventID: eventID, text: text, author: author)
    }

    func updateEventComment(eventID: String, commentID: String, text: String) async throws -> Comment {
        try await store.updateEventComment(eventID: eventID, commentID: commentID, text: text)
    }

    func deleteEventComment(eventID: String, commentID: String) async throws {
        try await store.deleteEventComment(eventID: eventID, commentID: commentID)
    }
}
