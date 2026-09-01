import Foundation
import Testing
@testable import UkrainianCommunity

#if canImport(FirebaseFunctions)
import FirebaseFunctions
#endif

@MainActor
private final class ToggleableRecordingAnalyticsService: AnalyticsTracking {
    let isCollectionAvailable = true
    private(set) var isCollectionEnabled = false
    private var scopeID: String?
    private let changes = AnalyticsCollectionChanges()
    private var scopeReads = 0
    private var readWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    var collectionScopeID: String? {
        scopeReads += 1
        let ready = readWaiters.filter { $0.0 <= scopeReads }
        readWaiters.removeAll { $0.0 <= scopeReads }
        ready.forEach { $0.1.resume() }
        return scopeID
    }
    private(set) var events: [AppAnalyticsEvent] = []
    private(set) var allTrackedEvents: [AppAnalyticsEvent] = []

    func actionCapture(for event: AppAnalyticsEvent) -> AnalyticsActionCapture? { nil }

    func collectionChanges() -> AsyncStream<Void> { changes.stream() }

    func waitForScopeReads(_ count: Int) async {
        guard scopeReads < count else { return }
        await withCheckedContinuation { readWaiters.append((count, $0)) }
    }

    func beginConsentSynchronization() {
        isCollectionEnabled = true
        scopeID = nil
        changes.notify()
    }

    func confirmConsentSynchronization() {
        scopeID = UUID().uuidString
        changes.notify()
    }

    func repeatCollectionSignal() { changes.notify() }

    func track(_ event: AppAnalyticsEvent, actionCapture: AnalyticsActionCapture?) {
        guard isCollectionEnabled else { return }
        events.append(event)
        allTrackedEvents.append(event)
    }

    func setCollectionEnabled(_ isEnabled: Bool) {
        guard isCollectionEnabled != isEnabled else { return }
        isCollectionEnabled = isEnabled
        if isEnabled {
            scopeID = UUID().uuidString
        } else {
            scopeID = nil
            events.removeAll()
        }
        changes.notify()
    }
}

#if canImport(FirebaseFunctions)
private actor ControlledAnalyticsAggregationDelivery: AnalyticsAggregationDelivering {
    struct Call: Equatable, Sendable {
        let id: UUID
        let request: AnalyticsAggregationRequest
        let expectedPrincipalID: String
    }

    private struct PendingCall {
        let continuation: CheckedContinuation<AnalyticsAggregationResponse, Error>
    }

    private struct CountWaiter {
        let count: Int
        let continuation: CheckedContinuation<Void, Never>
    }

    private struct CompletionWaiter {
        let callID: UUID
        let continuation: CheckedContinuation<Void, Never>
    }

    private var calls: [Call] = []
    private var pendingCalls: [UUID: PendingCall] = [:]
    private var completedCallIDs: Set<UUID> = []
    private var countWaiters: [CountWaiter] = []
    private var completionWaiters: [CompletionWaiter] = []

    func deliver(
        _ request: AnalyticsAggregationRequest,
        session: AnalyticsDeliverySession
    ) async throws -> AnalyticsAggregationResponse {
        let expectedPrincipalID = session.principalID ?? ""
        let call = Call(
            id: UUID(),
            request: request,
            expectedPrincipalID: expectedPrincipalID
        )
        calls.append(call)
        resumeSatisfiedCountWaiters()

        do {
            let response = try await withCheckedThrowingContinuation { continuation in
                pendingCalls[call.id] = PendingCall(continuation: continuation)
            }
            markCompleted(call.id)
            return response
        } catch {
            markCompleted(call.id)
            throw error
        }
    }

    func waitForCallCount(_ count: Int) async {
        guard calls.count < count else { return }
        await withCheckedContinuation { continuation in
            countWaiters.append(CountWaiter(count: count, continuation: continuation))
        }
    }

    func waitForCompletion(of callID: UUID) async {
        guard !completedCallIDs.contains(callID) else { return }
        await withCheckedContinuation { continuation in
            completionWaiters.append(
                CompletionWaiter(callID: callID, continuation: continuation)
            )
        }
    }

    func snapshot() -> [Call] {
        calls
    }

    func succeed(_ callID: UUID) {
        pendingCalls.removeValue(forKey: callID)?.continuation.resume(
            returning: AnalyticsAggregationResponse(tracked: true)
        )
    }

    func fail(_ callID: UUID) {
        pendingCalls.removeValue(forKey: callID)?.continuation.resume(
            throwing: TestDeliveryError.transient
        )
    }

    private func markCompleted(_ callID: UUID) {
        completedCallIDs.insert(callID)
        let satisfiedWaiters = completionWaiters.filter { $0.callID == callID }
        completionWaiters.removeAll { $0.callID == callID }
        for waiter in satisfiedWaiters {
            waiter.continuation.resume()
        }
    }

    private func resumeSatisfiedCountWaiters() {
        let satisfiedWaiters = countWaiters.filter { calls.count >= $0.count }
        countWaiters.removeAll { calls.count >= $0.count }
        for waiter in satisfiedWaiters {
            waiter.continuation.resume()
        }
    }
}

