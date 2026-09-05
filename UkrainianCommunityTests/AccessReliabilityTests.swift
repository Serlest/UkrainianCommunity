import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct AccessReliabilityTests {
    @Test func gracePeriodIsOptionalBoundedAndNeverCrossesAccounts() async throws {
        let suite = "AccessReliability.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var time: TimeInterval = 100
        let lock = AppLockService(defaults: defaults, authentication: ReliableLocalAuthentication(), now: { time })
        lock.updateSession(userID: "a", passwordAuthenticated: true)
        await lock.setEnabled(true)
        #expect(lock.gracePeriod == 0)
        lock.setGracePeriod(60)
        lock.enterBackground()
        time += 10
        lock.becomeActive()
        #expect(!lock.isLocked)
        lock.enterBackground()
        time += 60
        lock.becomeActive()
        #expect(lock.isLocked)
        await lock.unlock()
        lock.enterBackground()
        lock.updateSession(userID: "b", passwordAuthenticated: true)
        lock.updateSession(userID: "a")
        lock.becomeActive()
        #expect(lock.isLocked)
        let restored = AppLockService(defaults: defaults, authentication: ReliableLocalAuthentication())
        restored.updateSession(userID: "a")
        #expect(restored.gracePeriod == 60)
        #expect(restored.isLocked)
    }

    @Test func immediateLockAndFreshPasswordLoginRemainCompatible() async {
        let defaults = UserDefaults(suiteName: "AccessImmediate.\(UUID().uuidString)")!
        let lock = AppLockService(defaults: defaults, authentication: ReliableLocalAuthentication())
        lock.updateSession(userID: "a", passwordAuthenticated: true)
        await lock.setEnabled(true)
        lock.enterBackground()
        #expect(lock.isLocked)
        lock.becomeActive()
        lock.updateSession(userID: "a", passwordAuthenticated: true)
        #expect(!lock.isLocked)
        lock.setGracePeriod(3600)
        #expect(lock.gracePeriod == 0)
    }

    @Test func notificationCleanupFollowsAnInflightOldAccountAddBeforeNewWork() async throws {
        var events: [String] = []
        let session = LocalReminderSession(cleanup: { uid in events.append("cleanup:\(uid ?? "guest")") })
        session.transition(to: "a")
        await session.waitUntilIdle()
        var resume: CheckedContinuation<Void, Never>?
        let old = Task {
            try await session.perform(for: "a") {
                events.append("old:start")
                await withCheckedContinuation { resume = $0 }
                events.append("old:finish")
            }
        }
        while resume == nil { await Task.yield() }
        session.transition(to: nil)
        session.transition(to: "b")
        let new = Task { try await session.perform(for: "b") { events.append("new:add") } }
        resume?.resume()
        do { try await old.value; Issue.record("Old work must be invalidated") } catch is CancellationError {} catch { throw error }
        try await new.value
        #expect(events == ["cleanup:a", "old:start", "old:finish", "cleanup:guest", "cleanup:b", "new:add"])
    }

    @Test func consentVersionsBelongToTheOriginalChoiceAndAreClearedOnWithdrawal() throws {
        let suite = "ConsentVersions.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = AnalyticsConsentService(userDefaults: defaults)
        service.setAnalyticsEnabled(true, for: "a")
        let originalID = service.analyticsConsentID(for: "a")
        let versions = try #require(service.analyticsConsentVersions(for: "a"))
        #expect(versions.privacyVersion == AuthService.currentPrivacyVersion)
        service.setAnalyticsEnabled(true, for: "a")
        #expect(service.analyticsConsentID(for: "a") == originalID)
        #expect(service.analyticsConsentVersions(for: "b") == nil)
        service.setAnalyticsEnabled(false, for: "a")
        #expect(service.analyticsConsentVersions(for: "a") == nil)
        service.setAnalyticsEnabled(true, for: "a")
        #expect(service.analyticsConsentID(for: "a") != originalID)
    }

    @Test func legalExportContainsTheWholeHistoryIndependentOfTheVisibleFilter() async throws {
        let account = LegalEvidenceAccount(userID: "fixture", displayName: "Fixture", email: nil, createdAt: nil)
        let model = LegalEvidenceUserViewModel(account: account, repository: UITestLegalEvidenceRepository())
        await model.load()
        model.filter = .privacy
        #expect(model.filteredEvents.isEmpty)
        let json = try #require(model.exportText).data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let events = try decoder.decode([LegalEvidenceEvent].self, from: json)
        #expect(events.count == 501)
    }

    @Test func photoCommitWithLostResponseReturnsTheSavedPhotoWithoutDuplicating() async throws {
        var commits = 0
        var saved: String?
        let result = try await PhotoMutationRecovery.commit(
            isCurrent: { true }, readCommitted: { saved }, shouldRetry: { _ in true },
            mutation: { commits += 1; saved = "canonical-photo"; throw URLError(.timedOut) }
        )
        #expect(result == "canonical-photo")
        #expect(commits == 1)
    }

    @Test func photoRetryIsBoundedAndNeverLeaksIntoAnotherAccount() async {
        var commits = 0
        do {
            let _: String = try await PhotoMutationRecovery.commit(
                isCurrent: { true }, readCommitted: { nil }, shouldRetry: { _ in true },
                mutation: { commits += 1; throw URLError(.notConnectedToInternet) }
            )
            Issue.record("An unknown outcome must remain an error")
        } catch {}
        #expect(commits == 2)
        var current = true
        commits = 0
        do {
            let _: String = try await PhotoMutationRecovery.commit(
                isCurrent: { current }, readCommitted: { "old-account-photo" }, shouldRetry: { _ in true },
                mutation: { commits += 1; current = false; throw URLError(.timedOut) }
            )
            Issue.record("An old account result must not be published")
        } catch is CancellationError {} catch { Issue.record("Unexpected error: \(error)") }
        #expect(commits == 1)
    }

    @Test func synchronousCancellationKeepsItsPlaceBeforeImmediateRescheduling() async throws {
        let session = LocalReminderSession(cleanup: { _ in })
        session.transition(to: "a")
        var actions: [String] = []
        session.enqueue(for: "a") { actions.append("cancel") }
        try await session.perform(for: "a") { actions.append("schedule") }
        #expect(actions == ["cancel", "schedule"])
    }

    @Test func anOldUserCannotScheduleAfterAccountSwitch() async {
        let session = LocalReminderSession(cleanup: { _ in })
        session.transition(to: "b")
        var ran = false
        do { try await session.perform(for: "a") { ran = true } } catch {}
        #expect(!ran)
    }
}

@MainActor
private final class ReliableLocalAuthentication: LocalAuthenticationProviding {
    let biometry: AppBiometry = .faceID
    func authenticate(reason: String) async throws -> Bool { true }
    func cancel() {}
}
