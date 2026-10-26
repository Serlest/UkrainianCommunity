import XCTest
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
@testable import UkrainianCommunity

/// Opt-in real Codable/Callable/Firestore journey on the fixed localhost demo.
@MainActor
final class AnnouncementSDKEmulatorTests: XCTestCase {
    func testReviewedCommandReplayAndCurrentRevisionThroughRealSDK() async throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" else { throw XCTSkip("Fixed local demo only") }
        guard FirebaseApp.app()?.options.projectID == "demo-uac-release-audit",
              Firestore.firestore().settings.host == "127.0.0.1:28080" else { XCTFail("Refusing non-local SDK"); return }
        let uid = "notifications-audit-owner-20261026", auth = Auth.auth()
        try? auth.signOut(); defer { try? auth.signOut() }
        _ = try await auth.signIn(withEmail: uid + "@uac.test", password: "Emulator-Only-2026!")
        let repository = CloudAnnouncementRepository()
        var draft = UserAnnouncement(); draft.id = "n13-command-" + UUID().uuidString
        draft.title = .init(uk: "Перевірка повтору", de: "Wiederholung prüfen")
        draft.body = .init(uk: "Контрольний текст", de: "Kontrolltext")
        draft.startsAt -= 1000; draft.push = false
        let command = AnnouncementRequest(operationId: UUID().uuidString, operation: "save", revision: 0, draft: draft)
        let saved = try await repository.call("manageAnnouncements", command)
        let replay = try await repository.call("manageAnnouncements", command)
        XCTAssertEqual(saved.item?.revision, 1); XCTAssertEqual(replay.item?.revision, 1)
        let stored = try await repository.call("manageAnnouncements", AnnouncementRequest(operation: "get", id: draft.id))
        XCTAssertEqual(stored.item?.reviewedContent, saved.item?.reviewedContent)
        _ = try await repository.call("manageAnnouncements", AnnouncementRequest(operation: "publish", id: draft.id, revision: 1))
        let publishedReplay = try await repository.call("manageAnnouncements", command)
        XCTAssertEqual(publishedReplay.item?.status, "published"); XCTAssertEqual(publishedReplay.item?.revision, 1)
        do {
            _ = try await repository.call("manageAnnouncements", AnnouncementRequest(operation: "cancel", id: draft.id, revision: 7))
            XCTFail("Stale revision must be rejected")
        } catch { XCTAssertEqual((error as NSError).code, 10) }
        _ = try await repository.call("manageAnnouncements", AnnouncementRequest(operation: "cancel", id: draft.id, revision: 1))
        let cancelled = try await repository.call("manageAnnouncements", AnnouncementRequest(operation: "get", id: draft.id))
        XCTAssertEqual(cancelled.item?.status, "cancelled")
        try auth.signOut()
        _ = try await auth.signIn(withEmail: uid + "-other@uac.test", password: "Emulator-Only-2026!")
        do {
            _ = try await repository.call("manageAnnouncements", AnnouncementRequest(operation: "get", id: draft.id))
            XCTFail("Member cannot read owner campaigns")
        } catch { XCTAssertEqual((error as NSError).code, 7) }
    }
    func testOwnerPublishGuestReceiptAndCancellationThroughRealSDK() async throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" else {
            throw XCTSkip("Run against the fixed local demo fixture.")
        }
        XCTAssertEqual(FirebaseApp.app()?.options.projectID, "demo-uac-release-audit")
        guard FirebaseApp.app()?.options.projectID == "demo-uac-release-audit" else { return }
        let run = try XCTUnwrap(ProcessInfo.processInfo.environment["UACCursorFixtureRun"])
        let auth = Auth.auth()
        try? auth.signOut()
        defer { try? auth.signOut() }
        _ = try await auth.signIn(withEmail: "\(run)@uac.test", password: "Emulator-Only-2026!")
        let repository = CloudAnnouncementRepository()
        var draft = UserAnnouncement()
        draft.id = run + "-announcement"
        draft.title = AnnouncementText(uk: "Перевірка SDK", de: "SDK Prüfung")
        draft.body = AnnouncementText(uk: "Повідомлення", de: "Nachricht")
        draft.groups = ["guests", "registered"]; draft.mode = "acknowledge"; draft.startsAt -= 1000
        let saved = try await repository.call("manageAnnouncements", AnnouncementRequest(operation: "save", revision: 0, draft: draft))
        XCTAssertEqual(saved.item?.title.de, draft.title.de)
        let revision = try XCTUnwrap(saved.item?.revision)
        let people = try await repository.users(cursor: nil)
        XCTAssertTrue(people.items.contains { $0.id == run })
        _ = try await repository.call("manageAnnouncements", AnnouncementRequest(operation: "publish", id: draft.id, revision: revision))
        var feed = try await repository.call("getAnnouncements", AnnouncementRequest())
        XCTAssertTrue(feed.items?.contains { $0.id == draft.id && $0.active(at: feed.serverNow!) } == true)
        _ = try await repository.call("acknowledgeAnnouncement", AnnouncementRequest(id: draft.id, event: "presented"))
        _ = try await repository.call("acknowledgeAnnouncement", AnnouncementRequest(id: draft.id, event: "acknowledged"))
        feed = try await repository.call("getAnnouncements", AnnouncementRequest())
        XCTAssertNotNil(feed.items?.first { $0.id == draft.id }?.acknowledgedAt)
        try auth.signOut()
        feed = try await repository.call("getAnnouncements", AnnouncementRequest())
        XCTAssertTrue(feed.items?.contains { $0.id == draft.id && $0.userIds.isEmpty && $0.acknowledgedAt == nil } == true)
        _ = try await repository.call("acknowledgeAnnouncement", AnnouncementRequest(id: draft.id, event: "presented", secret: String(repeating: run, count: 2)))
        do {
            _ = try await repository.call("manageAnnouncements", AnnouncementRequest(operation: "list"))
            XCTFail("Guest must never access owner operations")
        } catch { XCTAssertEqual((error as NSError).code, 16) }
        _ = try await auth.signIn(withEmail: "\(run)@uac.test", password: "Emulator-Only-2026!")
        let stats = try await repository.call("manageAnnouncements", AnnouncementRequest(operation: "stats", id: draft.id))
        XCTAssertEqual(stats.acknowledged, 1); XCTAssertEqual(stats.guestPresented, 1)
        _ = try await repository.call("manageAnnouncements", AnnouncementRequest(operation: "cancel", id: draft.id))
        feed = try await repository.call("getAnnouncements", AnnouncementRequest())
        XCTAssertTrue(feed.items?.contains { $0.id == draft.id && $0.status == "cancelled" && !$0.active(at: feed.serverNow!) } == true)
    }
}