private actor PermanentFailureAnalyticsAggregationDelivery: AnalyticsAggregationDelivering {
    private(set) var deliveredContentIDs: [String] = []

    func deliver(
        _ request: AnalyticsAggregationRequest,
        session: AnalyticsDeliverySession
    ) async throws -> AnalyticsAggregationResponse {
        let contentID = request.parameters[AnalyticsParameterName.contentID.rawValue] ?? ""
        deliveredContentIDs.append(contentID)
        if contentID == "poison" {
            throw NSError(
                domain: FunctionsErrorDomain,
                code: FunctionsErrorCode.invalidArgument.rawValue
            )
        }
        return AnalyticsAggregationResponse(tracked: true)
    }

    func snapshot() -> [String] {
        deliveredContentIDs
    }
}

private actor RecoveringAnalyticsAggregationDelivery: AnalyticsAggregationDelivering {
    private var shouldFail = true
    private var deliveredContentIDs: [String] = []

    func deliver(
        _ request: AnalyticsAggregationRequest,
        session: AnalyticsDeliverySession
    ) async throws -> AnalyticsAggregationResponse {
        let contentID = request.parameters[AnalyticsParameterName.contentID.rawValue] ?? ""
        deliveredContentIDs.append(contentID)
        if shouldFail, contentID == "transient" {
            throw TestDeliveryError.transient
        }
        return AnalyticsAggregationResponse(tracked: true)
    }

    func setShouldFail(_ shouldFail: Bool) {
        self.shouldFail = shouldFail
    }

    func snapshot() -> [String] {
        deliveredContentIDs
    }
}

private actor ClockAdvancingTransientAnalyticsDelivery: AnalyticsAggregationDelivering {
    private let clock: AnalyticsTestClock
    private var deliveredContentIDs: [String] = []

    init(clock: AnalyticsTestClock) {
        self.clock = clock
    }

    func deliver(
        _ request: AnalyticsAggregationRequest,
        session: AnalyticsDeliverySession
    ) async throws -> AnalyticsAggregationResponse {
        let contentID = request.parameters[AnalyticsParameterName.contentID.rawValue] ?? ""
        deliveredContentIDs.append(contentID)
        if deliveredContentIDs.count == 1 {
            clock.advance(by: 10)
            throw TestDeliveryError.transient
        }
        return AnalyticsAggregationResponse(tracked: true)
    }

    func snapshot() -> [String] {
        deliveredContentIDs
    }
}

nonisolated private final class AnalyticsTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(date: Date) {
        self.date = date
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return date
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        date = date.addingTimeInterval(interval)
        lock.unlock()
    }
}

private enum TestDeliveryError: Error {
    case transient
}
#endif

