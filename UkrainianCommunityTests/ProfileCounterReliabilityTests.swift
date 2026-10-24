import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct ProfileCounterReliabilityTests {
    @Test func paginatedFallbackCountsUnreadRecordsBeyondTheFirstHundred() async throws {
        let repository = PagedCountRepository()
        #expect(try await repository.fetchUnreadOwnerFeedbackCount() == 137)
        #expect(repository.pageReads == 3)
    }

    @Test func concurrentRefreshesCoalesceAndOldCompletionCannotReplaceNewScope() async {
        let repository = SuspendedCountRepository()
        let model = OwnerProfileVisibilityViewModel(feedbackRepository: repository, organizationRepository: MockOrganizationRepository())
        let first = Task { await model.refresh(includeOrganizationRequests: false, includeFeedback: true) }
        while repository.resume == nil { await Task.yield() }
        let second = Task { await model.refresh(includeOrganizationRequests: false, includeFeedback: true) }
        for _ in 0..<20 { await Task.yield() }
        #expect(repository.reads == 1)
        let oldResume = repository.resume
        model.reset()
        repository.hold = false
        repository.value = 243
        await model.refresh(includeOrganizationRequests: false, includeFeedback: true)
        oldResume?.resume(returning: 1)
        await first.value; await second.value
        #expect(model.unreadFeedbackCount == 243)
        #expect(model.feedbackCountState == .loaded(243))
    }

    @Test func failedCountRetainsKnownNumberAndSuccessfulRetryRecovers() async {
        let repository = SuspendedCountRepository()
        repository.hold = false; repository.value = 137
        let model = OwnerProfileVisibilityViewModel(feedbackRepository: repository, organizationRepository: MockOrganizationRepository())
        await model.refresh(includeOrganizationRequests: false, includeFeedback: true)
        repository.fails = true
        await model.refresh(includeOrganizationRequests: false, includeFeedback: true)
        #expect(model.unreadFeedbackCount == 137)
        #expect(model.feedbackCountState == .failed)
        repository.fails = false; repository.value = 136
        await model.refresh(includeOrganizationRequests: false, includeFeedback: true)
        #expect(model.feedbackCountState == .loaded(136))
    }
}

@MainActor
private final class SuspendedCountRepository: FeedbackRepository {
    var reads = 0, value = 0
    var hold = true, fails = false
    var resume: CheckedContinuation<Int, Never>?
    func fetchUnreadOwnerFeedbackCount() async throws -> Int {
        reads += 1
        if hold { return await withCheckedContinuation { resume = $0 } }
        if fails { throw AppError.network }
        return value
    }
    func fetchFeedback() async throws -> [FeedbackItem] { [] }
    func submitFeedback(_ feedback: FeedbackItem) async throws {}
    func updateFeedbackStatus(id: String, status: FeedbackStatus) async throws {}
}

@MainActor
private final class PagedCountRepository: FeedbackRepository {
    var pageReads = 0
    let items: [FeedbackItem] = (0..<250).map { index in
        FeedbackItem(id: "count-\(index)", type: .question, subject: nil, message: "Question", status: .open,
            createdAt: Date(timeIntervalSince1970: Double(index)), updatedAt: .now,
            userId: "member", userDisplayName: "Member", ownerReply: nil, repliedAt: nil, repliedByUserId: nil,
            lastMessageText: nil, lastMessageAt: nil, lastMessageByUserId: nil, lastMessageByRole: nil,
            unreadForOwner: index < 137, unreadForUser: false)
    }
    func fetchFeedback() async throws -> [FeedbackItem] { items }
    func fetchFeedbackPage(userID: String?, after cursor: FeedbackPageCursor?, limit: Int) async throws -> FeedbackPage {
        pageReads += 1
        let sorted = items.sorted { $0.createdAt > $1.createdAt }
        let start = cursor.flatMap { next in sorted.firstIndex { $0.id == next.id }.map { $0 + 1 } } ?? 0
        let page = Array(sorted.dropFirst(start).prefix(limit))
        return FeedbackPage(items: page, nextCursor: page.last.map { .init(createdAt: $0.createdAt, id: $0.id) }, hasMore: start + page.count < sorted.count)
    }
    func submitFeedback(_ feedback: FeedbackItem) async throws {}
    func updateFeedbackStatus(id: String, status: FeedbackStatus) async throws {}
}
