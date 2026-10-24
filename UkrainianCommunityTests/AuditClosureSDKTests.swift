import XCTest
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
@testable import UkrainianCommunity

/// Connected repository/Functions checks, never run against a production project.
@MainActor
final class AuditClosureSDKTests: XCTestCase {
    private func signIn(_ role: String) async throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" else {
            throw XCTSkip("Seed scripts/seed-audit-closure-emulators.cjs in the isolated demo emulators")
        }
        guard FirebaseApp.app()?.options.projectID == "demo-uac-release-audit",
              Firestore.firestore().settings.host == "127.0.0.1:28080",
              !Firestore.firestore().settings.isSSLEnabled else {
            throw NSError(domain: "RefusingNonLocalAudit", code: 1)
        }
        try? Auth.auth().signOut()
        let result = try await Auth.auth().signIn(withEmail: "closure-\(role)@uac.test", password: "Emulator-Only-2026!")
        XCTAssertEqual(result.user.uid, "closure-\(role)")
    }

    func testPendingActivitySurvivesStoreRecreationAndDeliversOnlyForItsAccount() async throws {
        try await signIn("member")
        defer { try? Auth.auth().signOut() }
        let item = ActivityLogItem(id: "closure-outbox", actionType: .savedNews, targetId: "closure-news", targetType: .news,
                                   title: "Closure News", subtitle: nil, imageURL: nil, createdAt: .now)
        await PendingActivityLogStore.shared.enqueue(item, userID: "closure-member")
        let reconstructed = PendingActivityLogStore()
        let persisted = await reconstructed.items(userID: "closure-member")
        XCTAssertTrue(persisted.contains(where: { $0.id == item.id }))
        try await signIn("other")
        let rejected = await ActivityLogRecorder.reconcilePending(userID: "closure-member")
        XCTAssertEqual(rejected, .permissionDenied)
        let pending = await PendingActivityLogStore.shared.items(userID: "closure-member")
        XCTAssertTrue(pending.contains(where: { $0.id == item.id }))
        try await signIn("member")
        let error = await ActivityLogRecorder.reconcilePending(userID: "closure-member")
        XCTAssertNil(error)
        let delivered = try await Firestore.firestore().document("users/closure-member/activityLog/closure-outbox").getDocument(source: .server)
        XCTAssertEqual(delivered.get("targetId") as? String, item.targetId)
        let remaining = await PendingActivityLogStore.shared.items(userID: "closure-member")
        XCTAssertFalse(remaining.contains(where: { $0.id == item.id }))
        try await FirestoreActivityLogRepository().deleteActivity(id: item.id, userID: "closure-member")
    }

    func testBilingualNewsEditorPersistsFullPayloadThroughActualRepository() async throws {
        try await signIn("owner")
        defer { try? Auth.auth().signOut() }
        let user = try await UserProfileService.shared.fetchExistingUserProfile(uid: "closure-owner")
        let authState = AuthState(); authState.setAuthenticatedSession(user: user)
        let repository = FirestoreNewsRepository(sessionDataCache: SessionDataCache())
        let now = Date(), scheduled = now.addingTimeInterval(3600)
        let original = NewsPost(id: "closure-news-edit-" + UUID().uuidString, schemaVersion: 2,
            localizations: ["de": NewsLocalizedContent(title: "Deutscher Titel", subtitle: "Zusammenfassung", body: "Deutsche Beschreibung")],
            title: "Заголовок", subtitle: "Короткий опис", regionScope: .federalState, federalState: .tirol, city: "Innsbruck",
            category: .news, tags: ["audit"],
            source: ContentSourceMetadata(sourceType: .organization, organizationId: "closure-org", organizationName: "Closure Organization"),
            sourceName: "Organizer", sourceURL: "https://example.org/source", imageURL: nil,
            mediaMetadata: NewsMediaMetadata(caption: "Caption", alternativeText: "Alternative", credit: "Credit"),
            externalAction: ExternalContentAction(title: "Read more", url: "https://example.org/details"),
            body: "Повний опис новини для перевірки збереження.", authorId: "closure-owner", authorName: "Closure Owner",
            publishedAt: now, scheduledAt: scheduled, createdAt: now, updatedAt: now,
            comments: [], moderationStatus: .draft, likeCount: 0, likeState: .notLiked)
        try await repository.createNews(original)
        let editor = NewsEditorViewModel(repository: repository, authState: authState, mode: .edit(existing: original))
        editor.title = "Оновлений заголовок"
        editor.germanTitle = "Aktualisierter Titel"
        let saved = await editor.publish()
        XCTAssertTrue(saved, editor.errorMessage ?? "Editor must save")
        guard saved else { return } // Preserve the failing isolated payload for diagnosis.
        let stored = try await repository.fetchManagedNews(id: original.id, organizationID: "closure-org")
        XCTAssertEqual(stored.title, editor.title)
        XCTAssertEqual(stored.localizations["de"]?.title, editor.germanTitle)
        XCTAssertEqual(stored.localizations["de"]?.body, original.localizations["de"]?.body)
        XCTAssertEqual(stored.federalState, .tirol)
        XCTAssertEqual(stored.source.organizationId, "closure-org")
        XCTAssertEqual(stored.mediaMetadata, original.mediaMetadata)
        XCTAssertEqual(stored.externalAction, original.externalAction)
        XCTAssertEqual(stored.scheduledAt?.timeIntervalSince1970 ?? 0, scheduled.timeIntervalSince1970, accuracy: 0.001)
        let raw = try await Firestore.firestore().document("news/\(original.id)").getDocument(source: .server)
        XCTAssertEqual(raw.get("title") as? String, editor.title)
        XCTAssertEqual(raw.get("moderationStatus") as? String, "draft")
        try await repository.deleteNews(id: original.id)
    }

    func testBilingualEventEditorRetainsScheduledOccurrencesAndRegistrationSettings() async throws {
        try await signIn("owner")
        defer { try? Auth.auth().signOut() }
        let repository = FirestoreEventRepository(sessionDataCache: SessionDataCache())
        let now = Date(), start = now.addingTimeInterval(7 * 86400), scheduled = now.addingTimeInterval(3600)
        let occurrences = [EventOccurrence(id: "first", startDate: start, endDate: start.addingTimeInterval(3600)),
                           EventOccurrence(id: "second", startDate: start.addingTimeInterval(86400), endDate: start.addingTimeInterval(90000))]
        let original = Event(id: "closure-event-edit-" + UUID().uuidString, schemaVersion: 2,
            localizations: ["de": EventLocalizedContent(title: "Deutscher Titel", summary: "Zusammenfassung", details: "Deutsche Beschreibung")],
            title: "Зустріч громади", summary: "Короткий опис", details: "Повний опис зустрічі для перевірки.",
            regionScope: .federalState, federalState: .tirol,
            source: ContentSourceMetadata(sourceType: .organization, organizationId: "closure-org", organizationName: "Closure Organization"),
            authorId: "closure-owner", authorName: "Closure Owner", city: "Innsbruck", venue: "Test hall", address: "Test 1",
            latitude: 47.26, longitude: 11.39, contactEmail: "audit@example.org",
            mediaMetadata: EventMediaMetadata(caption: "Caption", alternativeText: "Alternative", credit: "Credit"),
            startDate: start, endDate: start.addingTimeInterval(3600), occurrences: occurrences,
            createdAt: now, updatedAt: now, scheduledAt: scheduled, requiresRegistration: true,
            pricing: EventPricing(kind: .free), capacity: 20, registeredCount: 0, comments: [],
            moderationStatus: .draft, registrationState: .notRegistered, likeCount: 0, likeState: .notLiked)
        try await repository.createEvent(original)
        let initial = try await repository.fetchManagedEvent(id: original.id, organizationID: "closure-org")
        let editor = EventEditorViewModel(repository: repository, mode: .edit(existing: initial))
        editor.title = "Оновлена зустріч"
        editor.germanTitle = "Aktualisierte Veranstaltung"
        let saved = await editor.publish()
        XCTAssertTrue(saved, editor.errorMessage ?? "Editor must save")
        guard saved else { return } // Preserve the failing isolated payload for diagnosis.
        let stored = try await repository.fetchManagedEvent(id: original.id, organizationID: "closure-org")
        XCTAssertEqual(stored.title, editor.title)
        XCTAssertEqual(stored.localizations["de"]?.title, editor.germanTitle)
        XCTAssertEqual(stored.localizations["de"]?.details, original.localizations["de"]?.details)
        XCTAssertEqual(stored.occurrences.map(\.id), initial.occurrences.map(\.id))
        for (actual, expected) in zip(stored.occurrences, initial.occurrences) {
            XCTAssertEqual(actual.startDate.timeIntervalSince1970, expected.startDate.timeIntervalSince1970, accuracy: 0.001)
            XCTAssertEqual(actual.endDate.timeIntervalSince1970, expected.endDate.timeIntervalSince1970, accuracy: 0.001)
            XCTAssertEqual(actual.isAllDay, expected.isAllDay)
            XCTAssertEqual(actual.status, expected.status)
        }
        XCTAssertEqual(stored.contactEmail, original.contactEmail)
        XCTAssertEqual(stored.mediaMetadata, original.mediaMetadata)
        XCTAssertEqual(stored.federalState, .tirol)
        XCTAssertEqual(stored.source.organizationId, "closure-org")
        XCTAssertEqual(stored.capacity, 20)
        XCTAssertTrue(stored.requiresRegistration)
        XCTAssertEqual(stored.registeredCount, 0)
        XCTAssertEqual(stored.scheduledAt?.timeIntervalSince1970 ?? 0, scheduled.timeIntervalSince1970, accuracy: 0.001)
        let raw = try await Firestore.firestore().document("events/\(original.id)").getDocument(source: .server)
        XCTAssertEqual(raw.get("title") as? String, editor.title)
        XCTAssertEqual(raw.get("moderationStatus") as? String, "draft")
        try await repository.deleteEvent(id: original.id)
    }

    func testThousandAttendeesLoadWithCompleteNamesAndStableOrder() async throws {
        guard ProcessInfo.processInfo.environment["UACAuditAttendeeLoad"] == "1" else {
            throw XCTSkip("Seed --load and opt in to the 1000-attendee journey")
        }
        try await signIn("owner")
        defer { try? Auth.auth().signOut() }
        let repository = FirestoreEventRepository(sessionDataCache: SessionDataCache())
        let start = Date()
        let attendees = try await repository.fetchEventRegistrations(eventID: "closure-large-event")
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(attendees.count, 1000)
        XCTAssertEqual(attendees.first?.userID, "closure-attendee-0000")
        XCTAssertEqual(attendees.last?.userID, "closure-attendee-0999")
        XCTAssertEqual(Set(attendees.map(\.userID)).count, 1000)
        XCTAssertTrue(attendees.allSatisfy { $0.displayName?.hasPrefix("Audit Attendee ") == true })
        XCTAssertLessThan(elapsed, 15, "Must complete within the current UI request deadline in the local load environment")
        let measurement = XCTAttachment(string: "Local emulator cold session: 1000 attendees, \(elapsed) seconds. This is not internet latency proof.")
        measurement.name = "attendee-load-timing"; measurement.lifetime = .keepAlways; add(measurement)
    }

    func testPersonalRepositoriesPersistAndIsolateAccounts() async throws {
        try await signIn("member")
        defer { try? Auth.auth().signOut() }
        let uid = "closure-member"
        let baselineHistory = try await FirestoreActivityLogRepository().fetchActivityLog(userID: uid, limit: 100)
        let db = Firestore.firestore()
        let news = FirestoreNewsRepository(sessionDataCache: SessionDataCache())
        let events = FirestoreEventRepository(sessionDataCache: SessionDataCache())
        let organizations = FirestoreOrganizationRepository(sessionDataCache: SessionDataCache())
        try await news.bookmarkNews(id: "closure-news", actionCapture: nil)
        try await events.bookmarkEvent(id: "closure-event", actionCapture: nil)
        try await organizations.bookmarkOrganization(id: "closure-org", actionCapture: nil)
        try await organizations.subscribeOrganization(id: "closure-org", actionCapture: nil)
        for (collection, id) in [("newsBookmarks", "closure-news"), ("eventBookmarks", "closure-event"), ("organizationBookmarks", "closure-org")] {
            let stored = try await db.document("users/\(uid)/\(collection)/\(id)").getDocument(source: .server)
            XCTAssertTrue(stored.exists, "Independent server read: \(collection)")
        }
        let follow = try await db.document("likes/organization_follow_closure-org_\(uid)").getDocument(source: .server)
        XCTAssertEqual(follow.get("userId") as? String, uid)
        let recent = RecentViewItem(itemId: "closure-news", itemType: .news, title: "Closure News", subtitle: nil, imageURL: nil, viewedAt: .now)
        try await FirestoreRecentViewsRepository().recordRecentView(recent, userID: uid)
        let activity = ActivityLogItem(id: "closure-save", actionType: .savedNews, targetId: "closure-news", targetType: .news, title: "Closure News", subtitle: nil, imageURL: nil, createdAt: .now)
        try await FirestoreActivityLogRepository().recordActivity(activity, userID: uid)
        let registered = try await events.registerForEvent(id: "closure-event", actionCapture: nil)
        XCTAssertEqual(registered.registrationState, .registered)
        XCTAssertEqual(registered.registeredCount, 1)
        let counter = try await db.document("events/closure-event").getDocument(source: .server)
        XCTAssertEqual(counter.get("registeredCount") as? Int, 1)
        // Recreate all repositories and reauthenticate: no session cache can fake persistence.
        try await signIn("member")
        let savedNews = try await FirestoreNewsRepository(sessionDataCache: SessionDataCache()).fetchBookmarkedNews()
        let savedEvents = try await FirestoreEventRepository(sessionDataCache: SessionDataCache()).fetchBookmarkedEvents()
        let savedOrganizations = try await FirestoreOrganizationRepository(sessionDataCache: SessionDataCache()).fetchBookmarkedOrganizations()
        let subscriptions = try await FirestoreOrganizationRepository(sessionDataCache: SessionDataCache()).fetchSubscribedOrganizations()
        let registrations = try await FirestoreEventRepository(sessionDataCache: SessionDataCache()).fetchRegisteredEvents()
        XCTAssertEqual(savedNews.map(\.id), ["closure-news"])
        XCTAssertEqual(savedEvents.map(\.id), ["closure-event"])
        XCTAssertEqual(savedOrganizations.map(\.id), ["closure-org"])
        XCTAssertEqual(subscriptions.map(\.id), ["closure-org"])
        XCTAssertEqual(registrations.map(\.id), ["closure-event"])
        let views = try await FirestoreRecentViewsRepository().fetchRecentViews(userID: uid, limit: 30)
        let history = try await FirestoreActivityLogRepository().fetchActivityLog(userID: uid, limit: 100)
        XCTAssertEqual(views.map(\.id), [recent.id])
        XCTAssertEqual(Set(history.map(\.id)), Set(baselineHistory.map(\.id)).union([activity.id]))
        try await signIn("other")
        let otherNews = try await FirestoreNewsRepository(sessionDataCache: SessionDataCache()).fetchBookmarkedNews()
        XCTAssertTrue(otherNews.isEmpty)
        let otherSubscriptions = try await FirestoreOrganizationRepository(sessionDataCache: SessionDataCache()).fetchSubscribedOrganizations()
        XCTAssertTrue(otherSubscriptions.isEmpty)
        do {
            _ = try await db.document("users/\(uid)/newsBookmarks/closure-news").getDocument(source: .server)
            XCTFail("Another member must not read private saved items")
        } catch { XCTAssertEqual((error as NSError).code, FirestoreErrorCode.permissionDenied.rawValue) }
        do {
            try await FirestoreRecentViewsRepository().recordRecentView(recent, userID: uid)
            XCTFail("Wrong-account recent-view write must be rejected")
        } catch { }
        try await signIn("member")
        try await news.unbookmarkNews(id: "closure-news")
        try await events.unbookmarkEvent(id: "closure-event")
        try await organizations.unbookmarkOrganization(id: "closure-org")
        try await organizations.unsubscribeOrganization(id: "closure-org", actionCapture: nil)
        let canceled = try await events.cancelEventRegistration(id: "closure-event", actionCapture: nil)
        XCTAssertEqual(canceled.registrationState, .notRegistered)
        XCTAssertEqual(canceled.registeredCount, 0)
        try await FirestoreRecentViewsRepository().deleteRecentView(id: recent.id, userID: uid, through: .now)
        try await FirestoreActivityLogRepository().deleteActivity(id: activity.id, userID: uid)
        for (collection, id) in [("newsBookmarks", "closure-news"), ("eventBookmarks", "closure-event"), ("organizationBookmarks", "closure-org")] {
            let stored = try await db.document("users/\(uid)/\(collection)/\(id)").getDocument(source: .server)
            XCTAssertFalse(stored.exists, "Deletion server read: \(collection)")
        }
        let finalCounter = try await db.document("events/closure-event").getDocument(source: .server)
        XCTAssertEqual(finalCounter.get("registeredCount") as? Int, 0)
    }
}