@MainActor
struct AnalyticsDeliveryConsistencyTests {
    @Test func consentKeepsDisclosureLanguageAcrossDeferredVerificationAndRestart() throws {
        let suite = "AnalyticsConsentLocale.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let previousLanguage = LocalizationStore.language
        defer {
            defaults.removePersistentDomain(forName: suite)
            LocalizationStore.language = previousLanguage
        }
        let consent = AnalyticsConsentService(userDefaults: defaults)
        LocalizationStore.language = .ukrainian
        consent.setAnalyticsEnabled(true, for: "new-user")
        let consentID = consent.analyticsConsentID(for: "new-user")
        LocalizationStore.language = .german
        let restored = AnalyticsConsentService(userDefaults: defaults)
        #expect(restored.analyticsConsentLocale(for: "new-user") == "uk")
        #expect(restored.analyticsConsentID(for: "new-user") == consentID)
        #expect(restored.analyticsConsentLocale(for: "another-user") == nil)
        restored.setAnalyticsEnabled(false, for: "new-user")
        #expect(restored.analyticsConsentLocale(for: "new-user") == nil)
        restored.setAnalyticsEnabled(true, for: "new-user")
        #expect(restored.analyticsConsentLocale(for: "new-user") == "de")
        #expect(restored.analyticsConsentID(for: "new-user") != consentID)
    }

    @Test func legacyGlobalConsentRequiresFreshPerPrincipalOptIn() {
        let suiteName = "AnalyticsPrincipalConsentTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "analyticsCollectionEnabled")

        let service = AnalyticsConsentService(userDefaults: defaults)

        #expect(defaults.object(forKey: "analyticsCollectionEnabled") == nil)
        #expect(service.isAnalyticsEnabled(for: nil) == false)
        #expect(service.isAnalyticsEnabled(for: "user-a") == false)
        #expect(service.isAnalyticsEnabled(for: "user-b") == false)

        service.setAnalyticsEnabled(true, for: nil)
        let guestConsentID = service.analyticsConsentID(for: nil)
        #expect(guestConsentID == nil)
        #expect(service.isAnalyticsEnabled(for: nil) == false)
        #expect(service.isAnalyticsEnabled(for: "user-a") == false)

        service.setAnalyticsEnabled(true, for: "user-a")
        let firstUserAConsentID = service.analyticsConsentID(for: "user-a")
        #expect(firstUserAConsentID != nil)
        let restoredService = AnalyticsConsentService(userDefaults: defaults)
        #expect(restoredService.isAnalyticsEnabled(for: "user-a") == true)
        #expect(restoredService.isAnalyticsEnabled(for: "user-b") == false)

        restoredService.setAnalyticsEnabled(true, for: "user-b")
        restoredService.setAnalyticsEnabled(false, for: "user-a")
        #expect(restoredService.isAnalyticsEnabled(for: "user-a") == false)
        #expect(restoredService.isAnalyticsEnabled(for: "user-b") == true)
        restoredService.setAnalyticsEnabled(true, for: "user-a")
        #expect(restoredService.analyticsConsentID(for: "user-a") != firstUserAConsentID)

        let storedConsent = defaults.dictionary(
            forKey: "analyticsCollectionConsentByPrincipal.v1"
        ) ?? [:]
        #expect(!storedConsent.keys.contains("user-a"))
    }

    @Test func viewDeduplicationIsScopedToTheCurrentOptInGeneration() async throws {
        let analytics = ToggleableRecordingAnalyticsService()
        let news = try await MockNewsRepository().fetchNews()
        let events = try await MockEventRepository().fetchEvents()
        let organizations = try await MockOrganizationRepository().fetchOrganizations()
        let post = try #require(news.first)
        let event = try #require(events.first)
        let organization = try #require(organizations.first)
        let newsViewModel = NewsViewModel(
            repository: MockNewsRepository(),
            analyticsService: analytics
        )
        let eventsViewModel = EventsViewModel(
            repository: MockEventRepository(),
            analyticsService: analytics
        )
        let organizationsViewModel = OrganizationsViewModel(
            repository: MockOrganizationRepository(),
            analyticsService: analytics
        )

        newsViewModel.trackViewIfNeeded(for: post)
        eventsViewModel.trackViewIfNeeded(for: event)
        organizationsViewModel.trackViewIfNeeded(for: organization)
        #expect(analytics.events.isEmpty)

        analytics.setCollectionEnabled(true)
        newsViewModel.trackViewIfNeeded(for: post)
        eventsViewModel.trackViewIfNeeded(for: event)
        organizationsViewModel.trackViewIfNeeded(for: organization)
        #expect(analytics.events.map(\.name) == [.newsView, .eventView, .organizationView])

        newsViewModel.trackViewIfNeeded(for: post)
        eventsViewModel.trackViewIfNeeded(for: event)
        organizationsViewModel.trackViewIfNeeded(for: organization)
        #expect(analytics.events.count == 3)

        let firstScopeID = try #require(analytics.collectionScopeID)
        analytics.setCollectionEnabled(false)
        #expect(analytics.events.isEmpty)
        analytics.setCollectionEnabled(true)
        #expect(analytics.collectionScopeID != firstScopeID)

        newsViewModel.trackViewIfNeeded(for: post)
        eventsViewModel.trackViewIfNeeded(for: event)
        organizationsViewModel.trackViewIfNeeded(for: organization)
        #expect(analytics.events.map(\.name) == [.newsView, .eventView, .organizationView])
        #expect(analytics.allTrackedEvents.count == 6)
    }

