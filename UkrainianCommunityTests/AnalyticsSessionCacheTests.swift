import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
private final class CacheProbe: OwnerAnalyticsRepository {
    var reads = 0
    var fail = false
    var hold = false
    var continuation: CheckedContinuation<Void, Never>?
    func fetchSnapshot(period: AnalyticsPeriod) async throws -> OwnerAnalyticsSnapshot {
        reads += 1
        if hold { await withCheckedContinuation { continuation = $0 } }
        if fail { throw AppError.network }
        return .empty(period: period)
    }
    func fetchContentDetail(period: AnalyticsPeriod, contentID: String, contentType: AnalyticsContentType) async throws -> AnalyticsContentDetailSnapshot {
        .empty(period: period, contentID: contentID, contentType: contentType)
    }
    func fetchOrganizationDetail(period: AnalyticsPeriod, organizationID: String) async throws -> AnalyticsOrganizationDetailSnapshot {
        .empty(period: period, organizationID: organizationID)
    }
}

@MainActor
struct AnalyticsSessionCacheTests {
    @Test func coalescesAndSharesAcrossDestinationsThenExpires() async throws {
        let source = CacheProbe(); source.hold = true
        var clock = Date(timeIntervalSince1970: 1_798_000_000)
        let cache = SessionOwnerAnalyticsRepository(underlying: source, now: { clock })
        cache.updateAccess(user: MockContentBuilder.ownerUser(), state: .authenticated)
        let a = Task { try await cache.fetchSnapshot(period: .sevenDays) }
        while source.continuation == nil { await Task.yield() }
        let b = Task { try await cache.fetchSnapshot(period: .sevenDays) }
        await Task.yield()
        source.continuation?.resume(); source.continuation = nil
        _ = try await (a.value, b.value)
        #expect(source.reads == 1)
        _ = try await cache.fetchSnapshot(period: .sevenDays)
        #expect(source.reads == 1)
        source.hold = false; clock += 61
        _ = try await cache.fetchSnapshot(period: .sevenDays)
        #expect(source.reads == 2)
        cache.invalidateCachedReads()
        _ = try await cache.fetchSnapshot(period: .sevenDays)
        #expect(source.reads == 3)
    }
    @Test func deniesNonOwnerAndRejectsLateResponseAfterSignOutAndBack() async throws {
        let source = CacheProbe(); source.hold = true
        let cache = SessionOwnerAnalyticsRepository(underlying: source)
        await #expect(throws: AppError.permissionDenied) { try await cache.fetchSnapshot(period: .today) }
        let owner = MockContentBuilder.ownerUser()
        cache.updateAccess(user: owner, state: .authenticated)
        let request = Task { try await cache.fetchSnapshot(period: .today) }
        while source.continuation == nil { await Task.yield() }
        cache.updateAccess(user: nil, state: .guest)
        cache.updateAccess(user: owner, state: .authenticated)
        source.continuation?.resume(); source.continuation = nil
        await #expect(throws: CancellationError.self) { try await request.value }
        source.hold = false
        _ = try await cache.fetchSnapshot(period: .today)
        #expect(source.reads == 2)
        let member = AppUser(id: owner.id, fullName: "Member", displayName: "Member", city: "Wien", email: "member@example.test", bio: "", role: .user, globalRole: .user, blockState: .active, createdAt: .now, updatedAt: .now)
        cache.updateAccess(user: member, state: .authenticated)
        await #expect(throws: AppError.permissionDenied) { try await cache.fetchSnapshot(period: .today) }
        #expect(source.reads == 2)
    }
    @Test func failureIsNotCachedAndMidnightRefreshesEvenWithinTTL() async throws {
        let source = CacheProbe()
        var clock = ISO8601DateFormatter().date(from: "2026-10-26T22:59:50Z")!
        let cache = SessionOwnerAnalyticsRepository(underlying: source, now: { clock })
        cache.updateAccess(user: MockContentBuilder.ownerUser(), state: .authenticated)
        source.fail = true
        await #expect(throws: AppError.network) { try await cache.fetchSnapshot(period: .today) }
        source.fail = false
        _ = try await cache.fetchSnapshot(period: .today)
        #expect(source.reads == 2)
        clock += 20
        _ = try await cache.fetchSnapshot(period: .today)
        #expect(source.reads == 3)
    }
    @Test func repeatedRefreshDoesNotStartAnOverlappingViewModelRead() async {
        let source = CacheProbe(); source.hold = true
        let model = OwnerAnalyticsViewModel(repository: source)
        let first = Task { await model.load() }
        while source.continuation == nil { await Task.yield() }
        await model.load()
        #expect(source.reads == 1)
        source.continuation?.resume(); source.continuation = nil
        await first.value
        #expect(!model.isLoading)
    }
    @Test func liveAccessIsCheckedBeforeServingCachedDataWithoutWaitingForARender() async throws {
        let owner = MockContentBuilder.ownerUser()
        var user: AppUser? = owner
        let source = CacheProbe()
        let cache = SessionOwnerAnalyticsRepository(underlying: source, access: { (user, .authenticated) })
        _ = try await cache.fetchSnapshot(period: .today)
        user = nil
        await #expect(throws: AppError.permissionDenied) { try await cache.fetchSnapshot(period: .today) }
        user = owner
        _ = try await cache.fetchSnapshot(period: .today)
        #expect(source.reads == 2)
    }
    @Test func displayedCurrentAccountHeadingIsSearchableInBothLanguages() {
        let previous = LocalizationStore.language
        defer { LocalizationStore.language = previous }
        for language in AppLanguage.allCases {
            LocalizationStore.language = language
            let model = OwnerAnalyticsViewModel(repository: MockOwnerAnalyticsRepository())
            model.searchText = AnalyticsPresentationText.currentTitle
            #expect(model.showsCurrentAccounts)
            #expect(model.hasSupplementalSearchResults)
            #expect(model.hasSearchResults)
        }
    }
    @Test func strictCountersRejectMalformedAndOverflowingDocuments() {
        for bad: Any in [true, NSNumber(value: false), -1, 1.5, Double.nan, Double.infinity, -Double.infinity, Double(Int.max), Int.max, "12"] {
            #expect(AnalyticsCountDecoder.decode(bad) == nil)
            #expect(!AnalyticsCountDecoder.validates(["metrics": ["views": bad]]))
        }
        #expect(AnalyticsCountDecoder.decode(0) == 0)
        #expect(AnalyticsCountDecoder.decode(42.0) == 42)
        #expect(AnalyticsCountDecoder.decode(AnalyticsCountDecoder.maximumExactCount) == AnalyticsCountDecoder.maximumExactCount)
        #expect(AnalyticsCountDecoder.validates(["metrics": ["views": 2], "title": "News"]))
        #expect(AnalyticsCountDecoder.validates([:]))
        #expect(!AnalyticsCountDecoder.validates(["items": [["metrics": ["views": Double.nan]]]]))
        #expect(!AnalyticsCountDecoder.validates(["usersByFederalState": ["tirol": true]]))
        #expect(!AnalyticsCountDecoder.validates(["metrics": Dictionary(uniqueKeysWithValues: (0..<100).map { ("metric\($0)", AnalyticsCountDecoder.maximumExactCount) })]))
    }
}
