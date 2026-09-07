import AppIntents
import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct AnnouncementTests {
    private func item() -> UserAnnouncement {
        var item = UserAnnouncement(); item.status = "published"; item.startsAt = 1000; item.expiresAt = 10000
        return item
    }
    @Test func editorSavePersistsBothLanguagesInRepository() async throws {
        let repository = MockAnnouncementRepository()
        var value = UserAnnouncement(); value.title = AnnouncementText(uk: "UK", de: "DE")
        value.body = AnnouncementText(uk: "Текст", de: "Text")
        let saved = try await repository.call("manageAnnouncements", AnnouncementRequest(operation: "save", revision: 0, draft: value))
        #expect(saved.item?.revision == 1)
        let list = try await repository.call("manageAnnouncements", AnnouncementRequest(operation: "list"))
        #expect(list.items?.first?.title.de == "DE")
    }
    @Test func expiryAndUnsupportedContractFailClosed() {
        var value = item()
        #expect(!value.active(at: 999)); #expect(value.active(at: 1000)); #expect(!value.active(at: 10000))
        value.schemaVersion = 2; #expect(!value.active(at: 5000))
        value.schemaVersion = 1; value.mode = "unknown"; #expect(!value.active(at: 5000))
    }
    @Test func onceAndAcknowledgementHaveDifferentRepeatSemantics() {
        var policy = AnnouncementPresentationPolicy(); var value = item()
        #expect(policy.eligible(value, now: 5000, locallyPresented: false, locallyAcknowledged: false))
        #expect(!policy.eligible(value, now: 5000, locallyPresented: true, locallyAcknowledged: false))
        value.mode = "acknowledge"
        #expect(policy.eligible(value, now: 5000, locallyPresented: true, locallyAcknowledged: false))
        policy.shown(value.id)
        #expect(!policy.eligible(value, now: 5000, locallyPresented: true, locallyAcknowledged: false))
        policy.background(at: Date(timeIntervalSince1970: 0)); policy.foreground(at: Date(timeIntervalSince1970: 20))
        #expect(!policy.eligible(value, now: 5000, locallyPresented: true, locallyAcknowledged: false))
        policy.background(at: Date(timeIntervalSince1970: 30)); policy.foreground(at: Date(timeIntervalSince1970: 1830))
        #expect(policy.eligible(value, now: 5000, locallyPresented: true, locallyAcknowledged: false))
        #expect(!policy.eligible(value, now: 5000, locallyPresented: true, locallyAcknowledged: true))
        value.acknowledgedAt = 4000
        #expect(!policy.eligible(value, now: 5000, locallyPresented: false, locallyAcknowledged: false))
    }
    @Test func accountSwitchClearsPrivateState() async {
        let repository = MockAnnouncementRepository()
        var value = UserAnnouncement(); value.status = "published"; value.startsAt -= 1000
        repository.items = [value]
        let suite = "AnnouncementTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = AnnouncementCoordinator(repository: repository, defaults: defaults)
        coordinator.configure(userID: "first", available: true)
        await coordinator.refresh(); coordinator.presentIfPossible(true)
        #expect(coordinator.active != nil)
        coordinator.configure(userID: nil, available: true)
        #expect(coordinator.items.isEmpty); #expect(coordinator.active == nil)
        coordinator.configure(userID: "second", available: false)
        await coordinator.refresh(); #expect(coordinator.items.isEmpty)
    }
    @Test func confirmationSurvivesRestartButIsNotTransferredToAnotherAccount() async {
        let repository = MockAnnouncementRepository()
        var value = UserAnnouncement(); value.status = "published"; value.mode = "acknowledge"; value.startsAt -= 1000
        repository.items = [value]
        let suite = "AnnouncementTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = AnnouncementCoordinator(repository: repository, defaults: defaults)
        first.configure(userID: suite, available: true)
        await first.refresh(); first.presentIfPossible(true)
        #expect(first.active != nil)
        await first.didPresent(value); await first.close(value, acknowledge: true)
        let next = AnnouncementCoordinator(repository: repository, defaults: defaults)
        next.configure(userID: suite, available: true); await next.refresh(); next.presentIfPossible(true)
        #expect(next.active == nil)
        next.configure(userID: suite + "other", available: true); await next.refresh(); next.presentIfPossible(true)
        #expect(next.active != nil)
    }
    @Test func cancelledHistoryFromAnotherDeviceRemainsButCannotOpenAutomatically() async {
        let repository = MockAnnouncementRepository()
        var value = UserAnnouncement(); value.status = "cancelled"; value.presentedAt = 1000; value.startsAt -= 1000
        repository.items = [value]
        let suite = "AnnouncementTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = AnnouncementCoordinator(repository: repository, defaults: defaults)
        coordinator.configure(userID: suite, available: true)
        await coordinator.refresh(); coordinator.presentIfPossible(true)
        #expect(coordinator.items.count == 1); #expect(coordinator.active == nil)
    }
    @Test func publicProjectionDecodesWithoutPrivateFields() throws {
        let json = #"{"id":"a","schemaVersion":1,"revision":1,"title":{"uk":"Тест","de":"Test"},"body":{"uk":"Текст","de":"Text"},"mode":"once","feedback":true,"startsAt":1000,"expiresAt":2000}"#
        let value = try JSONDecoder().decode(UserAnnouncement.self, from: Data(json.utf8))
        #expect(value.userIds.isEmpty); #expect(value.status == "published"); #expect(value.active(at: 1500))
    }
}
