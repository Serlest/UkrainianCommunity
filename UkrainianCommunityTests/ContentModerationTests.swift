import Foundation
import FirebaseFunctions
import Testing
@testable import UkrainianCommunity

@Suite(.serialized)
@MainActor
struct ContentModerationTests {
    private func item() async throws -> ContentReviewItem {
        try #require(try await ContentModerationFixture.shared.client.read(.init(action: "preview", contentType: "news", contentId: "moderation-news-0")).item)
    }
    @Test func paginatedQueueLoadsAll37WithoutDuplicatesAndCountsWholeQueue() async {
        let model = ContentModerationModel(client: ContentModerationFixture.shared.client)
        await model.load(type: "news", historyMode: false, reset: true)
        #expect(model.items.count == 30); #expect(model.counts["news"] == 37); #expect(model.hasMore)
        await model.load(type: "news", historyMode: false, reset: false)
        #expect(model.items.count == 37); #expect(Set(model.items.map(\.id)).count == 37); #expect(!model.hasMore)
        await model.load(type: "news", historyMode: false, reset: false)
        #expect(model.items.count == 37)
    }
    @Test func staleLoadCannotOverwriteNewerHistoryOrRestoreOldCursor() async throws {
        let sample = try await item()
        let entry = ContentReviewHistoryEntry(id: "history-1", contentId: sample.id, contentType: "news", title: sample.title,
            status: .rejected, reason: "Reason", reviewerName: "Owner", organizationName: sample.organizationName, createdAt: sample.createdAt)
        let client = ContentModerationClient(read: { query in
            if query.action == "list" { try await Task.sleep(for: .milliseconds(100)); return .init(items: [sample], cursor: .init(seconds: 1, nanoseconds: 0, id: "old")) }
            return .init(history: [entry])
        }, decide: { _, _, _, _, _ in })
        let model = ContentModerationModel(client: client)
        let old = Task { await model.load(type: "news", historyMode: false, reset: true) }
        await Task.yield()
        await model.load(type: "news", historyMode: true, reset: true)
        await old.value
        #expect(model.items.isEmpty); #expect(model.history == [entry]); #expect(!model.hasMore); #expect(!model.isLoading)
    }
    @Test func decisionUsesExactRevisionAndStableOperationAfterLostResponse() async throws {
        let sample = try await item()
        var operations: [String] = []; var revisions: [String] = []; var principals: [String] = []
        let client = ContentModerationClient(read: { _ in .init(item: sample) }, decide: { item, _, _, operation, principal in
            operations.append(operation); revisions.append(item.revision); principals.append(principal)
            if operations.count == 1 { throw AppError.network }
        })
        let model = ContentReviewDetailModel(client: client)
        await model.load(type: "news", id: sample.id)
        await model.decide(.needsRevision, reason: "Fix source", principal: "owner")
        #expect(!model.completed); #expect(model.error != nil)
        await model.decide(.needsRevision, reason: "Fix source", principal: "owner")
        #expect(model.completed); #expect(model.error == nil); #expect(!model.processing)
        #expect(operations.count == 2); #expect(operations[0] == operations[1]); #expect(revisions == [sample.revision, sample.revision]); #expect(principals == ["owner", "owner"])
        #expect(sample.revision == "1792670000:123456000")
    }
    @Test func reasonsAreRequiredAndBoundedForReturnOrRejectAndClearedOnApproval() async throws {
        let sample = try await item(); var calls: [String] = []
        let client = ContentModerationClient(read: { _ in .init(item: sample) }, decide: { _, _, reason, _, _ in calls.append(reason) })
        let model = ContentReviewDetailModel(client: client)
        await model.load(type: "news", id: sample.id)
        await model.decide(.rejected, reason: "   ", principal: "owner")
        await model.decide(.needsRevision, reason: String(repeating: "x", count: 2001), principal: "owner")
        #expect(calls.isEmpty)
        await model.decide(.approved, reason: "leftover rejection text", principal: "owner")
        #expect(calls == [""])
    }
    @Test func staleAndPermissionFailuresRemainVisibleAndDoNotClaimSuccess() async throws {
        let sample = try await item()
        for code in [FunctionsErrorCode.aborted, .permissionDenied] {
            let client = ContentModerationClient(read: { _ in .init(item: sample) }, decide: { _, _, _, _, _ in
                throw NSError(domain: FunctionsErrorDomain, code: code.rawValue)
            })
            let model = ContentReviewDetailModel(client: client)
            await model.load(type: "news", id: sample.id)
            await model.decide(.approved, reason: "", principal: "owner")
            #expect(!model.completed); #expect(model.error != nil); #expect(!model.processing)
            if code == .aborted { #expect(model.error == ContentModerationCopy.changed) }
        }
    }
    @Test func independentContentTypesShowEmptyEventsWithoutHidingNewsAndReportNetworkFailure() async {
        let model = ContentModerationModel(client: ContentModerationFixture.shared.client)
        await model.load(type: "event", historyMode: false, reset: true)
        #expect(model.items.isEmpty); #expect(model.counts["news"] == 37); #expect(model.error == nil)
        let failed = ContentModerationModel(client: .init(read: { _ in throw AppError.network }, decide: { _, _, _, _, _ in }))
        await failed.load(type: "news", historyMode: false, reset: true)
        #expect(failed.error != nil); #expect(!failed.isLoading)
    }
}
