import XCTest
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
@testable import UkrainianCommunity

@MainActor final class NotificationInboxSDKEmulatorTests: XCTestCase {
    func testNotificationPreferencesPersistAndRejectForeignWritesThroughRealSDK() async throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" else { throw XCTSkip("Fixed local demo only") }
        guard FirebaseApp.app()?.options.projectID == "demo-uac-release-audit",
              Firestore.firestore().settings.host == "127.0.0.1:28080" else { XCTFail("Refusing non-local SDK"); return }
        let uid = "notifications-audit-owner-20261026", auth = Auth.auth()
        try? auth.signOut(); defer { try? auth.signOut() }
        _ = try await auth.signIn(withEmail: uid + "@uac.test", password: "Emulator-Only-2026!")
        let repository = FirestoreNotificationPreferencesRepository()
        let settings = NotificationPreferences(notificationsEnabled: true, eventRemindersEnabled: false, reminderLeadMinutes: 30, updatedAt: nil)
        try await repository.saveNotificationPreferences(settings, userID: uid)
        let reopened = try await repository.fetchNotificationPreferences(userID: uid)
        XCTAssertTrue(reopened.notificationsEnabled); XCTAssertFalse(reopened.eventRemindersEnabled)
        XCTAssertEqual(reopened.reminderLeadMinutes, 30); XCTAssertNotNil(reopened.updatedAt)
        let server = try await Firestore.firestore().collection("users").document(uid).collection("notificationPreferences").document("settings").getDocument(source: .server)
        XCTAssertEqual(server.get("notificationsEnabled") as? Bool, true)
        XCTAssertEqual(server.get("eventRemindersEnabled") as? Bool, false)
        do {
            try await repository.saveNotificationPreferences(settings, userID: uid + "-other")
            XCTFail("Foreign notification preferences cannot be changed")
        } catch { XCTAssertEqual((error as NSError).code, 7) }
        try await repository.saveNotificationPreferences(.default, userID: uid)
    }
    func testPrivateInboxExactIDsCursorReceiptsArchiveAndBulkCutoffThroughRealSDK() async throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" else { throw XCTSkip("Fixed local demo only") }
        guard FirebaseApp.app()?.options.projectID == "demo-uac-release-audit",
              Firestore.firestore().settings.host == "127.0.0.1:28080" else { XCTFail("Refusing non-local SDK"); return }
        let uid = "notifications-audit-owner-20261026", auth = Auth.auth()
        try? auth.signOut(); defer { try? auth.signOut() }
        _ = try await auth.signIn(withEmail: uid + "@uac.test", password: "Emulator-Only-2026!")
        let repository = FirestoreNotificationInboxRepository()
        let first = try await repository.fetchNotification(userID: uid, notificationID: "n13-000")
        XCTAssertEqual(first.id, "n13-000"); XCTAssertEqual(first.recipientUserId, uid)
        let initialCount = try await repository.fetchUnreadCount(userID: uid)
        XCTAssertEqual(initialCount, 461)
        var cursor: NotificationInboxCursor?, ids: [String] = [], hasMore = true
        while hasMore {
            let page = try await repository.fetchNotificationPage(userID: uid, unreadOnly: false, limit: 50, after: cursor)
            ids += page.items.map(\.id); cursor = page.nextCursor; hasMore = page.hasMore
            XCTAssertLessThanOrEqual(ids.count, 461)
        }
        XCTAssertEqual(ids.count, 461); XCTAssertEqual(Set(ids).count, 461)
        try await repository.archiveNotification(userID: uid, notificationID: first.id)
        let archived = try await repository.fetchNotification(userID: uid, notificationID: first.id)
        XCTAssertTrue(archived.isArchived); XCTAssertFalse(archived.countsAsUnread)
        try await repository.restoreNotification(userID: uid, notificationID: first.id)
        try await repository.markNotificationUnread(userID: uid, notificationID: first.id)
        let unread = try await repository.fetchNotification(userID: uid, notificationID: first.id)
        XCTAssertTrue(unread.countsAsUnread)
        try await repository.markAllNotificationsRead(userID: uid)
        let afterMark = try await repository.fetchUnreadCount(userID: uid)
        XCTAssertEqual(afterMark, 1, "Future arrival must survive the bulk cutoff across two write pages")
        try await repository.deleteNotification(userID: uid, notificationID: first.id)
        do { _ = try await repository.fetchNotification(userID: uid, notificationID: first.id); XCTFail("Tombstone must not open") }
        catch { XCTAssertEqual(error as? AppError, .notFound) }
        do { _ = try await repository.fetchNotification(userID: uid, notificationID: "absent"); XCTFail("Missing must not open") }
        catch { XCTAssertEqual(error as? AppError, .notFound) }
        do { _ = try await repository.fetchNotification(userID: uid + "-other", notificationID: "n13-000"); XCTFail("Foreign inbox must be denied") }
        catch { XCTAssertEqual(error as? AppError, .permissionDenied) }
        try await repository.clearNotifications(userID: uid)
        let remaining = try await repository.fetchNotificationPage(userID: uid, unreadOnly: false, limit: 500, after: nil)
        XCTAssertEqual(remaining.items.filter(\.isVisibleInInbox).map(\.id), ["n13-460"])
        let tombstones = try await Firestore.firestore().collection("users").document(uid).collection("notificationInbox").whereField("deletedAt", isNotEqualTo: NSNull()).getDocuments(source: .server)
        XCTAssertEqual(tombstones.documents.count, 460)
    }
}
