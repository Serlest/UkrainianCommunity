import XCTest
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseFunctions
import FirebaseStorage
@testable import UkrainianCommunity

/// Run serially with scripts/seed-cursor-sdk-emulators.cjs; ordinary unit runs skip.
@MainActor
final class FirestoreRepositoryCursorEmulatorTests: XCTestCase {
    func testActualRepositoryPagesPreserveExactSnapshotCursors() async throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" else {
            throw XCTSkip("Opt in only against the fixed local demo emulators.")
        }
        #if DEBUG && targetEnvironment(simulator)
        let app = try XCTUnwrap(FirebaseApp.app(), "LocalFirebaseEmulatorConfiguration must configure the host")
        guard app.options.projectID == LocalFirebaseEmulatorConfiguration.projectID,
              app.options.projectID == "demo-uac-release-audit" else {
            XCTFail("Refusing non-demo Firebase app")
            return
        }
        let database = Firestore.firestore()
        guard database.settings.host == "127.0.0.1:28080", !database.settings.isSSLEnabled else {
            XCTFail("Refusing non-loopback Firestore endpoint")
            return
        }
        // Auth has no public emulator endpoint getter. Pin every remaining SDK
        // transport before any request; never fall back to a configured live host.
        let auth = Auth.auth()
        auth.useEmulator(withHost: "127.0.0.1", port: 19099)
        Functions.functions(region: "europe-west3").useEmulator(withHost: "127.0.0.1", port: 15001)
        Storage.storage().useEmulator(withHost: "127.0.0.1", port: 29199)
        let run = try XCTUnwrap(ProcessInfo.processInfo.environment["UACCursorFixtureRun"], "Seed the owned fixture first")
        guard run.range(of: "^cursor-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", options: .regularExpression) != nil else {
            XCTFail("Invalid cursor fixture namespace")
            return
        }
        guard Date().timeIntervalSince1970 + 86_400 < 2_000_000_000 else {
            XCTFail("Refresh the fixture's future seconds in both seed and test")
            return
        }
        try auth.signOut()
        defer { try? auth.signOut() }
        let result = try await auth.signIn(withEmail: "\(run)@uac.test", password: "Emulator-Only-2026!")
        guard result.user.uid == run, result.user.isEmailVerified else {
            XCTFail("Unexpected fixture identity")
            return
        }
        let owner = try await database.collection("users").document(run).getDocument(source: .server)
        guard owner.get("cursorFixtureRun") as? String == run, owner.get("globalRole") as? String == "owner" else {
            XCTFail("Fixture owner marker/role mismatch")
            return
        }

        let rows: [(String, Int32)] = [Int32(111_111_000), 123_456_000].enumerated().flatMap { group, nanos in
            [("\(run)-\(group)-before", nanos - 1_000), ("\(run)-\(group)-a", nanos),
             ("\(run)-\(group)-b", nanos), ("\(run)-\(group)-c", nanos), ("\(run)-\(group)-after", nanos + 1_000)]
        }
        // Separate caches also prevent another SDK journey's user state from
        // changing interaction decoration of these actual repository responses.
        let news = FirestoreNewsRepository(sessionDataCache: SessionDataCache())
        let events = FirestoreEventRepository(sessionDataCache: SessionDataCache())
        let organizations = FirestoreOrganizationRepository(sessionDataCache: SessionDataCache())
        let drafts = FirestoreOwnerContentDraftRepository()
        for limit in [1, 2] {
            try await checkPages(rows: rows.reversed().map { $0 }, limit: limit, cursor: { ($0.documentID, $0.exactTimestamp) }) {
                (after: NewsPageCursor?) in
                let page = try await news.fetchNewsPage(limit: limit, after: after, federalState: .vorarlberg)
                return (page.items.map(\.id), page.nextCursor, page.hasMore)
            }
            try await checkPages(rows: rows, limit: limit, cursor: { ($0.documentID, $0.exactTimestamp) }) {
                (after: EventPageCursor?) in
                let page = try await events.fetchEventsPage(limit: limit, after: after, federalState: .vorarlberg)
                return (page.items.map(\.id), page.nextCursor, page.hasMore)
            }
            try await checkPages(rows: rows.reversed().map { $0 }, limit: limit, cursor: { ($0.documentID, $0.exactTimestamp) }) {
                (after: OrganizationPageCursor?) in
                let page = try await organizations.fetchOrganizationsPage(limit: limit, after: after, federalState: .vorarlberg)
                return (page.items.map(\.id), page.nextCursor, page.hasMore)
            }
            try await checkPages(rows: rows.reversed().map { $0 }, limit: limit, cursor: { ($0.documentID, $0.exactTimestamp) }) {
                (after: OrganizationSubscriberCursor?) in
                let page = try await organizations.fetchOrganizationSubscriberPage(organizationID: "\(run)-0-a", limit: limit, after: after)
                return (page.items.map(\.documentID), page.nextCursor, page.hasMore)
            }
            // Switching section starts with nil again and exercises both sort
            // fields/directions through the real draft repository.
            for section in [OwnerContentPlanningSection.scheduled, .drafts] {
                let suffix = section == .scheduled ? "scheduled" : "recent"
                let ordered = section == .scheduled ? rows : rows.reversed().map { $0 }
                try await checkPages(rows: ordered.map { ("\($0.0)-\(suffix)", $0.1) }, limit: limit, cursor: { ($0.documentID, $0.exactTimestamp) }) {
                    (after: OwnerContentDraftPageCursor?) in
                    let page = try await drafts.fetchDraftPage(userID: run, section: section, limit: limit, after: after)
                    return (page.items.map(\.id), page.nextCursor, page.hasMore)
                }
            }
        }
        #else
        throw XCTSkip("The fixed demo configuration exists only in Debug Simulator builds.")
        #endif
    }

    private func checkPages<Cursor>(
        rows: [(String, Int32)],
        limit: Int,
        cursor: (Cursor) -> (String, PageCursorTimestamp?),
        fetch: (Cursor?) async throws -> ([String], Cursor?, Bool)
    ) async throws {
        var after: Cursor?
        var allIDs: [String] = []
        for offset in stride(from: 0, to: rows.count, by: limit) {
            let (ids, next, hasMore) = try await fetch(after)
            let expected = Array(rows.dropFirst(offset).prefix(limit))
            XCTAssertEqual(ids, expected.map { $0.0 }, "Actual repository page at offset \(offset), limit \(limit)")
            allIDs.append(contentsOf: ids)
            XCTAssertEqual(hasMore, offset + limit < rows.count)
            if hasMore || next != nil {
                let value = cursor(try XCTUnwrap(next, "Missing snapshot cursor before end of feed"))
                let last = try XCTUnwrap(expected.last)
                XCTAssertEqual(value.0, last.0, "Cursor must use returned last snapshot, not lookahead")
                let timestamp = try XCTUnwrap(value.1, "Firestore cursor lost original timestamp")
                XCTAssertEqual(timestamp.seconds, 2_000_000_000)
                XCTAssertEqual(timestamp.nanoseconds, last.1)
            }
            after = next
        }
        XCTAssertEqual(allIDs, rows.map { $0.0 })
        XCTAssertEqual(Set(allIDs).count, rows.count)
    }
}