    @Test(.timeLimit(.minutes(1))) func visibleDetailsRetryAfterConsentConfirmationWithoutDuplicates() async throws {
        let analytics = ToggleableRecordingAnalyticsService()
        analytics.beginConsentSynchronization()
        let post = try #require(try await MockNewsRepository().fetchNews().first)
        let event = try #require(try await MockEventRepository().fetchEvents().first)
        let organization = try #require(try await MockOrganizationRepository().fetchOrganizations().first)
        let news = NewsViewModel(repository: MockNewsRepository(), analyticsService: analytics)
        let events = EventsViewModel(repository: MockEventRepository(), analyticsService: analytics)
        let organizations = OrganizationsViewModel(repository: MockOrganizationRepository(), analyticsService: analytics)
        let tasks = [
            Task { await news.trackViewWhileVisible(for: post) },
            Task { await events.trackViewWhileVisible(for: event) },
            Task { await organizations.trackViewWhileVisible(for: organization) }
        ]
        defer { tasks.forEach { $0.cancel() } }
        await analytics.waitForScopeReads(3)
        #expect(analytics.allTrackedEvents.isEmpty)

        analytics.confirmConsentSynchronization()
        await analytics.waitForScopeReads(6)
        #expect(Set(analytics.events.map(\.name)) == [.newsView, .eventView, .organizationView])
        #expect(analytics.allTrackedEvents.count == 3)
        analytics.repeatCollectionSignal()
        await analytics.waitForScopeReads(9)
        #expect(analytics.allTrackedEvents.count == 3)

        analytics.setCollectionEnabled(false)
        await analytics.waitForScopeReads(12)
        #expect(analytics.allTrackedEvents.count == 3)
        tasks.forEach { $0.cancel() }
        for task in tasks { await task.value }
        analytics.setCollectionEnabled(true)
        #expect(analytics.allTrackedEvents.count == 3)
    }

    @Test(.timeLimit(.minutes(1))) func dismissedDetailDoesNotRecordWhenConsentFinishesLater() async throws {
        let analytics = ToggleableRecordingAnalyticsService()
        analytics.beginConsentSynchronization()
        let organization = try #require(try await MockOrganizationRepository().fetchOrganizations().first)
        let model = OrganizationsViewModel(repository: MockOrganizationRepository(), analyticsService: analytics)
        let task = Task { await model.trackViewWhileVisible(for: organization) }
        await analytics.waitForScopeReads(1)
        task.cancel()
        analytics.confirmConsentSynchronization()
        await task.value
        #expect(analytics.allTrackedEvents.isEmpty)
    }

    #if canImport(FirebaseFunctions)
    @Test func installationGuestConsentNeverAuthorizesAggregateDelivery() {
        let authorization = AnalyticsDeliveryAuthorization()
        let guestSession = authorization.transition(
            principalID: nil,
            consentID: "installation-consent"
        )

        #expect(guestSession.isEnabled == false)
        #expect(authorization.allowsDelivery(for: guestSession) == false)
    }

