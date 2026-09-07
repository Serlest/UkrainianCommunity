import XCTest
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
@testable import UkrainianCommunity

/// Opt-in real Codable/Callable/Firestore journey on the fixed localhost demo.
@MainActor
final class AnnouncementSDKEmulatorTests: XCTestCase {
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
