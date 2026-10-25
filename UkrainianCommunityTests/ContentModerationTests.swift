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
    @Test func moderationNotificationShowsTheReasonExactlyOnceAndKeepsMetadataOnlyReasons() {
        let reason = "Уточніть адресу проведення."
        for message in ["Подія громади — " + reason, "Подія громади"] {
            let notification = AppNotification(id: "moderation-detail", recipientUserId: "author", type: .contentModerationChanged,
                sourceType: .organization, sourceId: "event:material", actionType: .openProfile,
                message: message, metadata: ["moderationStatus": "needsRevision", "moderationReason": reason],
                payload: [:], isRead: false, readAt: nil, createdAt: .now)
            let body = notification.localizedDetailContent.body
            #expect(body.components(separatedBy: reason).count == 2)
            #expect(body.contains(ModerationStatus.needsRevision.title))
            #expect(notification.canOpenDestination)
        }
    }

    @Test func aDeletedPreviewCannotOfferADecisionOrMisleadingRetryAndANetworkRetryCanRecover() async throws {
        let sample = try await item()
        for failure in [AppError.notFound as Error, NSError(domain: FunctionsErrorDomain, code: FunctionsErrorCode.notFound.rawValue)] {
            let model = ContentReviewDetailModel(client: .init(read: { _ in throw failure }, decide: { _, _, _, _, _ in }))
            await model.load(type: "news", id: sample.id, principal: "author")
            #expect(model.item == nil); #expect(model.isUnavailable); #expect(model.error == ModerationAuditCopy.unavailable)
        }
        var fail = true
        let model = ContentReviewDetailModel(client: .init(read: { _ in
            if fail { throw AppError.network }; return .init(item: sample)
        }, decide: { _, _, _, _, _ in }))
        await model.load(type: "news", id: sample.id, principal: "owner")
        #expect(!model.isUnavailable); #expect(model.error != nil)
        fail = false
        await model.load(type: "news", id: sample.id, principal: "owner")
        #expect(model.item?.id == sample.id); #expect(model.error == nil); #expect(!model.isUnavailable)
    }

    @Test func failedRefreshPreservesConfirmedQueueInsteadOfReplacingItWithEmptyState() async throws {
        let sample = try await item()
        var fail = false
        let model = ContentModerationModel(client: .init(read: { _ in
            if fail { throw AppError.network }
            return .init(items: [sample], counts: ["news": 1])
        }, decide: { _, _, _, _, _ in }))
        await model.load(type: "news", historyMode: false, reset: true)
        fail = true
        await model.load(type: "news", historyMode: false, reset: true)
        #expect(model.items == [sample]); #expect(model.counts["news"] == 1)
        #expect(model.error != nil); #expect(!model.isLoading)
    }
    @Test func duplicateRefreshDoesNotIssueTwoIdenticalReads() async throws {
        let sample = try await item()
        var calls = 0
        let model = ContentModerationModel(client: .init(read: { _ in
            calls += 1; try await Task.sleep(for: .milliseconds(80))
            return .init(items: [sample])
        }, decide: { _, _, _, _, _ in }))
        let first = Task { await model.load(type: "news", historyMode: false, reset: true) }
        await Task.yield()
        await model.load(type: "news", historyMode: false, reset: true)
        await first.value
        #expect(calls == 1); #expect(model.items == [sample]); #expect(!model.isLoading)
    }
    @Test func latePreviewCannotOverwriteTheMaterialOpenedAfterIt() async throws {
        let first = try await item()
        let second = try #require(try await ContentModerationFixture.shared.client.read(.init(action: "preview", contentType: "news", contentId: "moderation-news-1")).item)
        let model = ContentReviewDetailModel(client: .init(read: { query in
            if query.contentId == first.id { try await Task.sleep(for: .milliseconds(80)); return .init(item: first) }
            return .init(item: second)
        }, decide: { _, _, _, _, _ in }))
        let old = Task { await model.load(type: "news", id: first.id) }
        await Task.yield()
        await model.load(type: "news", id: second.id)
        await old.value
        #expect(model.item?.id == second.id); #expect(!model.loading)
    }

    @Test func accountScopeResetClearsCountsAndDiscardsLateData() async throws {
        let sample = try await item()
        let model = ContentModerationModel(client: .init(read: { _ in
            try await Task.sleep(for: .milliseconds(80)); return .init(items: [sample], counts: ["news": 99])
        }, decide: { _, _, _, _, _ in }))
        let old = Task { await model.load(type: "news", historyMode: false, reset: true) }
        await Task.yield(); model.reset(); await old.value
        #expect(model.items.isEmpty); #expect(model.counts.isEmpty); #expect(!model.isLoading); #expect(!model.hasLoaded)
    }
    @Test func previewPrincipalAndConfirmedRevisionCannotBeSilentlyReplaced() async throws {
        let sample = try await item()
        let other = try #require(try await ContentModerationFixture.shared.client.read(.init(action: "preview", contentType: "news", contentId: "moderation-news-1")).item)
        var calls = 0
        let model = ContentReviewDetailModel(client: .init(read: { _ in .init(item: sample) }, decide: { _, _, _, _, _ in calls += 1 }))
        await model.load(type: "news", id: sample.id, principal: "first-owner")
        await model.decide(.approved, reason: "", principal: "other-owner")
        await model.decide(.approved, reason: "", principal: "first-owner", reviewedItem: other)
        #expect(calls == 0); #expect(!model.completed); #expect(model.error == ContentModerationCopy.changed)
    }
    @Test func failedNextPageRetainsCursorAndRetriesTheSamePage() async throws {
        let sample = try await item(); var pageCalls = 0
        let next = ContentModerationCursor(seconds: 1, nanoseconds: 2, id: sample.id)
        let model = ContentModerationModel(client: .init(read: { query in
            guard query.cursor != nil else { return .init(items: [sample], counts: ["news": 2], cursor: next) }
            #expect(query.cursor == next); pageCalls += 1
            if pageCalls == 1 { throw AppError.network }
            return .init(items: [])
        }, decide: { _, _, _, _, _ in }))
        await model.load(type: "news", historyMode: false, reset: true)
        await model.load(type: "news", historyMode: false, reset: false)
        #expect(model.failedLoadWasMore); #expect(model.items == [sample]); #expect(model.hasMore)
        await model.load(type: "news", historyMode: false, reset: false)
        #expect(pageCalls == 2); #expect(model.error == nil); #expect(!model.hasMore)
    }

    @Test func fullPublicationWireIncludesEventConditionsAndOlderPayloadsRemainDecodable() async throws {
        let legacy = try await item()
        #expect(legacy.publication == nil)
        let rich = ContentModerationFixture.richEvent()
        let decoded = try JSONDecoder().decode(ContentReviewItem.self, from: JSONEncoder().encode(rich))
        let details = try #require(decoded.publication)
        #expect(details.externalAction?.webURL?.path == "/tickets")
        #expect(details.pricing?.kind == "range"); #expect(details.pricing?.maximumAmount == 20)
        #expect(details.occurrences?.count == 2); #expect(details.occurrences?.last?.status == "cancelled")
        #expect(details.contactEmail == "fixture@example.org"); #expect(details.mediaMetadata?.alternativeText == "Accessible description")
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