    @Test func accountSwitchStartsNewPrincipalWithoutWaitingForStaleDelivery() async throws {
        let suiteName = "AnalyticsOutboxSwitchTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let delivery = ControlledAnalyticsAggregationDelivery()
        let authorization = AnalyticsDeliveryAuthorization()
        let outbox = AnalyticsAggregationOutbox(
            delivery: delivery,
            authorization: authorization,
            userDefaults: defaults
        )
        let userASession = authorization.transition(
            principalID: "user-a",
            consentID: "consent-a"
        )
        await outbox.transition(to: userASession)

        await outbox.enqueue(try Self.request(contentID: "from-a"), session: userASession)
        await delivery.waitForCallCount(1)
        let userACall = try #require((await delivery.snapshot()).first)
        let persistedData = try #require(defaults.data(forKey: "analyticsAggregateOutbox.v1"))
        let persistedJSON = try #require(String(data: persistedData, encoding: .utf8))
        #expect(!persistedJSON.contains("user-a"))

        let userBSession = authorization.transition(
            principalID: "user-b",
            consentID: "consent-b"
        )
        await outbox.transition(to: userBSession)
        await outbox.enqueue(try Self.request(contentID: "from-b"), session: userBSession)
        await delivery.waitForCallCount(2)
        let calls = await delivery.snapshot()
        let userBCall = calls[1]

        #expect(userACall.expectedPrincipalID == "user-a")
        #expect(userBCall.expectedPrincipalID == "user-b")
        #expect(userBCall.request.parameters["content_id"] == "from-b")

        // The stale A continuation deliberately completes while B is still
        // pending. It must neither consume nor block B's entry.
        await delivery.succeed(userACall.id)
        await delivery.waitForCompletion(of: userACall.id)
        #expect(await outbox.pendingEntryCount() == 1)

        await delivery.succeed(userBCall.id)
        await delivery.waitForCompletion(of: userBCall.id)
        await outbox.waitForDrain(toCompleteFor: userBSession)
        #expect(await outbox.pendingEntryCount() == 0)
    }

    @Test func samePrincipalStaleFailureCannotCrossOptOutBarrier() async throws {
        let suiteName = "AnalyticsOutboxOptOutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let delivery = ControlledAnalyticsAggregationDelivery()
        let authorization = AnalyticsDeliveryAuthorization()
        let outbox = AnalyticsAggregationOutbox(
            delivery: delivery,
            authorization: authorization,
            userDefaults: defaults
        )
        let oldSession = authorization.transition(
            principalID: "same-user",
            consentID: "old-consent"
        )
        await outbox.transition(to: oldSession)
        await outbox.enqueue(try Self.request(contentID: "old"), session: oldSession)
        await delivery.waitForCallCount(1)
        let oldCall = try #require((await delivery.snapshot()).first)

        let disabledSession = authorization.transition(
            principalID: "same-user",
            consentID: nil
        )
        // Re-enable before the actor receives the disabled transition. The new
        // consent epoch itself must still invalidate the old persisted entry.
        let newSession = authorization.transition(
            principalID: "same-user",
            consentID: "new-consent"
        )
        await outbox.transition(to: newSession)
        #expect(await outbox.pendingEntryCount() == 0)
        await outbox.enqueue(try Self.request(contentID: "new"), session: newSession)
        await delivery.waitForCallCount(2)
        let newCall = (await delivery.snapshot())[1]

        // A delayed clear from the prior disabled generation cannot erase the
        // newly consented entry either.
        await outbox.transition(to: disabledSession)
        #expect(await outbox.pendingEntryCount() == 1)

        await delivery.fail(oldCall.id)
        await delivery.waitForCompletion(of: oldCall.id)
        #expect(await outbox.pendingEntryCount() == 1)

        // A late enqueue carrying the pre-opt-out generation is rejected too.
        await outbox.enqueue(try Self.request(contentID: "stale"), session: oldSession)
        #expect(await outbox.pendingEntryCount() == 1)

        await delivery.succeed(newCall.id)
        await delivery.waitForCompletion(of: newCall.id)
        await outbox.waitForDrain(toCompleteFor: newSession)
        #expect(await outbox.pendingEntryCount() == 0)
        #expect(await delivery.snapshot().count == 2)
    }

