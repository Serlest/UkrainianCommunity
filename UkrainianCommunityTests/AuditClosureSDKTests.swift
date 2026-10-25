import XCTest
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseFunctions
import CryptoKit
import FirebaseStorage
import EventKit
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

    func testActualProviderLinkRetainsIdentityRejectsDuplicateAndOtherAccountThenRestoresFixture() async throws {
        try await signIn("member")
        defer { try? Auth.auth().signOut() }
        let backend = FirebaseAccountProviderLinkBackend()
        let original = try await backend.snapshot()
        XCTAssertEqual(original.userID, "closure-member")
        XCTAssertTrue(original.isEmailVerified)
        guard !original.providerIDs.contains("google.com") else {
            throw NSError(domain: "AuditFixtureAlreadyLinked", code: 1)
        }
        let user = try await UserProfileService.shared.fetchExistingUserProfile(uid: "closure-member")
        let state = AuthState(); state.setAuthenticatedSession(user: user)
        let service = AccountProviderLinkService(authState: state, backend: backend)
        // Strict JSON ID tokens are an explicitly supported Auth Emulator contract.
        // These synthetic credentials are never sent to Google or production Firebase.
        let subject = "closure-provider-" + UUID().uuidString.lowercased()
        let payload = try JSONSerialization.data(withJSONObject: [
            "sub": subject, "email": subject + "@uac.test", "email_verified": true,
            "iss": "https://accounts.google.com", "aud": "demo-uac-release-audit"
        ])
        let credential = GoogleAuthProvider.credential(withIDToken: String(decoding: payload, as: UTF8.self), accessToken: "emulator-only")
        func restoreFixture() async throws {
            try await signIn("member")
            let current = try XCTUnwrap(Auth.auth().currentUser)
            if current.providerData.contains(where: { $0.providerID == "google.com" }) {
                _ = try await current.unlink(fromProvider: "google.com")
            }
            let restoredProviders = try await emulatorAuthProviders(userID: "closure-member")
            XCTAssertEqual(restoredProviders, original.providerIDs)
        }
        do {
            let linked = try await service.link(credential)
            XCTAssertEqual(linked, original.providerIDs.union(["google.com"]))
            let independentlyLinked = try await emulatorAuthProviders(userID: "closure-member")
            XCTAssertEqual(independentlyLinked, linked)
            try Auth.auth().signOut()
            let throughGoogle = try await Auth.auth().signIn(with: credential)
            XCTAssertEqual(throughGoogle.user.uid, "closure-member", "Linking must preserve the existing account")
            try await signIn("member")
            do {
                _ = try await service.link(credential)
                XCTFail("Already linked provider must be rejected")
            } catch let error as AccountProviderLinkError { XCTAssertEqual(error, .alreadyLinked) }
            try await signIn("other")
            let other = try await UserProfileService.shared.fetchExistingUserProfile(uid: "closure-other")
            let otherState = AuthState(); otherState.setAuthenticatedSession(user: other)
            let otherService = AccountProviderLinkService(authState: otherState, backend: backend)
            do {
                _ = try await otherService.link(credential)
                XCTFail("A provider already owned by another account must not be attached")
            } catch {
                XCTAssertEqual((error as NSError).code, AuthErrorCode.credentialAlreadyInUse.rawValue)
            }
            XCTAssertEqual(Auth.auth().currentUser?.uid, "closure-other")
            let otherProviders = try await emulatorAuthProviders(userID: "closure-other")
            XCTAssertFalse(otherProviders.contains("google.com"))
            try await restoreFixture()
        } catch {
            try? await restoreFixture()
            throw error
        }
    }

    func testExistingFixtureVerificationAndPasswordResetActionCodesWithoutRegistration() async throws {
        try await signIn("other")
        defer { try? Auth.auth().signOut() }
        let email = "closure-other@uac.test"
        let updatePath = "identitytoolkit.googleapis.com/v1/projects/demo-uac-release-audit/accounts:update"
        func restoreFixture() async throws {
            _ = try await emulatorAuthObject(path: updatePath, method: "POST", body: [
                "localId": "closure-other", "emailVerified": true, "password": "Emulator-Only-2026!"
            ])
            try await signIn("other")
        }
        func latestCode(_ type: String, mode: String) async throws -> String {
            let response = try await emulatorAuthObject(path: "emulator/v1/projects/demo-uac-release-audit/oobCodes")
            let codes = try XCTUnwrap(response["oobCodes"] as? [[String: Any]])
            let entry = try XCTUnwrap(codes.last { $0["email"] as? String == email && $0["requestType"] as? String == type })
            let url = try XCTUnwrap(URLComponents(string: try XCTUnwrap(entry["oobLink"] as? String)))
            XCTAssertEqual(url.host, "127.0.0.1")
            XCTAssertEqual(url.queryItems?.first { $0.name == "mode" }?.value, mode)
            let code = try XCTUnwrap(entry["oobCode"] as? String)
            XCTAssertEqual(url.queryItems?.first { $0.name == "oobCode" }?.value, code)
            return code
        }
        do {
            _ = try await emulatorAuthObject(path: updatePath, method: "POST", body: ["localId": "closure-other", "emailVerified": false])
            let session = try XCTUnwrap(Auth.auth().currentUser)
            try await session.reload(); XCTAssertFalse(session.isEmailVerified)
            let profile = try await UserProfileService.shared.fetchExistingUserProfile(uid: "closure-other")
            let state = AuthState(); state.setAuthenticatedSession(user: profile)
            let service = AuthService(authState: state, backend: FirebaseAuthBackend(), profileProvider: UserProfileService.shared)
            try await service.sendEmailVerification()
            let verification = try await latestCode("VERIFY_EMAIL", mode: "verifyEmail")
            let action = try await Auth.auth().checkActionCode(verification)
            // Auth Emulator returns VERIFY_EMAIL, while SDK operation mapping expects verifyEmail.
            // The app does not inspect that enum; verify recipient, one-use code and actual state transition.
            XCTAssertEqual(action.email, email)
            try await Auth.auth().applyActionCode(verification)
            try await session.reload(); XCTAssertTrue(session.isEmailVerified)
            do {
                try await Auth.auth().applyActionCode(verification)
                XCTFail("Consumed verification link must not be reusable")
            } catch { XCTAssertEqual((error as NSError).code, AuthErrorCode.invalidActionCode.rawValue) }
            try await service.sendPasswordReset(email: email)
            let reset = try await latestCode("PASSWORD_RESET", mode: "resetPassword")
            let resetEmail = try await Auth.auth().verifyPasswordResetCode(reset)
            XCTAssertEqual(resetEmail, email)
            try await Auth.auth().confirmPasswordReset(withCode: reset, newPassword: "Emulator-Only-Reset-2026!")
            try Auth.auth().signOut()
            do {
                _ = try await Auth.auth().signIn(withEmail: email, password: "Emulator-Only-2026!")
                XCTFail("Previous fixture password must stop working")
            } catch { XCTAssertNotNil(error as NSError) }
            let changed = try await Auth.auth().signIn(withEmail: email, password: "Emulator-Only-Reset-2026!")
            XCTAssertEqual(changed.user.uid, "closure-other")
            do {
                _ = try await Auth.auth().verifyPasswordResetCode(reset)
                XCTFail("Consumed reset link must not be reusable")
            } catch { XCTAssertEqual((error as NSError).code, AuthErrorCode.invalidActionCode.rawValue) }
            try await restoreFixture()
        } catch {
            try? await restoreFixture()
            throw error
        }
    }

    private func emulatorAuthObject(path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> [String: Any] {
        guard FirebaseApp.app()?.options.projectID == "demo-uac-release-audit",
              Firestore.firestore().settings.host == "127.0.0.1:28080" else {
            throw NSError(domain: "RefusingNonLocalAudit", code: 3)
        }
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:19099/" + path))
        var request = URLRequest(url: url); request.httpMethod = method
        request.setValue("Bearer owner", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func emulatorAuthProviders(userID: String) async throws -> Set<String> {
        guard ["closure-member", "closure-other"].contains(userID),
              FirebaseApp.app()?.options.projectID == "demo-uac-release-audit" else {
            throw NSError(domain: "RefusingNonLocalAudit", code: 2)
        }
        let url = URL(string: "http://127.0.0.1:19099/identitytoolkit.googleapis.com/v1/projects/demo-uac-release-audit/accounts:lookup")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer owner", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["localId": [userID]])
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let users = try XCTUnwrap(object["users"] as? [[String: Any]])
        let user = try XCTUnwrap(users.first { $0["localId"] as? String == userID })
        return Set((user["providerUserInfo"] as? [[String: Any]] ?? []).compactMap { $0["providerId"] as? String })
    }

    func testAuditFixturesAcceptActualRepositoryEditsAndPublicProfileSync() async throws {
        try await signIn("editor")
        defer { try? Auth.auth().signOut() }
        let user = try await UserProfileService.shared.fetchExistingUserProfile(uid: "closure-editor")
        try await UserProfileService.shared.upsertPublicProfile(for: user)
        let profile = try await Firestore.firestore().document("publicProfiles/closure-editor").getDocument(source: .server)
        XCTAssertEqual(profile.get("id") as? String, user.id)
        let news = FirestoreNewsRepository(sessionDataCache: SessionDataCache())
        let newsValue = try await news.fetchNews(id: "closure-news")
        try await news.updateNews(try XCTUnwrap(newsValue))
        let events = FirestoreEventRepository(sessionDataCache: SessionDataCache())
        let eventValue = try await events.fetchEvent(id: "closure-event")
        try await events.updateEvent(try XCTUnwrap(eventValue))
    }

    func testOrganizationLocationEditClearsOldCoordinatesThroughActualCommand() async throws {
        try await signIn("owner")
        defer { try? Auth.auth().signOut() }
        let repository = FirestoreOrganizationRepository(sessionDataCache: SessionDataCache())
        let id = "closure-location-" + UUID().uuidString.lowercased()
        let original = Organization(id: id, name: "Local location audit", description: "Isolated map pin persistence verification.",
            regionScope: .federalState, federalState: .tirol, city: "Innsbruck", address: "Maria-Theresien-Straße 18", latitude: 47.2682, longitude: 11.3923,
            organizationType: "education", ownerId: "closure-member", adminIds: [], moderatorIds: [],
            createdAt: .now, updatedAt: .now, moderationStatus: .approved, likeCount: 0, likeState: .notLiked)
        _ = try await CloudFunctionsClient.shared.acceptOrganizationRules(organizationId: id, organizationName: original.name,
            version: "2026.1", appVersion: "1.2.1", locale: "uk")
        try await repository.createOrganization(original)
        try await signIn("member")
        let user = try await UserProfileService.shared.fetchExistingUserProfile(uid: "closure-member")
        let model = OrganizationsViewModel(repository: repository)
        let created = try await repository.fetchOrganization(id: id)
        let rename = OrganizationEditorViewModel(mode: .edit(existing: created))
        rename.name = "Renamed local audit"
        let renamed = await rename.submit(with: model, user: user)
        XCTAssertTrue(renamed, rename.errorMessage ?? "Name edit must persist")
        let reference = Firestore.firestore().document("organizations/" + id)
        let retained = try await reference.getDocument(source: .server)
        XCTAssertEqual(retained.get("latitude") as? Double, 47.2682)
        XCTAssertEqual(retained.get("longitude") as? Double, 11.3923)
        let loaded = try await repository.fetchOrganization(id: id)
        let moved = OrganizationEditorViewModel(mode: .edit(existing: loaded))
        moved.city = "Wien"; moved.address = "A different street 2"; moved.selectedFederalState = .wien
        let saved = await moved.submit(with: model, user: user)
        XCTAssertTrue(saved, moved.errorMessage ?? "Address edit must persist")
        let cleared = try await reference.getDocument(source: .server)
        XCTAssertEqual(cleared.get("city") as? String, "Wien")
        XCTAssertEqual(cleared.get("address") as? String, "A different street 2")
        XCTAssertNil(cleared.get("latitude")); XCTAssertNil(cleared.get("longitude"))
        try await signIn("owner")
        try await repository.deleteOrganization(id: id)
        let removed = try await reference.getDocument(source: .server)
        XCTAssertFalse(removed.exists)
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

    func testActualEventCalendarWritesAllOccurrencesAndIndependentReadback() async throws {
        guard ProcessInfo.processInfo.environment["UACAuditCalendar"] == "1" else { throw XCTSkip("Dedicated simulator calendar permission phase") }
        try await signIn("member")
        defer { try? Auth.auth().signOut() }
        XCTAssertEqual(EKEventStore.authorizationStatus(for: .event), .fullAccess)
        let now = Date(), start = Date().addingTimeInterval(7 * 86400)
        let title = "UAC isolated calendar " + UUID().uuidString
        let occurrences = [EventOccurrence(id: "one", startDate: start, endDate: start.addingTimeInterval(3600)),
            EventOccurrence(id: "two", startDate: start.addingTimeInterval(86400), endDate: start.addingTimeInterval(90000))]
        let event = Event(id: "closure-calendar", title: title, summary: "Calendar audit summary", details: "Calendar audit details",
            city: "Innsbruck", venue: "Local test", address: "Test 1", startDate: start, endDate: start.addingTimeInterval(3600), occurrences: occurrences,
            createdAt: now, updatedAt: now, capacity: nil, registeredCount: 0, comments: [], moderationStatus: .approved,
            registrationState: .notRegistered, likeCount: 0, likeState: .notLiked)
        try await EventCalendarWriter().add(event)
        let readback = EKEventStore()
        let query = readback.predicateForEvents(withStart: start.addingTimeInterval(-60), end: start.addingTimeInterval(2 * 86400), calendars: nil)
        let saved = readback.events(matching: query).filter { $0.title == title }.sorted { $0.startDate < $1.startDate }
        defer { for item in saved { try? readback.remove(item, span: .thisEvent, commit: false) }; try? readback.commit() }
        XCTAssertEqual(saved.count, 2)
        for (item, occurrence) in zip(saved, occurrences) {
            XCTAssertEqual(item.startDate.timeIntervalSince1970, occurrence.startDate.timeIntervalSince1970, accuracy: 1)
            XCTAssertEqual(item.endDate.timeIntervalSince1970, occurrence.endDate.timeIntervalSince1970, accuracy: 1)
            XCTAssertEqual(item.location, "Local test, Test 1, Innsbruck")
            XCTAssertTrue(item.notes?.contains("Calendar audit details") == true)
        }
    }

    func testApplicantRequestCanBeRefetchedBeforeResubmission() async throws {
        guard ProcessInfo.processInfo.environment["UACRequestNotificationUIFixture"] == "1" else { throw XCTSkip("Dedicated linked applicant UI phase") }
        try await signIn("member")
        defer { try? Auth.auth().signOut() }
        let repository = FirestoreOrganizationRepository(sessionDataCache: SessionDataCache())
        let requests = try await repository.fetchOrganizationRequests(submittedByUserID: "closure-member")
        let request = try XCTUnwrap(requests.first { $0.name.hasPrefix("Closure Notification Request ") && $0.moderationStatus == .needsRevision })
        let refreshed = try await RefreshRequest.run { try await repository.fetchOrganization(id: request.id) }
        XCTAssertEqual(refreshed.id, request.id)
        XCTAssertEqual(refreshed.submittedByUserId, "closure-member")
        XCTAssertEqual(refreshed.moderationStatus, .needsRevision)
    }

    func testPrepareActualOrganizationRevisionNoticeForApplicantUI() async throws {
        guard ProcessInfo.processInfo.environment["UACRequestNotificationUIFixture"] == "1" else { throw XCTSkip("Dedicated linked applicant UI phase") }
        try await signIn("member")
        defer { try? Auth.auth().signOut() }
        let user = try await UserProfileService.shared.fetchExistingUserProfile(uid: "closure-member")
        let repository = FirestoreOrganizationRepository(sessionDataCache: SessionDataCache())
        let model = OrganizationsViewModel(repository: repository)
        let editor = OrganizationEditorViewModel()
        editor.name = "Closure Notification Request " + UUID().uuidString
        editor.shortDescription = "A synthetic request for an actual notification and resubmission journey."
        editor.city = "Innsbruck"; editor.selectedFederalState = .tirol
        let created = await editor.submit(with: model, user: user, organizationRulesVersion: "2026.1")
        XCTAssertTrue(created, editor.errorMessage ?? "Create failed")
        let requests = try await repository.fetchOrganizationRequests(submittedByUserID: user.id)
        let request = try XCTUnwrap(requests.first { $0.name.hasPrefix("Closure Notification Request ") && $0.moderationStatus == .pendingReview })
        try await signIn("owner")
        try await repository.requestOrganizationRevision(id: request.id, message: "Please clarify the local audit description.", reviewerID: "closure-owner")
        try await signIn("member")
        let stored = try await Firestore.firestore().document("organizations/" + request.id).getDocument(source: .server)
        XCTAssertEqual(stored.get("moderationStatus") as? String, "needsRevision")
        let notices = try await Firestore.firestore().collection("users/closure-member/notificationInbox").whereField("sourceId", isEqualTo: request.id).getDocuments(source: .server)
        XCTAssertTrue(notices.documents.contains { $0.get("type") as? String == "organizationRequestNeedsRevision" && $0.get("recipientUserId") as? String == user.id })
        // Intentionally retained for the next real SDK/UI test; that test removes
        // only this uniquely named local request and its exact recipient notice.
    }

    func testOrganizationRequestEditorRevisionResubmitRejectionApprovalHistoryAndTargetInbox() async throws {
        try await signIn("member")
        defer { try? Auth.auth().signOut() }
        let member = try await UserProfileService.shared.fetchExistingUserProfile(uid: "closure-member")
        let repository = FirestoreOrganizationRepository(sessionDataCache: SessionDataCache())
        let model = OrganizationsViewModel(repository: repository)
        let create = OrganizationEditorViewModel()
        let name = "Audit Request " + UUID().uuidString
        create.name = name; create.shortDescription = "Isolated organization request workflow verification."
        create.fullDescription = "Full local audit description with independently verified persistence."
        create.germanName = "Lokale Testorganisation"; create.germanShortDescription = "Lokale Prüfung des vollständigen Freigabeablaufs."
        create.selectedFederalState = .tirol; create.city = "Innsbruck"
        create.email = "audit@example.org"; create.phone = "+43000000000"; create.website = "https://example.org"
        create.address = "Test 1"; create.foundedYear = "2020"; create.foundedMonth = 3
        create.languages = "uk, de"; create.contactPerson = "Audit Contact"; create.missionStatement = "Local audit mission"
        create.profileKind = .business; create.secondaryCategories = ["culture", "integration"]
        create.serviceModes = [.online, .onSite]; create.serviceArea = "Tirol"
        create.regularHours = ["monday": "09:00-17:00", "sunday": "closed"]
        create.specialHoursNote = "Local audit hours"; create.services = "Advice, Meetings"
        create.orderURL = "https://example.org/order"; create.bookingURL = "https://example.org/book"
        create.currentOfferTitle = "Audit offer"; create.currentOfferDetails = "Local audit offer details"
        create.currentOfferURL = "https://example.org/offer"; create.currentOfferValidUntil = Date().addingTimeInterval(86400)
        create.telegramURL = "https://t.me/uac_test_fixture"; create.donationURL = "https://example.org/support"
        create.facebookURL = "https://facebook.com/uac_test_fixture"; create.instagramURL = "https://instagram.com/uac_test_fixture"
        create.whatsappURL = "https://wa.me/43000000000"; create.youtubeURL = "https://youtube.com/@uac_test_fixture"
        create.linkedinURL = "https://linkedin.com/company/uac_test_fixture"
        create.germanMissionStatement = "Lokaler Testauftrag"; create.germanServiceArea = "Tirol DE"
        create.germanSpecialHoursNote = "Lokale Testzeiten"; create.germanServices = "Beratung, Treffen"
        create.germanCurrentOfferTitle = "Testangebot"; create.germanCurrentOfferDetails = "Lokale Angebotsdetails"
        let saved = await create.submit(with: model, user: member, organizationRulesVersion: "2026.1")
        XCTAssertTrue(saved, create.errorMessage ?? "Create must persist")
        guard saved else { return }
        let requests = try await repository.fetchOrganizationRequests(submittedByUserID: member.id)
        let original = try XCTUnwrap(requests.first { $0.name == name })
        XCTAssertEqual(original.moderationStatus, .pendingReview)
        XCTAssertEqual(original.foundedYear, 2020); XCTAssertEqual(original.foundedMonth, 3)
        XCTAssertEqual(original.languages, ["uk", "de"]); XCTAssertEqual(original.contactPerson, "Audit Contact")
        let profile = try XCTUnwrap(original.directoryProfile)
        XCTAssertEqual(profile.profileKind, .business)
        XCTAssertEqual(Set(profile.secondaryCategories), ["culture", "integration"])
        XCTAssertEqual(Set(profile.serviceModes), [.online, .onSite])
        XCTAssertEqual(profile.regularHours, ["monday": "09:00-17:00", "sunday": "closed"])
        XCTAssertEqual(profile.services, ["Advice", "Meetings"])
        XCTAssertEqual(profile.bookingURL, "https://example.org/book")
        XCTAssertEqual(profile.orderURL, "https://example.org/order")
        XCTAssertEqual(profile.currentOfferTitle, "Audit offer")
        XCTAssertEqual(original.localizations["de"]?.services, ["Beratung", "Treffen"])
        XCTAssertEqual(original.localizations["de"]?.currentOfferDetails, "Lokale Angebotsdetails")
        let reopened = OrganizationEditorViewModel(mode: .edit(existing: original))
        XCTAssertEqual(reopened.telegramURL, "https://t.me/uac_test_fixture")
        XCTAssertEqual(reopened.donationURL, "https://example.org/support")
        XCTAssertEqual(reopened.facebookURL, "https://facebook.com/uac_test_fixture")
        XCTAssertEqual(reopened.instagramURL, "https://instagram.com/uac_test_fixture")
        XCTAssertEqual(reopened.whatsappURL, "https://wa.me/43000000000")
        XCTAssertEqual(reopened.youtubeURL, "https://youtube.com/@uac_test_fixture")
        XCTAssertEqual(reopened.linkedinURL, "https://linkedin.com/company/uac_test_fixture")
        XCTAssertEqual(reopened.germanMissionStatement, "Lokaler Testauftrag")
        XCTAssertEqual(reopened.germanServiceArea, "Tirol DE")
        XCTAssertEqual(reopened.germanSpecialHoursNote, "Lokale Testzeiten")
        let reference = Firestore.firestore().document("organizations/" + original.id)
        let initial = try await reference.getDocument(source: .server)
        XCTAssertEqual(initial.get("submittedByUserId") as? String, member.id)
        XCTAssertEqual(initial.get("email") as? String, "audit@example.org")
        try await signIn("owner")
        try await repository.requestOrganizationRevision(id: original.id, message: "Local audit: clarify opening hours", reviewerID: "closure-owner")
        let revision = try await reference.getDocument(source: .server)
        XCTAssertEqual(revision.get("moderationStatus") as? String, "needsRevision")
        try await signIn("member")
        for cycle in 0..<2 {
            let current = try await repository.fetchOrganization(id: original.id)
            let edit = OrganizationEditorViewModel(mode: .edit(existing: current))
            edit.fullDescription += " Correction \(cycle)."
            let updated = await edit.submit(with: model, user: member)
            XCTAssertTrue(updated, edit.errorMessage ?? "Resubmission must persist")
            guard updated else { return }
            let pending = try await reference.getDocument(source: .server)
            XCTAssertEqual(pending.get("moderationStatus") as? String, "pendingReview")
            XCTAssertEqual(pending.get("fullDescription") as? String, edit.fullDescription)
            try await signIn("owner")
            if cycle == 0 { try await repository.rejectOrganizationRequest(id: original.id, reason: "Local audit rejection with correction allowed", reviewerID: "closure-owner") }
            else { try await repository.approveOrganizationRequest(id: original.id, reviewerID: "closure-owner") }
            try await signIn("member")
        }
        let approved = try await reference.getDocument(source: .server)
        XCTAssertEqual(approved.get("moderationStatus") as? String, "approved")
        XCTAssertEqual(approved.get("ownerId") as? String, "closure-member")
        let notices = try await Firestore.firestore().collection("users/closure-member/notificationInbox").whereField("sourceId", isEqualTo: original.id).getDocuments(source: .server)
        for type in ["organizationRequestNeedsRevision", "organizationRequestRejected", "organizationRequestApproved"] {
            let notice = try XCTUnwrap(notices.documents.first { $0.get("type") as? String == type })
            XCTAssertEqual(notice.get("recipientUserId") as? String, "closure-member")
            XCTAssertEqual(notice.get("actionTargetId") as? String, original.id)
        }
        try await signIn("owner")
        let history = try await Functions.functions(region: "europe-west3").httpsCallable("listOrganizationReviewHistory").call(["limit": 30])
        let payload = try XCTUnwrap(history.data as? [String: Any])
        let rows = try XCTUnwrap(payload["items"] as? [[String: Any]]).filter { $0["organizationId"] as? String == original.id }
        XCTAssertEqual(Set(rows.compactMap { $0["status"] as? String }), ["needsRevision", "rejected", "approved"])
        XCTAssertTrue(rows.allSatisfy { ($0["organizationName"] as? String) == name })
        // Delete only the newly created isolated record through the actual server command.
        try await repository.deleteOrganization(id: original.id)
        let deleted = try await reference.getDocument(source: .server)
        XCTAssertFalse(deleted.exists)
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
