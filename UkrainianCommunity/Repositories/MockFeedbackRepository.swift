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

    func fetchFeedbackMessages(feedback: FeedbackItem) async throws -> [FeedbackMessage] {
        await store.feedbackMessages(for: feedback)
    }

    func sendUserFeedbackMessage(feedback: FeedbackItem, text: String, user: AppUser) async throws {
        try await store.addFeedbackMessage(feedback: feedback, text: text, sender: user, senderRole: .user)
    }

    func sendOwnerFeedbackReply(feedback: FeedbackItem, text: String, owner: AppUser) async throws {
        try await store.addFeedbackMessage(feedback: feedback, text: text, sender: owner, senderRole: .owner)
    }

    func updateFeedbackStatus(id: String, status: FeedbackStatus) async throws {
        try await store.updateFeedbackStatus(id: id, status: status)
    }

    func replyToFeedback(id: String, reply: String, repliedByUserID: String) async throws {
        try await store.replyToFeedback(id: id, reply: reply, repliedByUserID: repliedByUserID)
    }

    func closeFeedback(id: String) async throws {
        try await store.updateFeedbackStatus(id: id, status: .closed)
    }
}