    @Test func analyticsFailureDiagnosticsExcludeSensitiveErrorDetails() {
        let error = NSError(domain: "com.google.firebase.appCheck", code: 0, userInfo: [
            NSLocalizedDescriptionKey: "secret-token and private-content",
            NSUnderlyingErrorKey: NSError(domain: "com.apple.devicecheck", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "private-response"])
        ])
        let diagnostic = AnalyticsDeliveryFailureDiagnostic(error: error)
        #expect(diagnostic.domain == "com.google.firebase.appCheck")
        #expect(diagnostic.code == 0)
        #expect(diagnostic.underlyingCodes == "com.apple.devicecheck:3")
        #expect(!String(describing: diagnostic).contains("secret-token"))
        #expect(!String(describing: diagnostic).contains("private-"))
    }

    @Test func permanentFailureDropsPoisonEntryAndContinuesWithNewerEvent() async throws {
        let suiteName = "AnalyticsOutboxRetryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let delivery = PermanentFailureAnalyticsAggregationDelivery()
        let authorization = AnalyticsDeliveryAuthorization()
        let outbox = AnalyticsAggregationOutbox(
            delivery: delivery,
            authorization: authorization,
            userDefaults: defaults
        )
        let session = authorization.transition(
            principalID: "user-a",
            consentID: "consent-a"
        )
        await outbox.transition(to: session)

        await outbox.enqueue(try Self.request(contentID: "poison"), session: session)
        await outbox.enqueue(try Self.request(contentID: "healthy"), session: session)
        await outbox.waitForDrain(toCompleteFor: session)

        #expect(await delivery.snapshot() == ["poison", "healthy"])
        #expect(await outbox.pendingEntryCount() == 0)
    }

    @Test func transientFailurePersistsWithoutBlockingAndRecoversAfterReinit() async throws {
        let suiteName = "AnalyticsOutboxTransientTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let clock = AnalyticsTestClock(date: Date(timeIntervalSince1970: 10_000))
        let delivery = RecoveringAnalyticsAggregationDelivery()
        let authorization = AnalyticsDeliveryAuthorization()
        let session = authorization.transition(
            principalID: "user-a",
            consentID: "consent-a"
        )
        let firstOutbox = AnalyticsAggregationOutbox(
            delivery: delivery,
            authorization: authorization,
            userDefaults: defaults,
            now: { clock.now() }
        )
        await firstOutbox.transition(to: session)

        await firstOutbox.enqueue(try Self.request(contentID: "transient"), session: session)
        await firstOutbox.waitForDrain(toCompleteFor: session)
        #expect(await firstOutbox.pendingEntryCount() == 1)

        await firstOutbox.enqueue(try Self.request(contentID: "healthy"), session: session)
        await firstOutbox.waitForDrain(toCompleteFor: session)
        #expect(await delivery.snapshot() == ["transient", "healthy"])
        #expect(await firstOutbox.pendingEntryCount() == 1)

        // Model a process restart by invalidating the old synchronous
        // authorization fence while leaving the persisted entry untouched.
        // Otherwise the old outbox's scheduled retry can race the restored
        // outbox and make this test depend on wall-clock scheduling.
        _ = authorization.transition(principalID: nil, consentID: nil)
        let restoredAuthorization = AnalyticsDeliveryAuthorization()
        let restoredSession = restoredAuthorization.transition(
            principalID: "user-a",
            consentID: "consent-a"
        )
        let restoredOutbox = AnalyticsAggregationOutbox(
            delivery: delivery,
            authorization: restoredAuthorization,
            userDefaults: defaults,
            now: { clock.now() }
        )
        await restoredOutbox.transition(to: restoredSession)
        await restoredOutbox.waitForDrain(toCompleteFor: restoredSession)
        #expect(await delivery.snapshot() == ["transient", "healthy"])

        await delivery.setShouldFail(false)
        clock.advance(by: 3)
        await restoredOutbox.transition(to: restoredSession)
        await restoredOutbox.waitForDrain(toCompleteFor: restoredSession)
        #expect(await delivery.snapshot() == ["transient", "healthy", "transient"])
        #expect(await restoredOutbox.pendingEntryCount() == 0)
    }

    @Test func transientFailureRetriesWhileTheAppRemainsIdleInForeground() async throws {
        let suiteName = "AnalyticsOutboxScheduledRetryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let clock = AnalyticsTestClock(date: Date(timeIntervalSince1970: 30_000))
        let delivery = ControlledAnalyticsAggregationDelivery()
        let authorization = AnalyticsDeliveryAuthorization()
        let outbox = AnalyticsAggregationOutbox(
            delivery: delivery,
            authorization: authorization,
            userDefaults: defaults,
            now: { clock.now() },
            retrySleep: { _ in clock.advance(by: 3) }
        )
        let session = authorization.transition(
            principalID: "user-a",
            consentID: "consent-a"
        )
        await outbox.transition(to: session)
        await outbox.enqueue(try Self.request(contentID: "transient"), session: session)

        await delivery.waitForCallCount(1)
        let firstCall = try #require((await delivery.snapshot()).first)
        await delivery.fail(firstCall.id)
        await delivery.waitForCompletion(of: firstCall.id)

        await delivery.waitForCallCount(2)
        let retryCall = try #require((await delivery.snapshot()).last)
        await delivery.succeed(retryCall.id)
        await delivery.waitForCompletion(of: retryCall.id)
        await outbox.waitForDrain(toCompleteFor: session)

        #expect(await outbox.pendingEntryCount() == 0)
    }

    @Test func transientBackoffStartsAfterTheFailedRequestCompletes() async throws {
        let suiteName = "AnalyticsOutboxFailureClockTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let clock = AnalyticsTestClock(date: Date(timeIntervalSince1970: 40_000))
        let delivery = ClockAdvancingTransientAnalyticsDelivery(clock: clock)
        let authorization = AnalyticsDeliveryAuthorization()
        let outbox = AnalyticsAggregationOutbox(
            delivery: delivery,
            authorization: authorization,
            userDefaults: defaults,
            now: { clock.now() },
            retrySleep: { _ in
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        )
        let session = authorization.transition(
            principalID: "user-a",
            consentID: "consent-a"
        )
        await outbox.transition(to: session)
        await outbox.enqueue(try Self.request(contentID: "delayed-failure"), session: session)
        await outbox.waitForDrain(toCompleteFor: session)

        #expect(await delivery.snapshot() == ["delayed-failure"])
        #expect(await outbox.pendingEntryCount() == 1)
    }

    @Test func transientEntryExpiresAfterFortyEightHours() async throws {
        let suiteName = "AnalyticsOutboxTTLTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let clock = AnalyticsTestClock(date: Date(timeIntervalSince1970: 20_000))
        let delivery = RecoveringAnalyticsAggregationDelivery()
        let authorization = AnalyticsDeliveryAuthorization()
        let session = authorization.transition(
            principalID: "user-a",
            consentID: "consent-a"
        )
        let firstOutbox = AnalyticsAggregationOutbox(
            delivery: delivery,
            authorization: authorization,
            userDefaults: defaults,
            now: { clock.now() }
        )
        await firstOutbox.transition(to: session)
        await firstOutbox.enqueue(try Self.request(contentID: "transient"), session: session)
        await firstOutbox.waitForDrain(toCompleteFor: session)
        #expect(await firstOutbox.pendingEntryCount() == 1)

        clock.advance(by: 48 * 60 * 60 + 1)
        let restoredOutbox = AnalyticsAggregationOutbox(
            delivery: delivery,
            authorization: authorization,
            userDefaults: defaults,
            now: { clock.now() }
        )
        await restoredOutbox.transition(to: session)
        await restoredOutbox.waitForDrain(toCompleteFor: session)

        #expect(await restoredOutbox.pendingEntryCount() == 0)
        #expect(await delivery.snapshot() == ["transient"])
    }
    #endif

    private static func request(contentID: String) throws -> AnalyticsAggregationRequest {
        try #require(AnalyticsAggregationRequest(
            event: AppAnalyticsEvent(
                name: .newsView,
                parameters: [.contentID: .string(contentID)]
            ),
            consentID: "123e4567-e89b-42d3-a456-426614174000",
            occurredAt: Date(timeIntervalSince1970: 1)
        ))
    }
}
