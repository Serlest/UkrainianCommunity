import Foundation

struct MockFeedbackRepository: FeedbackRepository {
    private let store = MockRepositoryStore.shared

    func submitFeedback(_ feedback: FeedbackItem) async throws {
        await store.createFeedback(feedback)
    }

    func fetchFeedback() async throws -> [FeedbackItem] {
        await store.feedback()
    }

    func fetchFeedback(userID: String) async throws -> [FeedbackItem] {
        await store.feedback(userID: userID)
    }

    func fetchFeedback(id: String) async throws -> FeedbackItem {
        guard let item = (await store.feedback()).first(where: { $0.id == id }) else {
            throw AppError.notFound
        }
        return item
    }

    func fetchFeedbackMessages(feedback: FeedbackItem) async throws -> [FeedbackMessage] {
        await store.feedbackMessages(for: feedback)
    }

    func acknowledgeFeedbackReadByUser(id: String, userID: String) async throws {
        try await store.acknowledgeFeedbackRead(id: id, userID: userID, byOwner: false)
    }

    func acknowledgeFeedbackReadByOwner(id: String) async throws {
        try await store.acknowledgeFeedbackRead(id: id, userID: nil, byOwner: true)
    }

    func performFeedbackOperation(_ operation: FeedbackOperationAttempt) async throws {
        try await store.performFeedbackOperation(operation)
    }

    func updateFeedbackStatus(id: String, status: FeedbackStatus) async throws {
        try await store.updateFeedbackStatus(id: id, status: status)
    }

    func replyToFeedback(id: String, reply: String, repliedByUserID: String) async throws {
        try await store.replyToFeedback(id: id, reply: reply, repliedByUserID: repliedByUserID)
    }

    func deleteFeedback(id: String) async throws {
        try await store.deleteFeedback(id: id)
    }

    func clearFeedbackInbox() async throws {
        await store.clearFeedback()
    }
}
