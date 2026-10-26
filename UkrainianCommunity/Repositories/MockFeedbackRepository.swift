import Foundation

struct MockFeedbackRepository: FeedbackRepository {
    private let store = MockRepositoryStore.shared
    private let audit = FeedbackSupportAuditTransport()

    func submitFeedback(_ feedback: FeedbackItem) async throws {
        try await audit.check("submit")
        await store.createFeedback(feedback)
    }

    func fetchFeedback() async throws -> [FeedbackItem] {
        if audit.isEmpty { return [] }
        return await store.feedback()
    }

    func fetchFeedback(userID: String) async throws -> [FeedbackItem] {
        await store.feedback(userID: userID)
    }

    func fetchOwnerInbox(query: FeedbackInboxQuery, after: FeedbackInboxCursor?) async throws -> FeedbackInboxPage {
        try await audit.check(after == nil ? "inbox" : "page")
        let matching = try await fetchFeedback().filter { LocalSearchMatcher.matches(query: query.search,
            values: [$0.id, $0.userId, $0.userDisplayName, $0.subject, $0.message, $0.lastMessageText]) }
        func bucket(_ item: FeedbackItem) -> String { item.status.isClosed ? "closed" : item.status.isAnswered ? "answered" : "open" }
        let counts = Dictionary(grouping: matching, by: bucket).mapValues(\.count)
        let rows = matching.filter { bucket($0) == query.filter }.sorted {
            let l = $0.lastMessageAt ?? $0.updatedAt, r = $1.lastMessageAt ?? $1.updatedAt
            return l == r ? (query.oldest ? $0.id < $1.id : $0.id > $1.id) : (query.oldest ? l < r : l > r)
        }
        let start = after.flatMap { cursor in rows.firstIndex { $0.id == cursor.id }.map { $0 + 1 } } ?? 0
        let page = Array(rows.dropFirst(start).prefix(30))
        return .init(items: page, counts: counts, cursor: start + page.count < rows.count ? page.last.map {
            .init(seconds: Int64(($0.lastMessageAt ?? $0.updatedAt).timeIntervalSince1970), nanoseconds: 0, id: $0.id)
        } : nil)
    }

    func fetchFeedbackPage(userID: String?, after cursor: FeedbackPageCursor?, limit: Int) async throws -> FeedbackPage {
        if userID != nil { try await audit.check(cursor == nil ? "mine" : "page") }
        let rows = try await fetchFeedback().filter { userID == nil || $0.userId == userID }.sorted {
            $0.createdAt == $1.createdAt ? $0.id > $1.id : $0.createdAt > $1.createdAt
        }.filter { cursor == nil || $0.createdAt < cursor!.createdAt || ($0.createdAt == cursor!.createdAt && $0.id < cursor!.id) }
        let items = Array(rows.prefix(limit))
        return .init(items: items, nextCursor: items.last.map { .init(createdAt: $0.createdAt, id: $0.id) }, hasMore: rows.count > items.count)
    }

    func fetchFeedbackMessagesPage(feedback: FeedbackItem, after cursor: FeedbackPageCursor?, limit: Int) async throws -> FeedbackMessagePage {
        try await audit.check("messages")
        let rows = await store.feedbackMessages(for: feedback).sorted {
            $0.createdAt == $1.createdAt ? $0.id > $1.id : $0.createdAt > $1.createdAt
        }.filter { cursor == nil || $0.createdAt < cursor!.createdAt || ($0.createdAt == cursor!.createdAt && $0.id < cursor!.id) }
        let items = Array(rows.prefix(limit))
        return .init(items: Array(items.reversed()), nextCursor: items.last.map { .init(createdAt: $0.createdAt, id: $0.id) }, hasMore: rows.count > items.count)
    }

    func fetchFeedback(id: String) async throws -> FeedbackItem {
        try await audit.check("detail")
        if audit.isDeleted { throw AppError.notFound }
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
        try await audit.check("send")
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

/// Transport failures exist only in explicit Debug Simulator audit launches.
@MainActor private final class FeedbackSupportAuditTransport {
    private var used = Set<String>()
    private var mode: String {
#if DEBUG && targetEnvironment(simulator)
        guard ProcessInfo.processInfo.arguments.contains("-ui-testing"),
              ProcessInfo.processInfo.environment["UITestFeedbackAudit"] == "1" else { return "" }
        return ProcessInfo.processInfo.environment["UITestFeedbackMode"] ?? ""
#else
        return ""
#endif
    }
    var isEmpty: Bool { mode == "empty" }
    var isDeleted: Bool { mode == "deleted" }
    func check(_ kind: String) async throws {
        if mode == "slow" { try await Task.sleep(for: .seconds(2)) }
        if mode == kind + "-error", used.insert(kind).inserted { throw AppError.network }
    }
}
