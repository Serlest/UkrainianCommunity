import XCTest
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseFunctions
import CryptoKit
import FirebaseStorage
import UIKit
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

    func testOutboxEnqueueForActualNextProcess() async throws {
        guard ProcessInfo.processInfo.environment["UACAuditOutboxPhase"] == "enqueue" else {
            throw XCTSkip("Dedicated two-process audit phase")
        }
        try await signIn("member")
        let item = ActivityLogItem(id: "closure-process-outbox", actionType: .savedNews,
            targetId: "closure-news", targetType: .news, title: "Closure News",
            subtitle: nil, imageURL: nil, createdAt: .now)
        await PendingActivityLogStore.shared.enqueue(item, userID: "closure-member")
        UserDefaults.standard.set(ProcessInfo.processInfo.processIdentifier, forKey: "audit.closure.outbox.writerPID")
        let queued = await PendingActivityLogStore.shared.items(userID: "closure-member")
        XCTAssertTrue(queued.contains { $0.id == item.id })
        try Auth.auth().signOut()
    }

    func testOutboxDeliversAfterActualProcessRestartAndAccountSwitch() async throws {
        guard ProcessInfo.processInfo.environment["UACAuditOutboxPhase"] == "deliver" else {
            throw XCTSkip("Dedicated two-process audit phase")
        }
        let previousPID = UserDefaults.standard.integer(forKey: "audit.closure.outbox.writerPID")
        XCTAssertGreaterThan(previousPID, 0)
        XCTAssertNotEqual(previousPID, Int(ProcessInfo.processInfo.processIdentifier))
        let queued = await PendingActivityLogStore.shared.items(userID: "closure-member")
        XCTAssertTrue(queued.contains { $0.id == "closure-process-outbox" })
        try await signIn("other")
        let wrongAccount = await ActivityLogRecorder.reconcilePending(userID: "closure-member")
        XCTAssertEqual(wrongAccount, .permissionDenied)
        try await signIn("member")
        let delivery = await ActivityLogRecorder.reconcilePending(userID: "closure-member")
        XCTAssertNil(delivery)
        let stored = try await Firestore.firestore().document("users/closure-member/activityLog/closure-process-outbox").getDocument(source: .server)
        XCTAssertEqual(stored.get("targetId") as? String, "closure-news")
        let remaining = await PendingActivityLogStore.shared.items(userID: "closure-member")
        XCTAssertFalse(remaining.contains { $0.id == "closure-process-outbox" })
        try await FirestoreActivityLogRepository().deleteActivity(id: "closure-process-outbox", userID: "closure-member")
        UserDefaults.standard.removeObject(forKey: "audit.closure.outbox.writerPID")
        try Auth.auth().signOut()
    }

    func testProfileAvatarUploadAssociationReopenAndCrossAccountDenial() async throws {
        try await signIn("member")
        defer { try? Auth.auth().signOut() }
        let original = try await UserProfileService.shared.fetchExistingUserProfile(uid: "closure-member")
        let image = UIGraphicsImageRenderer(size: .init(width: 640, height: 640)).image { context in
            UIColor.systemBlue.setFill(); context.fill(.init(x: 0, y: 0, width: 640, height: 640))
            UIColor.systemYellow.setFill(); context.fill(.init(x: 0, y: 320, width: 640, height: 320))
        }
        let bytes = try XCTUnwrap(image.jpegData(compressionQuality: 0.8))
        let url = try await ImageUploadService.shared.uploadProfileAvatarImage(data: bytes, userID: "closure-member")
        XCTAssertEqual(url.host, "firebasestorage.googleapis.com")
        XCTAssertTrue(url.absoluteString.contains("ukrainiancommunity-dbd5f.firebasestorage.app"))
        XCTAssertTrue(url.absoluteString.contains("profileImages%2Fclosure-member%2Favatar.jpg"))
        func draft(avatar: URL?) -> EditableUserProfileDraft {
            .init(fullName: original.fullName, displayName: original.displayName,
                  telegramUsername: original.telegramUsername, city: original.city, bio: original.bio,
                  selectedFederalState: original.selectedFederalState ?? .tirol, avatarURL: avatar)
        }
        _ = try await FirestoreUserRepository().updateProfile(draft(avatar: url))
        let stored = try await Firestore.firestore().document("users/closure-member").getDocument(source: .server)
        XCTAssertEqual(stored.get("avatarURL") as? String, url.absoluteString)
        let reference = Storage.storage().reference().child("profileImages/closure-member/avatar.jpg")
        let metadata = try await reference.getMetadata()
        XCTAssertEqual(metadata.contentType, "image/jpeg")
        let downloaded = try await reference.data(maxSize: 3_000_000)
        XCTAssertNotNil(UIImage(data: downloaded))
        try await signIn("other")
        do {
            _ = try await ImageUploadService.shared.uploadProfileAvatarImage(data: bytes, userID: "closure-member")
            XCTFail("Another member must not replace a profile avatar")
        } catch { XCTAssertEqual((error as NSError).code, StorageErrorCode.unauthorized.rawValue) }
        try await signIn("member")
        let reopened = try await UserProfileService.shared.fetchExistingUserProfile(uid: "closure-member")
        XCTAssertEqual(reopened.avatarURL, url)
        _ = try await FirestoreUserRepository().updateProfile(draft(avatar: original.avatarURL))
        try await reference.delete()
    }

    func testBilingualNewsEditorPersistsFullPayloadThroughActualRepository() async throws {
        try await newsEditorRoundTrip(scheduled: true)
    }

    func testPublishedNationalBilingualNewsPersistsThroughActualRepository() async throws {
        try await newsEditorRoundTrip(scheduled: false)
    }

    private func newsEditorRoundTrip(scheduled isScheduled: Bool) async throws {
        try await signIn("owner")
        defer { try? Auth.auth().signOut() }
        let user = try await UserProfileService.shared.fetchExistingUserProfile(uid: "closure-owner")
        let authState = AuthState(); authState.setAuthenticatedSession(user: user)
        let repository = FirestoreNewsRepository(sessionDataCache: SessionDataCache())
        let now = Date(), scheduled = now.addingTimeInterval(3600)
        let original = NewsPost(id: "closure-news-edit-" + UUID().uuidString, schemaVersion: 2,
            localizations: ["de": NewsLocalizedContent(title: "Deutscher Titel", subtitle: "Zusammenfassung", body: "Deutsche Beschreibung")],
            title: "Заголовок", subtitle: "Короткий опис", regionScope: isScheduled ? .federalState : .austria, federalState: isScheduled ? .tirol : nil, city: "Innsbruck",
            category: .news, tags: ["audit"],
            source: ContentSourceMetadata(sourceType: .organization, organizationId: "closure-org", organizationName: "Closure Organization"),
            sourceName: "Organizer", sourceURL: "https://example.org/source", imageURL: nil,
            mediaMetadata: NewsMediaMetadata(caption: "Caption", alternativeText: "Alternative", credit: "Credit"),
            externalAction: ExternalContentAction(title: "Read more", url: "https://example.org/details"),
            body: "Повний опис новини для перевірки збереження.", authorId: "closure-owner", authorName: "Closure Owner",
            publishedAt: now, scheduledAt: isScheduled ? scheduled : nil, createdAt: now, updatedAt: now,
            comments: [], moderationStatus: isScheduled ? .draft : .approved, likeCount: 0, likeState: .notLiked)
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
        XCTAssertEqual(stored.federalState, isScheduled ? .tirol : nil)
        XCTAssertEqual(stored.regionScope, isScheduled ? .federalState : .austria)
        XCTAssertEqual(stored.source.organizationId, "closure-org")
        XCTAssertEqual(stored.mediaMetadata, original.mediaMetadata)
        XCTAssertEqual(stored.externalAction, original.externalAction)
        XCTAssertEqual(stored.sourceName, original.sourceName)
        XCTAssertEqual(stored.sourceURL, original.sourceURL)
        XCTAssertEqual(stored.authorId, original.authorId)
        XCTAssertEqual(stored.likeCount, 0)
        XCTAssertEqual(stored.commentCount, 0)
        XCTAssertEqual(stored.viewCount, 0)
        if isScheduled {
            XCTAssertEqual(stored.scheduledAt?.timeIntervalSince1970 ?? 0, scheduled.timeIntervalSince1970, accuracy: 0.001)
        } else { XCTAssertNil(stored.scheduledAt) }
        let raw = try await Firestore.firestore().document("news/\(original.id)").getDocument(source: .server)
        XCTAssertEqual(raw.get("title") as? String, editor.title)
        XCTAssertEqual(raw.get("moderationStatus") as? String, isScheduled ? "draft" : "approved")
        if !isScheduled {
            let publicRead = try await repository.fetchNews(id: original.id)
            XCTAssertEqual(publicRead.localizations["de"]?.title, editor.germanTitle)
        }
        try await repository.deleteNews(id: original.id)
    }

    func testBilingualEventEditorRetainsScheduledOccurrencesAndRegistrationSettings() async throws {
        try await eventEditorRoundTrip(scheduled: true)
    }

    func testPublishedBilingualEventCanBeRegisteredByAnotherUserAndCanceled() async throws {
        try await eventEditorRoundTrip(scheduled: false)
    }

    private func eventEditorRoundTrip(scheduled isScheduled: Bool) async throws {
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
            createdAt: now, updatedAt: now, scheduledAt: isScheduled ? scheduled : nil, requiresRegistration: true,
            pricing: EventPricing(kind: .free), capacity: 20, registeredCount: 0, comments: [],
            moderationStatus: isScheduled ? .draft : .approved, registrationState: .notRegistered, likeCount: 0, likeState: .notLiked,
            category: .meetups, additionalCategories: [.training, .culture], audience: .everyone, minimumAge: 0, maximumAge: 120)
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
        XCTAssertEqual(stored.additionalCategories, original.additionalCategories)
        XCTAssertEqual(stored.minimumAge, 0)
        XCTAssertEqual(stored.maximumAge, 120)
        XCTAssertEqual(stored.capacity, 20)
        XCTAssertTrue(stored.requiresRegistration)
        XCTAssertEqual(stored.registeredCount, 0)
        if isScheduled {
            XCTAssertEqual(stored.scheduledAt?.timeIntervalSince1970 ?? 0, scheduled.timeIntervalSince1970, accuracy: 0.001)
        } else { XCTAssertNil(stored.scheduledAt) }
        let raw = try await Firestore.firestore().document("events/\(original.id)").getDocument(source: .server)
        XCTAssertEqual(raw.get("title") as? String, editor.title)
        XCTAssertEqual(raw.get("moderationStatus") as? String, isScheduled ? "draft" : "approved")
        if !isScheduled {
            try await signIn("member")
            let publicRead = try await FirestoreEventRepository(sessionDataCache: SessionDataCache()).fetchEvent(id: original.id)
            XCTAssertEqual(publicRead.localizations["de"]?.title, editor.germanTitle)
            let registered = try await repository.registerForEvent(id: original.id, actionCapture: nil)
            XCTAssertEqual(registered.registrationState, .registered)
            let withRegistration = try await Firestore.firestore().document("events/\(original.id)").getDocument(source: .server)
            XCTAssertEqual(withRegistration.get("registeredCount") as? Int, 1)
            let canceled = try await repository.cancelEventRegistration(id: original.id, actionCapture: nil)
            XCTAssertEqual(canceled.registrationState, .notRegistered)
            let withoutRegistration = try await Firestore.firestore().document("events/\(original.id)").getDocument(source: .server)
            XCTAssertEqual(withoutRegistration.get("registeredCount") as? Int, 0)
            try await signIn("owner")
        }
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

    func testOrganizationTeamActualServiceRoleChangesTransferAndTargetNotices() async throws {
        try await signIn("owner")
        defer { try? Auth.auth().signOut() }
        let actor = try await UserProfileService.shared.fetchExistingUserProfile(uid: "closure-owner")
        let db = Firestore.firestore()
        let repository = FirestoreOrganizationRepository(sessionDataCache: SessionDataCache())
        let service = FirestoreOrganizationRoleManagementService()
        let base = try await repository.fetchOrganization(id: "closure-org")
        XCTAssertEqual(base.ownerId, actor.id)
        let targetInbox = db.collection("users/closure-other/notificationInbox")
        try await signIn("other")
        let before = Set(try await targetInbox.getDocuments(source: .server).documents.map(\.documentID))
        try await signIn("owner")
        try await service.updateRole(role: .communityAdmin, organization: base, targetUserID: "closure-other", actor: actor, isRemoval: false, reason: "Local audit role assignment")
        let admin = try await repository.fetchOrganization(id: "closure-org")
        XCTAssertTrue(admin.adminIds.contains("closure-other")); XCTAssertFalse(admin.moderatorIds.contains("closure-other"))
        let stored = try await db.document("organizations/closure-org").getDocument(source: .server)
        XCTAssertTrue((stored.get("adminIds") as? [String] ?? []).contains("closure-other"))
        do {
            try await service.updateRole(role: .communityModerator, organization: base, targetUserID: "closure-other", actor: actor, isRemoval: false, reason: "Stale local audit")
            XCTFail("Stale role review must not overwrite the assignment")
        } catch { XCTAssertEqual((error as NSError).code, FunctionsErrorCode.aborted.rawValue) }
        try await signIn("other")
        let target = try await UserProfileService.shared.fetchExistingUserProfile(uid: "closure-other")
        let targetOrg = try await FirestoreOrganizationRepository(sessionDataCache: SessionDataCache()).fetchOrganization(id: "closure-org")
        XCTAssertTrue(PermissionService.canAccessManagedOrganization(targetOrg, user: target))
        try await signIn("owner")
        try await service.updateRole(role: .communityModerator, organization: admin, targetUserID: "closure-other", actor: actor, isRemoval: false, reason: "Local audit role change")
        let moderator = try await repository.fetchOrganization(id: "closure-org")
        XCTAssertFalse(moderator.adminIds.contains("closure-other")); XCTAssertTrue(moderator.moderatorIds.contains("closure-other"))
        try await service.updateRole(role: .member, organization: moderator, targetUserID: "closure-other", actor: actor, isRemoval: true, reason: "Local audit role removal")
        let removed = try await repository.fetchOrganization(id: "closure-org")
        XCTAssertFalse(removed.adminIds.contains("closure-other")); XCTAssertFalse(removed.moderatorIds.contains("closure-other"))
        XCTAssertFalse(PermissionService.canAccessManagedOrganization(removed, user: target))
        try await service.transferOwner(organization: removed, newOwnerID: "closure-other", actor: actor, reason: "Local audit ownership transfer")
        let transferred = try await repository.fetchOrganization(id: "closure-org")
        XCTAssertEqual(transferred.ownerId, "closure-other")
        XCTAssertTrue(PermissionService.canAccessManagedOrganization(transferred, user: target))
        let ownerDoc = try await db.document("organizations/closure-org").getDocument(source: .server)
        XCTAssertEqual(ownerDoc.get("ownerId") as? String, "closure-other")
        try await signIn("other")
        let notices = try await targetInbox.getDocuments(source: .server).documents.filter { !before.contains($0.documentID) }
        XCTAssertEqual(notices.count, 4)
        for notice in notices {
            XCTAssertEqual(notice.get("recipientUserId") as? String, "closure-other")
            XCTAssertEqual(notice.get("actorUserId") as? String, "closure-owner")
            XCTAssertEqual(notice.get("sourceId") as? String, "closure-org")
            XCTAssertEqual(notice.get("actionTargetId") as? String, "closure-org")
        }
        XCTAssertEqual(notices.filter { $0.get("type") as? String == "organizationRoleAssigned" }.count, 3)
        XCTAssertEqual(notices.filter { $0.get("type") as? String == "organizationRoleRemoved" }.count, 1)
        // Restore the isolated reusable organization after observing the new owner.
        try await signIn("owner")
        try await service.transferOwner(organization: transferred, newOwnerID: "closure-owner", actor: actor, reason: "Restore local audit fixture")
        let restored = try await repository.fetchOrganization(id: "closure-org")
        XCTAssertEqual(restored.ownerId, "closure-owner")
    }

    func testDirectorySDKPublicationRevisionConflictRevocationAndTargetNotifications() async throws {
        try await signIn("owner")
        defer { try? Auth.auth().signOut() }
        let access = DirectoryEditorAccessAPI.live
        let inspect = try XCTUnwrap(access.inspect), mutate = try XCTUnwrap(access.mutate)
        let inspected = try await inspect("closure-owner", ["closure-other"])
        let previous = try XCTUnwrap(inspected.first)
        let grantOperation = UUID().uuidString
        let granted = try await mutate("closure-owner", previous, true, grantOperation)
        XCTAssertTrue(granted.enabled)
        try await signIn("other")
        let editorUser = try await UserProfileService.shared.fetchExistingUserProfile(uid: "closure-other")
        let first = DirectoryContentStore(cacheURL: nil)
        first.configure(user: editorUser)
        for _ in 0..<50 { if first.canEdit { break }; try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertTrue(first.canEdit)
        let base = try XCTUnwrap(DirectoryCatalog.categories.first { $0.id == "first-steps" })
        var category = DirectoryManagedCategory.bundled(base)
        category.id = "custom-" + UUID().uuidString.lowercased()
        category.title = DirectoryText(ukrainian: "Локальна перевірка", german: "Lokaler Test")
        category.symbol = "book"
        try await first.save(category, expectedRevision: 0, actorID: editorUser.id)
        let db = Firestore.firestore(), reference = db.collection("directoryCategories").document(category.id)
        let stored = try await reference.getDocument(source: .server)
        XCTAssertEqual(stored.get("revision") as? Int, 1)
        let payload = try XCTUnwrap(stored.get("payload") as? String)
        XCTAssertEqual(try JSONDecoder().decode(DirectoryManagedCategory.self, from: Data(payload.utf8)), category)
        let reopened = DirectoryContentStore(cacheURL: nil)
        reopened.configure(user: editorUser); reopened.startObserving()
        for _ in 0..<50 { if reopened.category(category.id) != nil && reopened.canEdit { break }; try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(reopened.category(category.id), category)
        category.title = DirectoryText(ukrainian: "Оновлено", german: "Aktualisiert")
        try await first.save(category, expectedRevision: 1, actorID: editorUser.id)
        do {
            try await reopened.save(category, expectedRevision: 1, actorID: editorUser.id)
            XCTFail("A stale open editor must not overwrite revision 2")
        } catch { XCTAssertEqual((error as NSError).code, FunctionsErrorCode.aborted.rawValue) }
        let revision2 = try await reference.getDocument(source: .server)
        XCTAssertEqual(revision2.get("revision") as? Int, 2)
        try await signIn("owner")
        let revokeOperation = UUID().uuidString
        let revoked = try await mutate("closure-owner", granted, false, revokeOperation)
        XCTAssertFalse(revoked.enabled)
        try await signIn("other")
        for _ in 0..<50 { if !reopened.canEdit { break }; try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertFalse(reopened.canEdit)
        do {
            try await reopened.save(category, expectedRevision: 2, actorID: editorUser.id)
            XCTFail("Revoked open editor must not save")
        } catch { XCTAssertEqual(error as? AppError, .permissionDenied) }
        for operation in [grantOperation, revokeOperation] {
            let key = SHA256.hash(data: Data(("closure-owner" + "\0" + operation).utf8)).map { String(format: "%02x", $0) }.joined()
            let notice = try await db.document("users/closure-other/notificationInbox/directory-access-\(key)").getDocument(source: .server)
            XCTAssertEqual(notice.get("recipientUserId") as? String, "closure-other")
            XCTAssertEqual(notice.get("actorUserId") as? String, "closure-owner")
            XCTAssertEqual(notice.get("sourceId") as? String, "closure-other")
        }
        // Delete with the owner after revocation and independently read tombstone/history.
        try await signIn("owner")
        let ownerUser = try await UserProfileService.shared.fetchExistingUserProfile(uid: "closure-owner")
        let ownerStore = DirectoryContentStore(cacheURL: nil); ownerStore.configure(user: ownerUser)
        try await ownerStore.deleteCustomCategory(category.id, expectedRevision: 2, actorID: ownerUser.id)
        let deleted = try await reference.getDocument(source: .server)
        XCTAssertEqual(deleted.get("isDeleted") as? Bool, true)
        XCTAssertEqual(deleted.get("revision") as? Int, 3)
        let versions = try await reference.collection("versions").getDocuments(source: .server)
        XCTAssertEqual(Set(versions.documents.map(\.documentID)), ["1", "2", "3"])
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
