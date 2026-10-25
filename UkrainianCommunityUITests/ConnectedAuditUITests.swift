import XCTest
import CryptoKit

/// Real UI and actual SDK graph against the fixed demo emulators; no fixture roles/repositories.
@MainActor
final class ConnectedAuditUITests: XCTestCase {
    private let directoryUIFixtureID = "custom-" + UUID().uuidString.lowercased()
    private var ownedPhotoIDs = Set<String>()
    private var ownedDisposableUserIDs = Set<String>()
    private var ownedDeletionOperationIDs = Set<String>()
    private var ownedRequestDocumentPaths = Set<String>()
    override func setUpWithError() throws { continueAfterFailure = false }

    func testDisposableAccountDeletionConfirmsServerCleanupAndLanding() async throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" else { throw XCTSkip("Isolated demo required") }
        let suffix = "disposable-" + UUID().uuidString.lowercased()
        let email = "closure-" + suffix + "@uac.test"
        func authRequest(_ action: String, body: [String: Any]) async throws -> [String: Any] {
            // Fixed loopback Auth emulator only. This fixture is created here,
            // is never reused by another test and cannot target a real account.
            var request = URLRequest(url: URL(string: "http://127.0.0.1:19099/identitytoolkit.googleapis.com/v1/accounts:" + action + "?key=local-demo-only")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer owner", forHTTPHeaderField: "Authorization")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, response) = try await URLSession.shared.data(for: request)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
        let identity = try await authRequest("signUp", body: ["email": email, "password": "Emulator-Only-2026!", "returnSecureToken": true])
        let uid = try XCTUnwrap(identity["localId"] as? String)
        XCTAssertFalse(uid.hasPrefix("closure-"))
        ownedDisposableUserIDs.insert(uid)
        _ = try await authRequest("update", body: ["localId": uid, "emailVerified": true])
        let template = try await readDemoDocument("users/closure-member")
        var fields = try XCTUnwrap(template["fields"] as? [String: [String: Any]])
        fields["id"] = ["stringValue": uid]; fields["email"] = ["stringValue": email]
        fields["fullName"] = ["stringValue": "Disposable Audit Account"]
        fields["displayName"] = ["stringValue": "Disposable Audit Account"]
        fields["globalRole"] = ["stringValue": "user"]
        try await patchDemoDocument("users/" + uid, fields: fields)
        let app = launchMember(account: suffix)
        app.tabBars.buttons.element(boundBy: 4).tap()
        let settings = app.buttons["profile.settings.open"].firstMatch; reveal(settings, app); settings.tap()
        let deletion = app.buttons["profile.delete_account.button"].firstMatch; reveal(deletion, app); deletion.tap()
        let confirm = app.buttons["profile.delete_account.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 8)); XCTAssertFalse(confirm.isEnabled)
        capture(app, "sdk-disposable-delete-unconfirmed")
        app.buttons["Скасувати"].firstMatch.tap()
        _ = try await readDemoDocument("users/" + uid)
        reveal(deletion, app); deletion.tap()
        let keyword = app.textFields["profile.delete_account.confirmation"].firstMatch
        XCTAssertTrue(keyword.waitForExistence(timeout: 8)); keyword.tap(); keyword.typeText("ВИДАЛИТИ")
        if app.keyboards.firstMatch.exists {
            app.coordinate(withNormalizedOffset: .init(dx: 0.75, dy: 0.18)).tap()
        }
        reveal(confirm, app); XCTAssertTrue(confirm.isEnabled); capture(app, "sdk-disposable-delete-confirmed"); confirm.tap()
        XCTAssertTrue(app.buttons["auth.landing.signIn"].waitForExistence(timeout: 40))
        XCTAssertTrue(app.textFields["profile.delete_account.confirmation"].firstMatch.waitForNonExistence(timeout: 10))
        capture(app, "sdk-disposable-delete-landing")
        _ = try await demoRequest("users/" + uid, method: "GET", fields: nil, expectedStatus: 404)
        let lookup = try await authRequest("lookup", body: ["localId": [uid]])
        XCTAssertTrue((lookup["users"] as? [[String: Any]] ?? []).isEmpty)
        let operationID = SHA256.hash(data: Data(("account-deletion:" + uid).utf8)).map { String(format: "%02x", $0) }.joined()
        ownedDeletionOperationIDs.insert(operationID)
        let operation = try await readDemoDocument("accountDeletionOperations/" + operationID)
        let operationFields = try XCTUnwrap(operation["fields"] as? [String: [String: Any]])
        XCTAssertEqual(operationFields["status"]?["stringValue"] as? String, "completed")
        app.terminate()
    }

    func testConnectedOrganizationCommentDeleteReportAndHideExactAuthor() async throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" else { throw XCTSkip("Isolated demo required") }
        let stamp = ISO8601DateFormatter().string(from: Date())
        try await patchDemoDocument("organizations/closure-org", fields: ["adminIds": ["arrayValue": ["values": [["stringValue": "closure-editor"]]]]])
        for id in ["closure-delete", "closure-report"] {
            try await patchDemoDocument("organizations/closure-org/comments/" + id, fields: [
                "id": ["stringValue": id], "authorId": ["stringValue": "closure-other"],
                "authorName": ["stringValue": "Closure Other"], "text": ["stringValue": "Synthetic audit comment " + id],
                "parentType": ["stringValue": "organization"], "parentId": ["stringValue": "closure-org"],
                "createdAt": ["timestampValue": stamp], "moderationStatus": ["stringValue": "approved"], "isDeleted": ["booleanValue": false]])
        }
        _ = try await demoRequest("users/closure-editor/blockedUsers/closure-other", method: "DELETE", fields: nil)
        let app = launchMember(account: "editor")
        app.tabBars.buttons.element(boundBy: 2).tap()
        let card = app.buttons["organization.card.closure-org"].firstMatch
        reveal(card, app); card.tap()
        let deleteMenu = app.buttons["organization.comment.actions.closure-delete"].firstMatch
        reveal(deleteMenu, app); deleteMenu.tap()
        app.buttons["Видалити"].firstMatch.tap()
        capture(app, "sdk-org-comment-delete-confirm")
        // Cancel by tapping outside the native iPad-style confirmation popover on iOS 26.
        app.coordinate(withNormalizedOffset: .init(dx: 0.92, dy: 0.13)).tap()
        XCTAssertTrue(deleteMenu.exists)
        _ = try await readDemoDocument("organizations/closure-org/comments/closure-delete")
        deleteMenu.tap(); app.buttons["Видалити"].firstMatch.tap()
        app.buttons["Видалити"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["comments.row.closure-delete"].waitForNonExistence(timeout: 15))
        _ = try await demoRequest("organizations/closure-org/comments/closure-delete", method: "GET", fields: nil, expectedStatus: 404)
        let reportMenu = app.buttons["organization.comment.actions.closure-report"].firstMatch
        reveal(reportMenu, app); reportMenu.tap(); app.buttons["Поскаржитися"].firstMatch.tap()
        let submit = app.buttons["contentReport.submit"].firstMatch
        XCTAssertTrue(submit.waitForExistence(timeout: 8)); XCTAssertFalse(submit.isEnabled)
        app.buttons["contentReport.reason"].firstMatch.tap(); app.buttons["Спам або шахрайство"].firstMatch.tap()
        let details = app.textViews["contentReport.details"].firstMatch
        reveal(details, app); details.tap(); details.typeText("Synthetic local audit report; exact target and actor verification only.")
        let goodFaith = app.buttons["contentReport.goodFaith"].firstMatch
        reveal(goodFaith, app); goodFaith.tap()
        capture(app, "sdk-org-comment-report-ready")
        XCTAssertTrue(submit.isEnabled); submit.tap()
        XCTAssertTrue(app.descendants(matching: .any)["contentReport.success"].firstMatch.waitForExistence(timeout: 20))
        capture(app, "sdk-org-comment-report-receipt")
        let cases = try await readDemoDocument("dsaCases")
        let documents = try XCTUnwrap(cases["documents"] as? [[String: Any]])
        XCTAssertTrue(documents.contains { doc in
            guard let f = doc["fields"] as? [String: [String: Any]] else { return false }
            return f["targetId"]?["stringValue"] as? String == "closure-report"
                && f["parentId"]?["stringValue"] as? String == "closure-org"
                && f["targetAuthorId"]?["stringValue"] as? String == "closure-other"
                && f["reporterUserId"]?["stringValue"] as? String == "closure-editor"
        })
        app.buttons["contentReport.done"].tap()
        reveal(reportMenu, app); reportMenu.tap(); app.buttons["Заблокувати користувача"].firstMatch.tap()
        capture(app, "sdk-org-comment-hide-confirm")
        app.buttons["Заблокувати користувача"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["comments.row.closure-report"].waitForNonExistence(timeout: 15))
        let blocked = try await readDemoDocument("users/closure-editor/blockedUsers/closure-other")
        let fields = try XCTUnwrap(blocked["fields"] as? [String: [String: Any]])
        XCTAssertEqual(fields["targetUserId"]?["stringValue"] as? String, "closure-other")
        capture(app, "sdk-org-comment-hidden-exact-author")
        app.terminate()
        _ = try await demoRequest("users/closure-editor/blockedUsers/closure-other", method: "DELETE", fields: nil)
        try await patchDemoDocument("organizations/closure-org", fields: ["adminIds": ["arrayValue": ["values": []]]])
    }

    func testConnectedOrganizationTeamCandidateCancelAssignChangeAndRemove() async throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" else { throw XCTSkip("Isolated demo required") }
        try await patchDemoDocument("organizations/closure-org", fields: ["ownerId": ["stringValue": "closure-editor"], "adminIds": ["arrayValue": ["values": []]], "moderatorIds": ["arrayValue": ["values": []]]])
        try await patchDemoDocument("likes/organization_follow_closure-org_closure-other", fields: ["userId": ["stringValue": "closure-other"], "subscribedOrganizationId": ["stringValue": "closure-org"], "createdAt": ["timestampValue": ISO8601DateFormatter().string(from: Date())]])
        try await patchDemoDocument("publicProfiles/closure-other", fields: ["id": ["stringValue": "closure-other"], "displayName": ["stringValue": "Closure Other"], "city": ["stringValue": "Innsbruck"], "federalState": ["stringValue": "tirol"]])
        let app = launchMember(large: true, account: "editor")
        app.tabBars.buttons.element(boundBy: 4).tap()
        let management = app.buttons["profile.organizationManagement"].firstMatch
        reveal(management, app); management.tap()
        let manage = app.buttons["organization.manage.closure-org"].firstMatch
        reveal(manage, app); manage.tap()
        let contacts = app.buttons["organization.contact.edit"].firstMatch
        reveal(contacts, app); capture(app, "sdk-org-contacts-accessibility-actions")
        let add = app.buttons["organization.management.addTeamMember"].firstMatch
        reveal(add, app); add.tap()
        let candidate = app.buttons["organization.team.candidate.closure-other"].firstMatch
        XCTAssertTrue(candidate.waitForExistence(timeout: 15)); capture(app, "sdk-org-team-candidate-list")
        app.buttons["organization.team.cancelSearch"].tap()
        let before = try await readDemoDocument("organizations/closure-org")
        XCTAssertFalse(String(describing: (before["fields"] as? [String: [String: Any]])?["moderatorIds"]).contains("closure-other"))
        reveal(add, app); add.tap(); XCTAssertTrue(candidate.waitForExistence(timeout: 15)); candidate.tap()
        let confirm = app.buttons["organization.team.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); capture(app, "sdk-org-team-assign-confirm"); confirm.tap()
        let actions = app.buttons["organization.team.actions.closure-other"].firstMatch
        reveal(actions, app); XCTAssertTrue(actions.waitForExistence(timeout: 15))
        var stored = try await readDemoDocument("organizations/closure-org")
        XCTAssertTrue(String(describing: stored).contains("closure-other"))
        capture(app, "sdk-org-team-assigned-row")
        actions.tap(); app.buttons["organization.team.assign.admin.closure-other"].firstMatch.tap(); XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        for _ in 0..<15 {
            stored = try await readDemoDocument("organizations/closure-org")
            if let fields = stored["fields"] as? [String: [String: Any]], String(describing: fields["adminIds"]).contains("closure-other") { break }
            try await Task.sleep(for: .milliseconds(200))
        }
        let fields = try XCTUnwrap(stored["fields"] as? [String: [String: Any]])
        XCTAssertTrue(String(describing: fields["adminIds"]).contains("closure-other"))
        reveal(actions, app); actions.tap(); app.buttons["Зняти роль"].firstMatch.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); capture(app, "sdk-org-team-remove-confirm"); confirm.tap()
        XCTAssertTrue(actions.waitForNonExistence(timeout: 15))
        let removed = try await readDemoDocument("organizations/closure-org")
        let removedFields = try XCTUnwrap(removed["fields"] as? [String: [String: Any]])
        for key in ["adminIds", "moderatorIds"] { XCTAssertFalse(String(describing: removedFields[key]).contains("closure-other")) }
        capture(app, "sdk-org-team-after-removal")
        app.terminate()
        try await patchDemoDocument("organizations/closure-org", fields: ["ownerId": ["stringValue": "closure-owner"]])
    }

    func testOrganizationTeamConfirmationRejectsConcurrentRemoval() async throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" else { throw XCTSkip("Isolated demo required") }
        try await patchDemoDocument("organizations/closure-org", fields: ["ownerId": ["stringValue": "closure-editor"], "adminIds": ["arrayValue": ["values": [["stringValue": "closure-other"]]]], "moderatorIds": ["arrayValue": ["values": []]]])
        let app = launchMember(account: "editor")
        app.tabBars.buttons.element(boundBy: 4).tap()
        for id in ["profile.organizationManagement", "organization.manage.closure-org"] {
            let b = app.buttons[id].firstMatch; reveal(b, app); b.tap()
        }
        let actions = app.buttons["organization.team.actions.closure-other"].firstMatch
        reveal(actions, app); actions.tap()
        app.buttons["organization.team.assign.moderator.closure-other"].firstMatch.tap()
        let confirm = app.buttons["organization.team.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); capture(app, "sdk-team-concurrent-removal-confirmation")
        let stamp = ISO8601DateFormatter().string(from: Date())
        try await patchDemoDocument("organizations/closure-org", fields: ["adminIds": ["arrayValue": ["values": []]], "moderatorIds": ["arrayValue": ["values": []]], "updatedAt": ["timestampValue": stamp]])
        // Let the actual realtime organization observation receive the new team
        // while the native confirmation remains open.
        try await Task.sleep(for: .seconds(1))
        confirm.tap()
        let conflict = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Дані або роль змінилися")).firstMatch
        reveal(conflict, app); XCTAssertTrue(conflict.waitForExistence(timeout: 10)); capture(app, "sdk-team-concurrent-removal-rejected")
        let document = try await readDemoDocument("organizations/closure-org")
        let fields = try XCTUnwrap(document["fields"] as? [String: [String: Any]])
        for key in ["adminIds", "moderatorIds"] { XCTAssertFalse(String(describing: fields[key]).contains("closure-other")) }
        app.terminate()
        try await patchDemoDocument("organizations/closure-org", fields: ["ownerId": ["stringValue": "closure-owner"]])
    }

    func testConnectedNewsPhotoCropSaveAndReopen() async throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" else { throw XCTSkip("Isolated demo required") }
        try await patchDemoDocument("organizations/closure-org", fields: ["adminIds": ["arrayValue": ["values": [["stringValue": "closure-editor"]]]]])
        let app = launchMember(account: "editor")
        let card = app.buttons["home.card.news-closure-news"].firstMatch
        reveal(card, app); card.tap()
        app.buttons["detail.header.more-actions"].firstMatch.tap(); app.buttons["Редагувати"].firstMatch.tap()
        let next = app.buttons["editor.news.next"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 10)); next.tap()
        let picker = app.buttons["editor.news.photo"].firstMatch
        reveal(picker, app); picker.tap()
        let photo = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 10))
        app.buttons["Abbrechen"].firstMatch.tap(); XCTAssertTrue(photo.waitForNonExistence(timeout: 8))
        picker.tap(); XCTAssertTrue(photo.waitForExistence(timeout: 10)); photo.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).tap()
        let apply = app.buttons["imageCrop.apply"].firstMatch
        XCTAssertTrue(apply.waitForExistence(timeout: 10)); capture(app, "sdk-news-landscape-crop")
        app.buttons["imageCrop.cancel"].tap(); XCTAssertTrue(apply.waitForNonExistence(timeout: 8))
        picker.tap(); XCTAssertTrue(photo.waitForExistence(timeout: 10)); photo.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(apply.waitForExistence(timeout: 10)); apply.tap(); XCTAssertTrue(apply.waitForNonExistence(timeout: 10))
        reveal(next, app); next.tap()
        let submit = app.buttons["editor.news.submit"].firstMatch
        reveal(submit, app); XCTAssertTrue(submit.isEnabled); submit.tap()
        XCTAssertTrue(submit.waitForNonExistence(timeout: 30))
        let doc = try await readDemoDocument("news/closure-news")
        let fields = try XCTUnwrap(doc["fields"] as? [String: [String: Any]])
        let image = try XCTUnwrap(fields["imageURL"]?["stringValue"] as? String)
        try await assertLocalImageDownload(image)
        app.buttons["detail.header.more-actions"].firstMatch.tap(); app.buttons["Редагувати"].firstMatch.tap()
        XCTAssertTrue(next.waitForExistence(timeout: 10)); next.tap(); reveal(picker, app)
        capture(app, "sdk-news-photo-saved-reopened")
        app.terminate()
    }

    func testConnectedEventPhotoCropSaveAndReopen() async throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" else { throw XCTSkip("Isolated demo required") }
        try await patchDemoDocument("organizations/closure-org", fields: ["adminIds": ["arrayValue": ["values": [["stringValue": "closure-editor"]]]]])
        let app = launchMember(account: "editor")
        app.tabBars.buttons.element(boundBy: 1).tap()
        let card = app.buttons["event.card.closure-event"].firstMatch; reveal(card, app); card.tap()
        app.buttons["detail.header.more-actions"].firstMatch.tap(); app.buttons["Редагувати"].firstMatch.tap()
        let picker = app.buttons["editor.event.photo"].firstMatch; reveal(picker, app); picker.tap()
        let photo = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 10)); photo.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).tap()
        let apply = app.buttons["imageCrop.apply"].firstMatch
        XCTAssertTrue(apply.waitForExistence(timeout: 10)); capture(app, "sdk-event-landscape-crop")
        app.buttons["imageCrop.cancel"].firstMatch.tap(); XCTAssertTrue(apply.waitForNonExistence(timeout: 10))
        picker.tap(); XCTAssertTrue(photo.waitForExistence(timeout: 10))
        photo.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(apply.waitForExistence(timeout: 10)); apply.tap()
        XCTAssertTrue(apply.waitForNonExistence(timeout: 10))
        for _ in 0..<3 { let next = app.buttons["editor.event.next"].firstMatch; reveal(next, app); XCTAssertTrue(next.isEnabled); next.tap() }
        let submit = app.buttons["editor.event.submit"].firstMatch; reveal(submit, app); XCTAssertTrue(submit.isEnabled); submit.tap()
        XCTAssertTrue(submit.waitForNonExistence(timeout: 30))
        let document = try await readDemoDocument("events/closure-event")
        let fields = try XCTUnwrap(document["fields"] as? [String: [String: Any]])
        try await assertLocalImageDownload(try XCTUnwrap(fields["imageURL"]?["stringValue"] as? String))
        app.buttons["detail.header.more-actions"].firstMatch.tap(); app.buttons["Редагувати"].firstMatch.tap()
        reveal(picker, app); capture(app, "sdk-event-photo-saved-reopened"); app.terminate()
    }

    func testConnectedOrganizationGalleryPhotoSaveReadAndDelete() async throws {
        try await organizationGalleryJourney(replacing: false)
    }

    func testConnectedOrganizationGalleryReplacementConflictReloadAndRetry() async throws {
        try await organizationGalleryJourney(replacing: true)
    }

    private func organizationGalleryJourney(replacing: Bool) async throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" else { throw XCTSkip("Isolated demo required") }
        if replacing {
            try await patchDemoDocument("serverConfiguration/organizationAccess", fields: [
                "mode": ["stringValue": "enforced"], "commandsEnabled": ["booleanValue": true],
                "commandModes": ["mapValue": ["fields": ["updateOrganizationInfo": ["stringValue": "enforced"], "saveOrganizationPhoto": ["stringValue": "enforced"]]]]])
        }
        try await patchDemoDocument("organizations/closure-org", fields: ["ownerId": ["stringValue": "closure-editor"]])
        let app = launchMember(account: "editor")
        app.tabBars.buttons.element(boundBy: 4).tap()
        let management = app.buttons["profile.organizationManagement"].firstMatch
        reveal(management, app); management.tap()
        let manage = app.buttons["organization.manage.closure-org"].firstMatch
        reveal(manage, app); manage.tap()
        let add = app.buttons["organization.photo.add"].firstMatch
        reveal(add, app); add.tap()
        let photo = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 10)); photo.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).tap()
        let caption = app.textFields["organization.photo.caption"].firstMatch
        XCTAssertTrue(caption.waitForExistence(timeout: 10)); caption.tap(); caption.typeText("Local gallery verification")
        capture(app, "sdk-organization-photo-caption-ready")
        let upload = app.buttons["organization.photo.upload"].firstMatch
        XCTAssertTrue(upload.isEnabled); upload.tap(); XCTAssertTrue(upload.waitForNonExistence(timeout: 30))
        let collection = try await readDemoDocument("organizations/closure-org/photos")
        let docs = try XCTUnwrap(collection["documents"] as? [[String: Any]])
        let document = try XCTUnwrap(docs.first { ($0["fields"] as? [String: [String: Any]])?["caption"]?["stringValue"] as? String == "Local gallery verification" })
        let fields = try XCTUnwrap(document["fields"] as? [String: [String: Any]])
        let id = try XCTUnwrap(fields["id"]?["stringValue"] as? String)
        ownedPhotoIDs.insert(id)
        XCTAssertEqual(fields["uploadedBy"]?["stringValue"] as? String, "closure-editor")
        try await assertLocalImageDownload(try XCTUnwrap(fields["imageURL"]?["stringValue"] as? String))
        let open = app.buttons["organization.photo.open." + id].firstMatch
        reveal(open, app); open.tap()
        XCTAssertTrue(app.descendants(matching: .any)["organization.photo.image.loaded." + id].firstMatch.waitForExistence(timeout: 15))
        capture(app, "sdk-organization-photo-fullscreen")
        app.buttons["Готово"].firstMatch.tap()
        if replacing {
            reveal(open, app); open.press(forDuration: 1)
            app.buttons["organization.photo.replace." + id].firstMatch.tap()
            XCTAssertTrue(photo.waitForExistence(timeout: 10))
            photo.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).tap()
            XCTAssertTrue(upload.waitForExistence(timeout: 10))
            let path = "organizations/closure-org/photos/" + id
            let originalURL = try XCTUnwrap(fields["imageURL"]?["stringValue"] as? String)
            let concurrentURL = originalURL + (originalURL.contains("?") ? "&" : "?") + "auditRevision=2"
            try await patchDemoDocument(path, fields: ["imageURL": ["stringValue": concurrentURL]])
            upload.tap()
            let reload = app.buttons["organization.photo.editor.reload"].firstMatch
            XCTAssertTrue(reload.waitForExistence(timeout: 20)); capture(app, "sdk-organization-photo-replacement-conflict")
            reload.tap(); XCTAssertTrue(reload.waitForNonExistence(timeout: 15))
            XCTAssertTrue(upload.isEnabled); upload.tap(); XCTAssertTrue(upload.waitForNonExistence(timeout: 30))
            let updated = try await readDemoDocument(path)
            let replacementFields = try XCTUnwrap(updated["fields"] as? [String: [String: Any]])
            let replacementURL = try XCTUnwrap(replacementFields["imageURL"]?["stringValue"] as? String)
            XCTAssertNotEqual(replacementURL, originalURL); XCTAssertNotEqual(replacementURL, concurrentURL)
            XCTAssertEqual(replacementFields["id"]?["stringValue"] as? String, id)
            try await assertLocalImageDownload(replacementURL)
            capture(app, "sdk-organization-photo-replaced-after-reload")
        }
        let delete = app.buttons["organization.photo.delete." + id].firstMatch
        reveal(delete, app); delete.tap(); capture(app, "sdk-organization-photo-delete-confirm")
        app.buttons["Видалити фото"].firstMatch.tap()
        XCTAssertTrue(open.waitForNonExistence(timeout: 15))
        let after = try await readDemoDocument("organizations/closure-org/photos")
        XCTAssertFalse(String(describing: after).contains(id))
        app.terminate()
        try await patchDemoDocument("organizations/closure-org", fields: ["ownerId": ["stringValue": "closure-owner"]])
    }

    func testApplicantOpensActualRevisionNoticeEditsAndResubmitsExactRequest() async throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1", ProcessInfo.processInfo.environment["UACRequestNotificationUIFixture"] == "1" else { throw XCTSkip("Dedicated linked applicant UI phase") }
        let collection = try await readDemoDocument("organizations")
        let documents = try XCTUnwrap(collection["documents"] as? [[String: Any]])
        let document = try XCTUnwrap(documents.first { doc in
            guard let f = doc["fields"] as? [String: [String: Any]] else { return false }
            return (f["name"]?["stringValue"] as? String ?? "").hasPrefix("Closure Notification Request ")
                && f["submittedByUserId"]?["stringValue"] as? String == "closure-member"
                && f["moderationStatus"]?["stringValue"] as? String == "needsRevision"
        })
        let fields = try XCTUnwrap(document["fields"] as? [String: [String: Any]])
        let id = try XCTUnwrap(fields["id"]?["stringValue"] as? String)
        let inbox = try await readDemoDocument("users/closure-member/notificationInbox")
        let notices = try XCTUnwrap(inbox["documents"] as? [[String: Any]])
        let notice = try XCTUnwrap(notices.first { doc in
            guard let f = doc["fields"] as? [String: [String: Any]] else { return false }
            return f["sourceId"]?["stringValue"] as? String == id && f["type"]?["stringValue"] as? String == "organizationRequestNeedsRevision"
                && f["recipientUserId"]?["stringValue"] as? String == "closure-member"
        })
        let noticeName = try XCTUnwrap(notice["name"] as? String)
        let noticeID = try XCTUnwrap(noticeName.split(separator: "/").last.map(String.init))
        ownedRequestDocumentPaths.formUnion(["organizations/" + id, "users/closure-member/notificationInbox/" + noticeID])
        let maximumText = ProcessInfo.processInfo.environment["UACApplicantMaximumText"] == "1"
        let app = launchMember(language: maximumText ? "de" : "uk", appearance: maximumText ? "dark" : "light", maximumText: maximumText)
        app.tabBars.buttons.element(boundBy: 4).tap()
        let entry = app.buttons["profile.notifications.open"].firstMatch; reveal(entry, app); capture(app, "sdk-applicant-profile-navigation"); entry.tap()
        let row = app.buttons.matching(NSPredicate(format: "identifier == %@", "notificationInbox.open." + noticeID)).firstMatch
        reveal(row, app); row.tap()
        let destination = app.buttons["notificationDetail.openDestination"].firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout: 10)); capture(app, "sdk-applicant-revision-notice"); destination.tap()
        let edit = app.buttons["organization.request.preview." + id].firstMatch
        reveal(edit, app); edit.tap()
        let name = app.textFields["organization.editor.name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 10)); XCTAssertEqual(name.value as? String, fields["name"]?["stringValue"] as? String)
        let description = app.descendants(matching: .any)["organization.editor.description"].firstMatch
        reveal(description, app); description.tap(); description.tap(withNumberOfTaps: 4, numberOfTouches: 1)
        let corrected = "Corrected local audit description from the actual recipient notification."
        description.typeText(corrected); XCTAssertEqual(description.value as? String, corrected)
        if app.keyboards.firstMatch.exists { app.coordinate(withNormalizedOffset: .init(dx: 0.75, dy: 0.12)).tap() }
        for _ in 0..<3 { let next = app.buttons["organizationEditor.next"].firstMatch; reveal(next, app); XCTAssertTrue(next.isEnabled); next.tap() }
        let submit = app.buttons["organizationEditor.submit"].firstMatch; reveal(submit, app); capture(app, "sdk-applicant-resubmission-preview"); submit.tap()
        if !submit.waitForNonExistence(timeout: 35), maximumText {
            capture(app, "sdk-applicant-resubmission-retry-state")
            // Exercise the visible retry using the retained draft, never an API
            // write or a fabricated successful response.
            XCTAssertTrue(submit.isEnabled, "Submission must finish or expose an enabled retry")
            XCTAssertTrue(app.staticTexts[corrected].firstMatch.exists)
            reveal(submit, app); submit.tap()
        }
        XCTAssertTrue(submit.waitForNonExistence(timeout: 35))
        let saved = try await readDemoDocument("organizations/" + id)
        let updated = try XCTUnwrap(saved["fields"] as? [String: [String: Any]])
        XCTAssertEqual(updated["moderationStatus"]?["stringValue"] as? String, "pendingReview")
        XCTAssertEqual(updated["shortDescription"]?["stringValue"] as? String, corrected)
        XCTAssertNil(updated["reviewMessage"]); XCTAssertNil(updated["rejectionReason"])
        let resubmitted = app.buttons["organization.request.preview." + id].firstMatch
        reveal(resubmitted, app)
        capture(app, "sdk-applicant-resubmitted-exact-request")
        app.terminate()
        for path in ownedRequestDocumentPaths { _ = try await demoRequest(path, method: "DELETE", fields: nil) }
    }

    func testOrganizationAuthorityRevocationClosesOpenDraftWithoutSaving() async throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" else { throw XCTSkip("Isolated demo required") }
        try await patchDemoDocument("organizations/closure-org", fields: ["ownerId": ["stringValue": "closure-editor"], "adminIds": ["arrayValue": ["values": []]], "moderatorIds": ["arrayValue": ["values": []]]])
        let app = launchMember(account: "editor")
        app.tabBars.buttons.element(boundBy: 4).tap()
        for id in ["profile.organizationManagement", "organization.manage.closure-org", "organization.management.editInfo"] {
            let button = app.buttons[id].firstMatch; reveal(button, app); button.tap()
        }
        let name = app.textFields["organization.editor.name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 10)); name.tap(); name.typeText(" Unsaved revoked draft")
        capture(app, "sdk-organization-authority-before-revocation")
        try await patchDemoDocument("organizations/closure-org", fields: ["ownerId": ["stringValue": "closure-other"]])
        XCTAssertTrue(app.buttons["editor.close"].firstMatch.waitForNonExistence(timeout: 15))
        XCTAssertFalse(app.buttons["organization.management.editInfo"].firstMatch.exists)
        XCTAssertFalse(app.buttons["organization.management.createNews"].firstMatch.exists)
        capture(app, "sdk-organization-authority-revoked")
        let document = try await readDemoDocument("organizations/closure-org")
        let fields = try XCTUnwrap(document["fields"] as? [String: [String: Any]])
        XCTAssertFalse((fields["name"]?["stringValue"] as? String ?? "").contains("Unsaved revoked draft"))
        XCTAssertEqual(fields["ownerId"]?["stringValue"] as? String, "closure-other")
        app.terminate()
        try await patchDemoDocument("organizations/closure-org", fields: ["ownerId": ["stringValue": "closure-owner"]])
    }

    func testConnectedOrganizationAllEditableFieldsLogoSaveAndReopen() async throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" else { throw XCTSkip("Isolated demo required") }
        try await patchDemoDocument("organizations/closure-org", fields: ["ownerId": ["stringValue": "closure-editor"]])
        let app = launchMember(account: "editor")
        app.tabBars.buttons.element(boundBy: 4).tap()
        for id in ["profile.organizationManagement", "organization.manage.closure-org", "organization.management.editInfo"] {
            let button = app.buttons[id].firstMatch; reveal(button, app); button.tap()
        }
        func tap(_ id: String, towardTop: Bool = false) {
            let e: XCUIElement
            if id.contains("localization.german") { e = app.descendants(matching: .any)[id].firstMatch }
            else if id.hasPrefix("organization.editor.hours.") || id == "organization.editor.offerExpiration" { e = app.switches[id].firstMatch }
            else { e = app.buttons[id].firstMatch }
            reveal(e, app, preferUpwardScroll: towardTop); XCTAssertTrue(e.isEnabled, id); e.tap()
        }
        func field(_ id: String, _ value: String) {
            let input = app.descendants(matching: .any).matching(NSPredicate(format: "identifier == %@ AND (elementType == %d OR elementType == %d)", id, XCUIElement.ElementType.textField.rawValue, XCUIElement.ElementType.textView.rawValue)).firstMatch
            reveal(input, app); input.tap()
            if let old = input.value as? String, !old.isEmpty, old != input.placeholderValue {
                // Native paragraph selection replaces the existing multiline
                // value without relying on a cursor position or localized menu.
                input.tap(withNumberOfTaps: 4, numberOfTouches: 1)
            }
            input.typeText(value)
            XCTAssertEqual(input.value as? String, value, id)
            if app.keyboards.firstMatch.exists {
                app.coordinate(withNormalizedOffset: .init(dx: 0.75, dy: 0.12)).tap()
                XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
            }
        }
        tap("organization.editor.kind.business")
        tap("organization.editor.logo")
        let photo = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 10)); photo.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).tap()
        let apply = app.buttons["imageCrop.apply"].firstMatch
        XCTAssertTrue(apply.waitForExistence(timeout: 10)); capture(app, "sdk-organization-logo-square-crop"); apply.tap()
        XCTAssertTrue(apply.waitForNonExistence(timeout: 10))
        for (id, value) in [("name", "Closure UI Complete"), ("description", "UI form persistence verification."), ("mission", "Audit mission"), ("fullDescription", "Audit full description"), ("field.calendar", "2020"), ("field.globe.europe.africa", "uk, de")] { field("organization.editor." + id, value) }
        tap("organization.editor.foundedMonth")
        let month = app.buttons["organization.editor.month.3"].firstMatch
        if !month.waitForExistence(timeout: 5) {
            capture(app, "sdk-organization-month-picker-diagnostic")
            let tree = XCTAttachment(string: app.debugDescription); tree.name = "organization-month-picker-tree"; tree.lifetime = .keepAlways; add(tree)
        }
        XCTAssertTrue(month.exists); month.tap()
        tap("organization.editor.category.education", towardTop: true)
        tap("organization.editor.secondary.culture"); tap("organization.editor.secondary.integration")
        tap("organization.editor.localization.german")
        for (id, value) in [("name", "Lokale UI Organisation"), ("description", "Lokale UI Beschreibung"), ("mission", "Lokaler UI Auftrag"), ("fullDescription", "Vollständige UI Beschreibung")] { field("organization.editor.german." + id, value) }
        capture(app, "sdk-organization-basics-bilingual-ready")
        tap("organizationEditor.next")
        tap("organization.editor.region"); app.buttons["Відень"].firstMatch.tap()
        field("organization.editor.city", "Wien")
        let contacts = [("mappin.circle", "Auditstraße 1"), ("envelope", "audit@example.org"), ("phone", "+43000000000"), ("globe", "https://example.org"), ("paperplane", "https://t.me/uac_test_fixture"), ("heart", "https://example.org/support"), ("person.crop.circle", "Audit Contact"), ("person.2", "https://facebook.com/uac_test_fixture"), ("camera", "https://instagram.com/uac_test_fixture"), ("phone.bubble", "https://wa.me/43000000000"), ("play.rectangle", "https://youtube.com/@uac_test_fixture"), ("briefcase", "https://linkedin.com/company/uac_test_fixture")]
        for (id, value) in contacts { field("organization.editor.field." + id, value) }
        capture(app, "sdk-organization-contacts-ready"); tap("organizationEditor.next")
        tap("organization.editor.mode.online"); tap("organization.editor.mode.onSite")
        for (id, value) in [("field.map", "Wien"), ("services", "Advice, Meetings"), ("field.calendar.badge.exclamationmark", "Audit special hours"), ("field.bag", "https://example.org/order"), ("field.calendar.badge.plus", "https://example.org/book"), ("field.tag", "UI offer"), ("offerDetails", "UI offer details"), ("field.link", "https://example.org/offer")] { field("organization.editor." + id, value) }
        tap("organization.editor.hours.monday", towardTop: true); tap("organization.editor.offerExpiration")
        tap("organization.editor.directory.localization.german")
        for (id, value) in [("area", "Wien DE"), ("services", "Beratung, Treffen"), ("hours", "Lokale Testzeiten"), ("offerTitle", "UI Angebot"), ("offerDetails", "UI Angebotsdetails")] { field("organization.editor.german." + id, value) }
        capture(app, "sdk-organization-directory-bilingual-ready"); tap("organizationEditor.next")
        let submit = app.buttons["organizationEditor.submit"].firstMatch
        reveal(submit, app); XCTAssertTrue(submit.isEnabled); capture(app, "sdk-organization-all-fields-preview"); submit.tap()
        XCTAssertTrue(submit.waitForNonExistence(timeout: 30))
        let document = try await readDemoDocument("organizations/closure-org")
        let fields = try XCTUnwrap(document["fields"] as? [String: [String: Any]])
        let top = ["name": "Closure UI Complete", "shortDescription": "UI form persistence verification.", "missionStatement": "Audit mission", "fullDescription": "Audit full description", "city": "Wien", "address": "Auditstraße 1", "email": "audit@example.org", "phone": "+43000000000", "website": "https://example.org", "contactPerson": "Audit Contact", "organizationType": "education", "telegramURL": "https://t.me/uac_test_fixture", "donationURL": "https://example.org/support", "facebookURL": "https://facebook.com/uac_test_fixture", "instagramURL": "https://instagram.com/uac_test_fixture", "whatsappURL": "https://wa.me/43000000000", "youtubeURL": "https://youtube.com/@uac_test_fixture", "linkedinURL": "https://linkedin.com/company/uac_test_fixture"]
        for (key, value) in top { XCTAssertEqual(fields[key]?["stringValue"] as? String, value, key) }
        func strings(_ value: [String: Any]?) -> [String] {
            ((value?["arrayValue"] as? [String: Any])?["values"] as? [[String: Any]] ?? []).compactMap { $0["stringValue"] as? String }
        }
        XCTAssertEqual(strings(fields["languages"]), ["uk", "de"])
        XCTAssertEqual(fields["federalState"]?["stringValue"] as? String, "wien")
        XCTAssertEqual(fields["foundedYear"]?["integerValue"] as? String, "2020"); XCTAssertEqual(fields["foundedMonth"]?["integerValue"] as? String, "3")
        let profile = try XCTUnwrap((fields["directoryProfile"]?["mapValue"] as? [String: Any])?["fields"] as? [String: [String: Any]])
        XCTAssertEqual(Set(strings(profile["secondaryCategories"])), ["culture", "integration"])
        XCTAssertEqual(Set(strings(profile["serviceModes"])), ["online", "onSite"])
        XCTAssertEqual(strings(profile["services"]), ["Advice", "Meetings"])
        for (key, value) in ["profileKind": "business", "serviceArea": "Wien", "specialHoursNote": "Audit special hours", "orderURL": "https://example.org/order", "bookingURL": "https://example.org/book", "currentOfferTitle": "UI offer", "currentOfferDetails": "UI offer details", "currentOfferURL": "https://example.org/offer"] { XCTAssertEqual(profile[key]?["stringValue"] as? String, value, key) }
        XCTAssertNotNil(profile["currentOfferValidUntil"]?["timestampValue"])
        let hours = (profile["regularHours"]?["mapValue"] as? [String: Any])?["fields"] as? [String: [String: Any]]
        XCTAssertEqual(hours?["monday"]?["stringValue"] as? String, "09:00-18:00")
        let localized = try XCTUnwrap((fields["localizations"]?["mapValue"] as? [String: Any])?["fields"] as? [String: [String: Any]])
        let de = try XCTUnwrap((localized["de"]?["mapValue"] as? [String: Any])?["fields"] as? [String: [String: Any]])
        XCTAssertEqual(strings(de["services"]), ["Beratung", "Treffen"])
        for (key, value) in ["name": "Lokale UI Organisation", "shortDescription": "Lokale UI Beschreibung", "missionStatement": "Lokaler UI Auftrag", "fullDescription": "Vollständige UI Beschreibung", "serviceArea": "Wien DE", "specialHoursNote": "Lokale Testzeiten", "currentOfferTitle": "UI Angebot", "currentOfferDetails": "UI Angebotsdetails"] { XCTAssertEqual(de[key]?["stringValue"] as? String, value, "de." + key) }
        let logo = try XCTUnwrap(fields["imageURL"]?["stringValue"] as? String); try await assertLocalImageDownload(logo)
        tap("organization.management.editInfo")
        let name = app.textFields["organization.editor.name"].firstMatch; reveal(name, app)
        XCTAssertEqual(name.value as? String, "Closure UI Complete"); capture(app, "sdk-organization-all-fields-reopened")
        app.terminate()
    }

    private func assertLocalImageDownload(_ url: String) async throws {
        var components = try XCTUnwrap(URLComponents(string: url))
        XCTAssertEqual(components.host, "firebasestorage.googleapis.com")
        components.scheme = "http"; components.host = "127.0.0.1"; components.port = 29199
        let (data, response) = try await URLSession.shared.data(from: try XCTUnwrap(components.url))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(data.prefix(2), Data([0xff,0xd8]))
    }

    func testConnectedEventCalendarAuthorizationAndRegistration() async throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1", let phase = ProcessInfo.processInfo.environment["UACCalendarUIPhase"], ["deny", "allow"].contains(phase) else { throw XCTSkip("Dedicated simulator Calendar phase") }
        let app = launchMember()
        app.tabBars.buttons.element(boundBy: 1).tap()
        let card = app.buttons["event.card.closure-event"].firstMatch
        reveal(card, app); card.tap()
        let calendar = app.buttons["event.calendar.closure-event"].firstMatch
        reveal(calendar, app); calendar.tap()
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        XCTAssertTrue(system.alerts.firstMatch.waitForExistence(timeout: 10))
        capture(system, "sdk-calendar-permission-" + phase)
        let deny = system.alerts.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "Nicht", "Don’t")).firstMatch
        if phase == "deny" { XCTAssertTrue(deny.exists); deny.tap() }
        else {
            let allow = system.alerts.buttons.matching(NSPredicate(format: "NOT (label CONTAINS[c] %@ OR label CONTAINS[c] %@)", "Nicht", "Don’t")).firstMatch
            XCTAssertTrue(allow.exists); allow.tap()
        }
        let expected = phase == "deny" ? "Немає доступу до календаря" : "Додано в календар"
        XCTAssertTrue(app.alerts.staticTexts[expected].waitForExistence(timeout: 10))
        capture(app, "sdk-calendar-result-" + phase)
        app.alerts.buttons.firstMatch.tap()
        if phase == "allow" {
            calendar.tap(); XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
            capture(app, "sdk-calendar-already-added"); app.alerts.buttons.firstMatch.tap()
            let register = app.buttons["event.register.closure-event"].firstMatch
            reveal(register, app)
            let confirm = app.buttons["event.registration.confirm"].firstMatch
            if register.label.contains("Скасувати") {
                register.tap(); XCTAssertTrue(confirm.waitForExistence(timeout: 8)); confirm.tap()
                await fulfillment(of: [expectation(for: NSPredicate(format: "NOT (label CONTAINS %@)", "Скасувати"), evaluatedWith: register)], timeout: 10)
            }
            register.tap()
            XCTAssertTrue(confirm.waitForExistence(timeout: 8)); capture(app, "sdk-event-registration-confirm"); confirm.tap()
            await fulfillment(of: [expectation(for: NSPredicate(format: "label CONTAINS %@", "Скасувати"), evaluatedWith: register)], timeout: 10)
            _ = try await readDemoDocument("registrations/event_closure-event_closure-member")
            register.tap(); XCTAssertTrue(confirm.waitForExistence(timeout: 8)); confirm.tap()
            await fulfillment(of: [expectation(for: NSPredicate(format: "NOT (label CONTAINS %@)", "Скасувати"), evaluatedWith: register)], timeout: 10)
            _ = try await demoRequest("registrations/event_closure-event_closure-member", method: "GET", fields: nil, expectedStatus: 404)
        }
        app.terminate()
    }

    func testConnectedNewsAndEventExternalTargetsOpenSafariAndReturn() async throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" else { throw XCTSkip("Isolated demo required") }
        let url = "https://www.oesterreich.gv.at/"
        let action: [String: Any] = ["mapValue": ["fields": ["title": ["stringValue": "Audit external action"], "url": ["stringValue": url]]]]
        try await patchDemoDocument("news/closure-news", fields: ["externalAction": action])
        try await patchDemoDocument("events/closure-event", fields: ["externalAction": action, "requiresRegistration": ["booleanValue": false], "participationMode": ["stringValue": "externalTickets"]])
        let app = launchMember()
        for (tab, cardID, actionID) in [(0, "home.card.news-closure-news", "news.externalAction.closure-news"),
                                       (1, "event.card.closure-event", "event.externalAction.closure-event")] {
            app.tabBars.buttons.element(boundBy: tab).tap()
            let card = app.buttons[cardID].firstMatch
            reveal(card, app); card.tap()
            let link = app.descendants(matching: .any)[actionID].firstMatch
            reveal(link, app); link.tap()
            let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
            XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 15))
            let address = safari.textFields.firstMatch
            XCTAssertTrue(address.waitForExistence(timeout: 10))
            XCTAssertTrue(String(describing: address.value).contains("oesterreich.gv.at"))
            capture(safari, "sdk-external-safari-" + String(tab))
            app.activate()
            XCTAssertTrue(app.buttons["navigation.back"].firstMatch.waitForExistence(timeout: 10))
            capture(app, "sdk-external-return-" + String(tab))
            app.buttons["navigation.back"].firstMatch.tap()
        }
        app.terminate()
        try await patchDemoDocument("events/closure-event", fields: ["requiresRegistration": ["booleanValue": true], "participationMode": ["stringValue": "inAppRegistration"]])
    }

    func testConnectedEventAndOrganizationMapsTargetsAndReturn() async throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" else { throw XCTSkip("Isolated demo required") }
        for path in ["events/closure-event", "organizations/closure-org"] {
            try await patchDemoDocument(path, fields: ["latitude": ["doubleValue": 47.2682], "longitude": ["doubleValue": 11.3923]])
        }
        try await patchDemoDocument("organizations/closure-org", fields: ["address": ["stringValue": "Maria-Theresien-Straße 18"]])
        let organizationDocument = try await readDemoDocument("organizations/closure-org")
        let organizationFields = try XCTUnwrap(organizationDocument["fields"] as? [String: [String: Any]])
        let organizationName = try XCTUnwrap(organizationFields["name"]?["stringValue"] as? String)
        let app = launchMember()
        for (tab, cardID, mapID) in [(1, "event.card.closure-event", "event.map.closure-event"),
                                    (2, "organization.card.closure-org", "organization.contact.mappin.and.ellipse")] {
            app.tabBars.buttons.element(boundBy: tab).tap()
            let card = app.buttons[cardID].firstMatch; reveal(card, app); card.tap()
            if tab == 2 {
                let contacts = app.buttons["organization.section.contacts"].firstMatch
                reveal(contacts, app); contacts.tap()
            }
            let link = tab == 2 ? app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Локація:")).firstMatch
                : app.descendants(matching: .any)[mapID].firstMatch
            reveal(link, app); link.tap()
            let maps = XCUIApplication(bundleIdentifier: "com.apple.Maps")
            XCTAssertTrue(maps.wait(for: .runningForeground, timeout: 20))
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            for _ in 0..<6 {
                if let denial = ["Nicht erlauben", "Don’t Allow", "Don't Allow"].map({ springboard.alerts.buttons[$0].firstMatch }).first(where: { $0.exists }) { denial.tap(); continue }
                if let action = ["Continue", "Fortfahren", "Weiter", "Later", "Später", "Nicht jetzt"].map({ maps.buttons[$0].firstMatch }).first(where: { $0.exists && $0.isHittable }) { action.tap(); continue }
                break
            }
            let title = maps.staticTexts.matching(NSPredicate(format: "label == %@", tab == 2 ? organizationName : "Test hall")).firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 15))
            let coordinates = maps.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "47,26820", "11,39230")).firstMatch
            XCTAssertTrue(coordinates.waitForExistence(timeout: 10))
            capture(maps, "sdk-maps-target-" + String(tab))
            let tree = XCTAttachment(string: maps.debugDescription); tree.name = "maps-target-tree-" + String(tab); tree.lifetime = .keepAlways; add(tree)
            app.activate(); XCTAssertTrue(app.buttons["navigation.back"].firstMatch.waitForExistence(timeout: 10))
            app.buttons["navigation.back"].firstMatch.tap()
        }
        app.terminate()
    }

    func testMemberBookmarkThroughUIAndReopenAfterProcessRestart() throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" else {
            throw XCTSkip("Requires local audit emulator fixtures")
        }
        let app = launchMember()
        let card = app.buttons["home.card.news-closure-news"].firstMatch
        reveal(card, app); XCTAssertTrue(card.waitForExistence(timeout: 15)); card.tap()
        let bookmark = app.buttons["detail.header.action.bookmark"].firstMatch
        XCTAssertTrue(bookmark.waitForExistence(timeout: 10)); bookmark.tap()
        XCTAssertTrue(app.buttons["detail.header.action.bookmark.fill"].waitForExistence(timeout: 10))
        capture(app, "sdk-news-bookmarked")
        app.terminate(); app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))
        app.tabBars.buttons.element(boundBy: 4).tap()
        let saved = app.buttons["profile.savedContent"]
        reveal(saved, app); XCTAssertTrue(saved.exists); saved.tap()
        let row = app.buttons["saved.open.news-closure-news"]
        reveal(row, app); XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
        let remove = app.buttons["detail.header.action.bookmark.fill"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 10)); capture(app, "sdk-bookmark-after-restart"); remove.tap()
        XCTAssertTrue(bookmark.waitForExistence(timeout: 10))
    }

    func testActualPhotoPickerCropCancelAndApplyPreserveEditor() async throws {
        try await photoJourney(language: "uk", appearance: "light", large: false)
    }

    func testActualPhotoPickerGermanDarkAtAccessibilitySize() async throws {
        try await photoJourney(language: "de", appearance: "dark", large: true)
    }

    func testConnectedPhotoSelectionUploadSaveAndProcessReopen() async throws {
        try await photoJourney(language: "uk", appearance: "light", large: false, save: true)
    }

    private func photoJourney(language: String, appearance: String, large: Bool, save: Bool = false) async throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" else {
            throw XCTSkip("Requires local audit emulator and simulator photo fixture")
        }
        let app = launchMember(language: language, appearance: appearance, large: large)
        app.tabBars.buttons.element(boundBy: 4).tap()
        let edit = app.buttons["profile.edit.open"]
        reveal(edit, app); XCTAssertTrue(edit.exists); edit.tap()
        let picker = app.buttons["profile.edit.photo"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10)); picker.tap()
        let photo = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 10))
        capture(app, "sdk-profile-system-photo-picker")
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let apply = app.buttons["imageCrop.apply"]
        XCTAssertTrue(apply.waitForExistence(timeout: 15))
        let zoomIn = app.buttons["imageCrop.control.plus.magnifyingglass"]
        reveal(zoomIn, app); XCTAssertTrue(zoomIn.isHittable); zoomIn.tap()
        let zoomOut = app.buttons["imageCrop.control.minus.magnifyingglass"]
        XCTAssertTrue(zoomOut.isEnabled); zoomOut.tap()
        for symbol in ["arrow.left", "arrow.right", "arrow.up", "arrow.down", "minus.magnifyingglass", "plus.magnifyingglass"] {
            let control = app.buttons["imageCrop.control." + symbol]
            reveal(control, app); XCTAssertTrue(control.isHittable)
            XCTAssertGreaterThanOrEqual(control.frame.width, 44)
            XCTAssertGreaterThanOrEqual(control.frame.height, 44)
        }
        capture(app, "sdk-profile-crop-controls-" + language + "-" + appearance)
        app.buttons["imageCrop.cancel"].tap()
        XCTAssertTrue(apply.waitForNonExistence(timeout: 5)); XCTAssertTrue(picker.exists)
        picker.tap(); XCTAssertTrue(photo.waitForExistence(timeout: 10)); photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(apply.waitForExistence(timeout: 15)); app.buttons["imageCrop.reset"].tap(); apply.tap()
        XCTAssertTrue(apply.waitForNonExistence(timeout: 15))
        XCTAssertTrue(app.buttons["profile.edit.save"].isEnabled)
        capture(app, "sdk-profile-cropped-preview-" + language + "-" + appearance)
        if save {
            app.buttons["profile.edit.save"].tap()
            XCTAssertTrue(picker.waitForNonExistence(timeout: 30))
            let document = try await readDemoDocument("users/closure-member")
            let fields = try XCTUnwrap(document["fields"] as? [String: [String: Any]])
            let url = try XCTUnwrap(fields["avatarURL"]?["stringValue"] as? String)
            var local = try XCTUnwrap(URLComponents(string: url))
            XCTAssertEqual(local.host, "firebasestorage.googleapis.com")
            XCTAssertTrue(local.percentEncodedPath.contains("profileImages%2Fclosure-member%2Favatar.jpg"))
            local.scheme = "http"; local.host = "127.0.0.1"; local.port = 29199
            let (data, response) = try await URLSession.shared.data(from: try XCTUnwrap(local.url))
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            XCTAssertEqual(data.prefix(2), Data([0xff, 0xd8]))
            app.terminate(); app.launch()
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))
            app.tabBars.buttons.element(boundBy: 4).tap()
            XCTAssertTrue(app.buttons["profile.edit.open"].waitForExistence(timeout: 10))
            capture(app, "sdk-profile-photo-after-process-restart")
        }
        // Both branches are pinned to the isolated demo environment.
        app.terminate()
    }


    func testConnectedDirectoryPublishReopenConflictAndLiveRevocation() async throws {
        try await directoryJourney(language: "uk", appearance: "light")
    }

    func testConnectedDirectoryGermanDarkConflictAndRevocation() async throws {
        try await directoryJourney(language: "de", appearance: "dark")
    }

    private func directoryJourney(language: String, appearance: String) async throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" else {
            throw XCTSkip("Requires isolated emulator fixtures")
        }
        try await patchDemoDocument("directoryEditors/closure-editor", fields: ["enabled": ["booleanValue": true]])
        let app = launchMember(language: language, appearance: appearance, account: "editor")
        app.tabBars.buttons.element(boundBy: 3).tap()
        let manage = app.buttons["directory.manage"].firstMatch
        reveal(manage, app); XCTAssertTrue(manage.waitForExistence(timeout: 10)); manage.tap()
        let category = app.buttons["directory.category.manage.first-steps"].firstMatch
        XCTAssertTrue(category.waitForExistence(timeout: 10)); reveal(category, app); category.tap()
        let name = app.textFields["directory.field.categoryTitle.uk"].firstMatch
        reveal(name, app); XCTAssertTrue(name.exists)
        let suffix = " " + String(UUID().uuidString.prefix(6))
        let original = try XCTUnwrap(name.value as? String)
        name.tap(); name.typeText(suffix + "\n")
        let edited = try XCTUnwrap(name.value as? String)
        XCTAssertNotEqual(edited, original)
        XCTAssertTrue(edited.contains(suffix.trimmingCharacters(in: .whitespaces)))
        let publish = app.buttons["directory.category.publish"].firstMatch
        XCTAssertTrue(publish.isEnabled); publish.tap()
        let confirm = app.buttons["directory.category.confirmPublish"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 20))
        let stored = try await readDemoDocument("directoryCategories/first-steps")
        let fields = try XCTUnwrap(stored["fields"] as? [String: [String: Any]])
        let revision = try XCTUnwrap(fields["revision"]?["integerValue"] as? String)
        let payload = try XCTUnwrap(fields["payload"]?["stringValue"] as? String)
        XCTAssertTrue(payload.contains(edited))
        reveal(category, app); category.tap(); reveal(name, app)
        XCTAssertEqual(name.value as? String, edited)
        capture(app, "sdk-directory-published-reopened")
        name.tap(); name.typeText(" conflict\n")
        // Simulate another editor committing while this UI retains its original revision.
        let nextRevision = try XCTUnwrap(Int(revision)).advanced(by: 1)
        try await patchDemoDocument("directoryCategories/first-steps", fields: ["revision": ["integerValue": String(nextRevision)]])
        publish.tap(); XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        let conflict = app.alerts.firstMatch
        XCTAssertTrue(conflict.waitForExistence(timeout: 15))
        XCTAssertTrue(conflict.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", language == "uk" ? "іншому пристрої" : "anderen Gerät")).firstMatch.exists)
        capture(app, "sdk-directory-revision-conflict-" + language + "-" + appearance)
        conflict.buttons.firstMatch.tap()
        let afterConflict = try await readDemoDocument("directoryCategories/first-steps")
        let afterFields = try XCTUnwrap(afterConflict["fields"] as? [String: [String: Any]])
        XCTAssertEqual(afterFields["payload"]?["stringValue"] as? String, payload)
        try await patchDemoDocument("directoryEditors/closure-editor", fields: ["enabled": ["booleanValue": false]])
        let unavailable = app.buttons["directory.accessUnavailable.back"].firstMatch
        XCTAssertTrue(unavailable.waitForExistence(timeout: 15))
        XCTAssertFalse(publish.exists)
        capture(app, "sdk-directory-access-revoked-open-editor-" + language + "-" + appearance)
        unavailable.tap()
        // The management route is restricted too, with an explicit safe return.
        XCTAssertTrue(unavailable.waitForExistence(timeout: 8)); unavailable.tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(manage.exists)
        try await patchDemoDocument("directoryEditors/closure-editor", fields: ["enabled": ["booleanValue": true]])
        app.terminate()
    }

    func testConnectedOrganizationPersonalRoutesRestartAndAccountIsolation() async throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" else {
            throw XCTSkip("Requires isolated emulator fixtures")
        }
        let app = launchMember()
        app.tabBars.buttons.element(boundBy: 2).tap()
        let card = app.buttons["organization.card.closure-org"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15)); reveal(card, app); card.tap()
        let bookmark = app.buttons["detail.header.action.bookmark"].firstMatch
        XCTAssertTrue(bookmark.waitForExistence(timeout: 10)); bookmark.tap()
        XCTAssertTrue(app.buttons["detail.header.action.bookmark.fill"].waitForExistence(timeout: 10))
        let follow = app.buttons["organization.subscribe.closure-org"].firstMatch
        reveal(follow, app)
        if follow.isSelected {
            follow.tap()
            let unfollow = app.buttons["organization.subscription.confirm"].firstMatch
            XCTAssertTrue(unfollow.waitForExistence(timeout: 5)); unfollow.tap()
            let removed = expectation(for: NSPredicate(format: "selected == false"), evaluatedWith: follow)
            await fulfillment(of: [removed], timeout: 15)
        }
        follow.tap()
        let selected = NSPredicate(format: "selected == true")
        let followed = expectation(for: selected, evaluatedWith: follow)
        await fulfillment(of: [followed], timeout: 15)
        capture(app, "sdk-organization-saved-followed")
        let bookmarkPath = "users/closure-member/organizationBookmarks/closure-org"
        let followPath = "likes/organization_follow_closure-org_closure-member"
        _ = try await readDemoDocument(bookmarkPath)
        let subscription = try await readDemoDocument(followPath)
        let followFields = try XCTUnwrap(subscription["fields"] as? [String: [String: Any]])
        XCTAssertEqual(followFields["userId"]?["stringValue"] as? String, "closure-member")
        app.terminate(); app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))
        for (route, row) in [("savedContent", "saved.open.organization-closure-org"),
                             ("followedOrganizations", "subscriptions.open.closure-org"),
                             ("recentViews", "recentViews.open.organization_closure-org")] {
            app.tabBars.buttons.element(boundBy: 4).tap()
            let entry = app.buttons["profile." + route]
            reveal(entry, app); entry.tap()
            let target = app.buttons[row].firstMatch
            XCTAssertTrue(target.waitForExistence(timeout: 15)); reveal(target, app)
            capture(app, "sdk-personal-after-restart-" + route)
            app.buttons["navigation.back"].firstMatch.tap()
        }
        app.terminate()
        let other = launchMember(account: "other")
        other.tabBars.buttons.element(boundBy: 4).tap()
        for (route, row) in [("savedContent", "saved.open.organization-closure-org"),
                             ("followedOrganizations", "subscriptions.open.closure-org")] {
            let entry = other.buttons["profile." + route]
            reveal(entry, other); entry.tap()
            let search = other.textFields[route == "savedContent" ? "saved.search" : "subscriptions.search"]
            XCTAssertTrue(search.waitForExistence(timeout: 10))
            XCTAssertFalse(other.buttons[row].exists)
            capture(other, "sdk-other-account-" + route)
            other.buttons["navigation.back"].firstMatch.tap()
        }
        other.terminate()
        let member = launchMember()
        member.tabBars.buttons.element(boundBy: 4).tap()
        let saved = member.buttons["profile.savedContent"]
        reveal(saved, member); saved.tap()
        let savedOrg = member.buttons["saved.open.organization-closure-org"].firstMatch
        XCTAssertTrue(savedOrg.waitForExistence(timeout: 15)); reveal(savedOrg, member); savedOrg.tap()
        let remove = member.buttons["detail.header.action.bookmark.fill"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 10)); remove.tap()
        XCTAssertTrue(member.buttons["detail.header.action.bookmark"].waitForExistence(timeout: 10))
        capture(member, "sdk-member-data-restored-after-account-switch")
        let unfollow = member.buttons["organization.subscribe.closure-org"].firstMatch
        reveal(unfollow, member); XCTAssertTrue(unfollow.isSelected); unfollow.tap()
        let confirmRemoval = member.buttons["organization.subscription.confirm"].firstMatch
        XCTAssertTrue(confirmRemoval.waitForExistence(timeout: 5)); confirmRemoval.tap()
        let removed = expectation(for: NSPredicate(format: "selected == false"), evaluatedWith: unfollow)
        await fulfillment(of: [removed], timeout: 15)
        member.terminate()
    }

    func testConnectedHiddenUserSearchCancelUnblockAndReopen() async throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" else {
            throw XCTSkip("Requires isolated emulator fixtures")
        }
        let path = "users/closure-member/blockedUsers/closure-other"
        try await patchDemoDocument(path, fields: ["targetUserId": ["stringValue": "closure-other"],
            "displayName": ["stringValue": "Closure Other"], "updatedAt": ["timestampValue": "2026-10-25T00:00:00Z"]])
        let app = launchMember(language: "de", appearance: "dark", large: true)
        app.tabBars.buttons.element(boundBy: 4).tap()
        let settings = app.buttons["profile.settings.open"]
        reveal(settings, app); settings.tap()
        let hidden = app.buttons["profile.settings.blockedUsers"]
        reveal(hidden, app); XCTAssertTrue(hidden.exists); hidden.tap()
        let unblock = app.buttons["blockedUsers.unblock.closure-other"].firstMatch
        reveal(unblock, app); XCTAssertTrue(unblock.waitForExistence(timeout: 15))
        let search = app.textFields["blockedUsers.search"].firstMatch
        search.tap(); search.typeText("  Closure  \n")
        XCTAssertTrue(unblock.exists); reveal(unblock, app); unblock.tap()
        let confirm = app.buttons["blockedUsers.confirmUnblock"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        capture(app, "sdk-hidden-user-unblock-confirm-de-dark-AX")
        app.alerts.buttons["blockedUsers.cancelUnblock"].firstMatch.tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5)); XCTAssertTrue(unblock.exists)
        _ = try await readDemoDocument(path)
        unblock.tap(); XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(unblock.waitForNonExistence(timeout: 15))
        _ = try await demoRequest(path, method: "GET", fields: nil, expectedStatus: 404)
        capture(app, "sdk-hidden-user-empty-after-unblock-de-dark-AX")
        app.buttons["navigation.back"].firstMatch.tap()
        reveal(hidden, app); hidden.tap()
        XCTAssertFalse(unblock.exists)
        app.terminate()
    }

    func testConnectedDirectoryOutlineSymbolGroupVisibilityOrderingAndDeletion() async throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" else {
            throw XCTSkip("Requires isolated emulator fixtures")
        }
        try await prepareDirectoryUIFixture()
        let app = launchMember(account: "editor")
        app.tabBars.buttons.element(boundBy: 3).tap()
        let manage = app.buttons["directory.manage"].firstMatch
        reveal(manage, app); manage.tap()
        let category = app.buttons["directory.category.manage." + directoryUIFixtureID].firstMatch
        XCTAssertTrue(category.waitForExistence(timeout: 10)); reveal(category, app); category.tap()
        let symbol = app.buttons["directory.category.symbol"].firstMatch
        reveal(symbol, app); symbol.tap()
        let search = app.textFields["directory.symbol.search"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("Інформація\n")
        let selected = app.buttons["directory.symbol.info.circle.fill"].firstMatch
        XCTAssertTrue(selected.waitForExistence(timeout: 5)); selected.tap()
        let move = app.buttons["directory.group.move.group-one"].firstMatch
        reveal(move, app); move.tap()
        let down = app.buttons["Опустити нижче"].firstMatch
        XCTAssertTrue(down.waitForExistence(timeout: 5)); down.tap()
        let group = app.buttons["directory.group.edit.group-one"].firstMatch
        reveal(group, app); group.tap()
        let hidden = app.switches["directory.group.hidden"].firstMatch
        reveal(hidden, app); XCTAssertTrue(hidden.isHittable)
        hidden.coordinate(withNormalizedOffset: .init(dx: 0.94, dy: 0.5)).tap()
        capture(app, "sdk-directory-group-hidden")
        app.navigationBars.buttons.firstMatch.tap()
        let add = app.buttons["Додати підкатегорію"].firstMatch
        reveal(add, app); add.tap()
        for locale in ["uk", "de"] {
            let field = app.textFields["directory.field.groupTitle." + locale].firstMatch
            reveal(field, app); XCTAssertTrue(field.exists); field.tap(); field.typeText(locale == "uk" ? "Нова група\n" : "Neue Gruppe\n")
        }
        capture(app, "sdk-directory-new-group-ready")
        let confirmAdd = app.buttons["Додати"].firstMatch
        XCTAssertTrue(confirmAdd.isEnabled); confirmAdd.tap()
        let placement = app.buttons["directory.category.placement"].firstMatch
        reveal(placement, app, preferUpwardScroll: true); placement.tap()
        let support = app.buttons["Підтримка та участь"].firstMatch
        XCTAssertTrue(support.waitForExistence(timeout: 5)); support.tap()
        let publish = app.buttons["directory.category.publish"].firstMatch
        XCTAssertTrue(publish.isEnabled); publish.tap()
        let confirm = app.buttons["directory.category.confirmPublish"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(publish.waitForNonExistence(timeout: 15))
        let data = try await directoryPayload()
        XCTAssertEqual(data["symbol"] as? String, "info.circle.fill")
        XCTAssertEqual(data["placement"] as? String, "support")
        let groups = try XCTUnwrap(data["groups"] as? [[String: Any]])
        XCTAssertEqual(groups.count, 3)
        let one = try XCTUnwrap(groups.first { $0["id"] as? String == "group-one" })
        let two = try XCTUnwrap(groups.first { $0["id"] as? String == "group-two" })
        XCTAssertEqual(one["isHidden"] as? Bool, true)
        XCTAssertGreaterThan(try XCTUnwrap(one["order"] as? Int), try XCTUnwrap(two["order"] as? Int))
        XCTAssertTrue(groups.contains { ($0["title"] as? [String: String])?["german"] == "Neue Gruppe" })
        // Reopen the actual draft from the server, then delete the disposable category through UI.
        reveal(category, app); category.tap()
        let deletion = app.buttons["directory.category.delete"].firstMatch
        reveal(deletion, app); deletion.tap()
        let confirmDelete = app.buttons["directory.category.confirmDelete"].firstMatch
        XCTAssertTrue(confirmDelete.waitForExistence(timeout: 5)); capture(app, "sdk-directory-delete-category-dialog"); confirmDelete.tap()
        XCTAssertTrue(deletion.waitForNonExistence(timeout: 15))
        let document = try await readDemoDocument("directoryCategories/" + directoryUIFixtureID)
        let fields = try XCTUnwrap(document["fields"] as? [String: [String: Any]])
        XCTAssertEqual(fields["isDeleted"]?["booleanValue"] as? Bool, true)
        XCTAssertEqual(fields["revision"]?["integerValue"] as? String, "3")
        app.terminate()
    }

    func testConnectedDirectoryContactArticleMoveAndPublicRead() async throws {
        try await directoryContactJourney(language: "uk", appearance: "light", large: false)
    }

    func testConnectedDirectoryContactGermanDarkAccessibility() async throws {
        try await directoryContactJourney(language: "de", appearance: "dark", large: true)
    }

    private func directoryContactJourney(language: String, appearance: String, large: Bool) async throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" else {
            throw XCTSkip("Requires isolated emulator fixtures")
        }
        try await prepareDirectoryUIFixture()
        let app = launchMember(language: language, appearance: appearance, large: large, account: "editor")
        app.tabBars.buttons.element(boundBy: 3).tap()
        let manage = app.buttons["directory.manage"].firstMatch
        reveal(manage, app); manage.tap()
        let category = app.buttons["directory.category.manage." + directoryUIFixtureID].firstMatch
        reveal(category, app); category.tap()
        let article = app.buttons["directory.topic.edit.audit-topic-one"].firstMatch
        reveal(article, app); article.tap()
        let group = app.buttons["directory.topic.group"].firstMatch
        reveal(group, app); group.tap()
        let second = app.buttons[language == "uk" ? "Група two" : "Gruppe two"].firstMatch
        XCTAssertTrue(second.waitForExistence(timeout: 5)); second.tap()
        let section = app.buttons["directory.section.edit.audit-section"].firstMatch
        reveal(section, app); section.tap()
        let add = app.buttons["directory.contact.add"].firstMatch
        reveal(add, app); add.tap()
        let number = app.textFields["directory.contact.number.0"].firstMatch
        reveal(number, app); number.tap(); number.typeText("+431000000000")
        for (field, value) in [("contactTitle.uk", "Тестовий контакт"), ("contactTitle.de", "Testkontakt"),
                               ("contactDetail.uk", "Опис контакту"), ("contactDetail.de", "Kontaktbeschreibung")] {
            let input = app.textFields["directory.field." + field].firstMatch
            reveal(input, app); input.tap(); input.typeText(value + "\n")
        }
        // Delete a second row while retaining the populated one. Cached bindings
        // for the removed index must not crash or overwrite the surviving row.
        reveal(add, app); add.tap()
        let removeSecond = app.buttons["directory.contact.remove.1"].firstMatch
        reveal(removeSecond, app); removeSecond.tap()
        let remainingNumber = app.textFields["directory.contact.number.0"].firstMatch
        reveal(remainingNumber, app); XCTAssertEqual(remainingNumber.value as? String, "+431000000000")
        capture(app, "sdk-directory-contact-ready-after-second-row-removal-" + language + "-" + appearance)
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        let publish = app.buttons["directory.category.publish"].firstMatch
        XCTAssertTrue(publish.isEnabled); publish.tap()
        let confirm = app.buttons["directory.category.confirmPublish"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(category.waitForExistence(timeout: 15))
        let payload = try await directoryPayload()
        let topics = try XCTUnwrap(payload["topics"] as? [[String: Any]])
        let topic = try XCTUnwrap(topics.first { $0["id"] as? String == "audit-topic-one" })
        XCTAssertEqual(topic["groupID"] as? String, "group-two")
        let sections = try XCTUnwrap(topic["sections"] as? [[String: Any]])
        let contacts = try XCTUnwrap(sections.first?["contacts"] as? [[String: Any]])
        XCTAssertEqual(contacts.count, 1)
        XCTAssertEqual(contacts.first?["number"] as? String, "+431000000000")
        XCTAssertEqual((contacts.first?["title"] as? [String: String])?["german"], "Testkontakt")
        app.terminate()
        let member = launchMember()
        member.tabBars.buttons.element(boundBy: 3).tap()
        let publicCategory = member.buttons["directory.category." + directoryUIFixtureID].firstMatch
        reveal(publicCategory, member); publicCategory.tap()
        let publicArticle = member.buttons["directory.topic.audit-topic-one"].firstMatch
        reveal(publicArticle, member); publicArticle.tap()
        let contact = member.staticTexts["Тестовий контакт"].firstMatch
        reveal(contact, member); XCTAssertTrue(contact.exists)
        capture(member, "sdk-directory-public-contact-member")
        XCTAssertFalse(member.buttons["directory.category.publish"].exists)
        // Observe the destination data and control without placing a real call.
        member.terminate()
    }

    func testConnectedDirectoryCreatesBilingualCategoryFromFormAndDeletesIt() async throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" else {
            throw XCTSkip("Requires isolated emulator fixtures")
        }
        let app = launchMember(account: "editor")
        app.tabBars.buttons.element(boundBy: 3).tap()
        let manage = app.buttons["directory.manage"].firstMatch
        reveal(manage, app); manage.tap()
        let create = app.buttons["directory.category.add.support"].firstMatch
        reveal(create, app); create.tap()
        let unique = String(UUID().uuidString.prefix(6))
        let ukrainianTitle = "Перевірка " + unique
        for locale in ["uk", "de"] {
            if locale == "de" {
                let language = app.buttons["Deutsch"].firstMatch
                reveal(language, app, preferUpwardScroll: true); language.tap()
            }
            for (field, text, multiline) in [
                ("categoryTitle", locale == "uk" ? ukrainianTitle : "Prüfung " + unique, false),
                ("categorySummary", locale == "uk" ? "Локальний тест" : "Lokaler Test", false),
                ("articleTitle", locale == "uk" ? "Тестова стаття" : "Testbeitrag", false),
                ("articleSummary", locale == "uk" ? "Вступ статті" : "Einleitung", true),
                ("sectionTitle", locale == "uk" ? "Тестовий блок" : "Testabschnitt", false),
                ("sectionBody", locale == "uk" ? "Тестові кроки для перевірки" : "Testschritte für die Prüfung", true)] {
                let id = "directory.field." + field + "." + locale
                let input = multiline ? app.textViews[id].firstMatch : app.textFields[id].firstMatch
                reveal(input, app); input.tap(); input.typeText(text)
                if !multiline { input.typeText("\n") }
            }
        }
        let sourceName = app.textFields["directory.source.name"].firstMatch
        reveal(sourceName, app); sourceName.tap(); sourceName.typeText("Audit source\n")
        let sourceURL = app.textFields["directory.source.url"].firstMatch
        reveal(sourceURL, app); sourceURL.tap(); sourceURL.typeText("https://www.oesterreich.gv.at/\n")
        capture(app, "sdk-directory-new-bilingual-category-ready")
        let publish = app.buttons["directory.category.publish"].firstMatch
        XCTAssertTrue(publish.isEnabled); publish.tap()
        let confirm = app.buttons["directory.category.confirmPublish"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(sourceURL.waitForNonExistence(timeout: 20))
        let collection = try await readDemoDocument("directoryCategories")
        let documents = try XCTUnwrap(collection["documents"] as? [[String: Any]])
        let created = try XCTUnwrap(documents.first { doc in
            let fields = doc["fields"] as? [String: [String: Any]]
            return (fields?["payload"]?["stringValue"] as? String)?.contains(ukrainianTitle) == true
        })
        let fields = try XCTUnwrap(created["fields"] as? [String: [String: Any]])
        let id = try XCTUnwrap(fields["id"]?["stringValue"] as? String)
        XCTAssertTrue(id.hasPrefix("custom-")); XCTAssertEqual(fields["revision"]?["integerValue"] as? String, "1")
        let payload = try XCTUnwrap(fields["payload"]?["stringValue"] as? String)
        let categoryData = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any])
        XCTAssertEqual((categoryData["title"] as? [String: String])?["german"], "Prüfung " + unique)
        XCTAssertEqual(categoryData["placement"] as? String, "support")
        let category = app.buttons["directory.category.manage." + id].firstMatch
        reveal(category, app); category.tap()
        let title = app.textFields["directory.field.categoryTitle.uk"].firstMatch
        reveal(title, app); XCTAssertEqual(title.value as? String, ukrainianTitle)
        capture(app, "sdk-directory-new-category-reopened")
        let deletion = app.buttons["directory.category.delete"].firstMatch
        reveal(deletion, app); deletion.tap()
        let remove = app.buttons["directory.category.confirmDelete"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 5)); remove.tap()
        XCTAssertTrue(deletion.waitForNonExistence(timeout: 15))
        let afterDelete = try await readDemoDocument("directoryCategories")
        let tombstones = try XCTUnwrap(afterDelete["documents"] as? [[String: Any]])
        let deleted = try XCTUnwrap(tombstones.first { doc in
            let fields = doc["fields"] as? [String: [String: Any]]
            return fields?["id"]?["stringValue"] as? String == id
        })
        let deletedFields = try XCTUnwrap(deleted["fields"] as? [String: [String: Any]])
        XCTAssertEqual(deletedFields["isDeleted"]?["booleanValue"] as? Bool, true)
        XCTAssertEqual(deletedFields["revision"]?["integerValue"] as? String, "2")
        app.terminate()
    }

    private func directoryPayload() async throws -> [String: Any] {
        let document = try await readDemoDocument("directoryCategories/" + directoryUIFixtureID)
        let fields = try XCTUnwrap(document["fields"] as? [String: [String: Any]])
        let payload = try XCTUnwrap(fields["payload"]?["stringValue"] as? String)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any])
    }

    private func prepareDirectoryUIFixture() async throws {
        let document = try await readDemoDocument("directoryCategories/first-steps")
        let fields = try XCTUnwrap(document["fields"] as? [String: [String: Any]])
        let payload = try XCTUnwrap(fields["payload"]?["stringValue"] as? String)
        var category = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any])
        category["id"] = directoryUIFixtureID; category["order"] = 0; category["placement"] = "start"; category["isHidden"] = false
        category["title"] = ["ukrainian": "Локальна перевірка", "german": "Lokale Prüfung"]
        category["groups"] = ["one", "two"].enumerated().map { rank, id in
            ["id": "group-" + id, "order": rank, "isHidden": false,
             "title": ["ukrainian": "Група " + id, "german": "Gruppe " + id]] as [String: Any]
        }
        let base = try XCTUnwrap((category["topics"] as? [[String: Any]])?.first)
        category["topics"] = try ["one", "two"].enumerated().map { rank, id in
            var topic = base
            topic["id"] = "audit-topic-" + id; topic["groupID"] = "group-" + id
            topic["order"] = rank; topic["isHidden"] = false
            topic["title"] = ["ukrainian": "Стаття " + id, "german": "Beitrag " + id]
            var section = try XCTUnwrap((base["sections"] as? [[String: Any]])?.first)
            section["id"] = "audit-section"; section["contacts"] = []
            topic["sections"] = [section]; topic["regionalSections"] = [String: Any]()
            return topic
        }
        let data = try JSONSerialization.data(withJSONObject: category, options: [.sortedKeys])
        try await patchDemoDocument("directoryCategories/" + directoryUIFixtureID, fields: ["id": ["stringValue": directoryUIFixtureID],
            "payload": ["stringValue": String(decoding: data, as: UTF8.self)], "revision": ["integerValue": "1"],
            "isDeleted": ["booleanValue": false], "updatedAt": ["timestampValue": ISO8601DateFormatter().string(from: .now)]])
    }

    private func readDemoDocument(_ path: String) async throws -> [String: Any] {
        try await demoRequest(path, method: "GET", fields: nil)
    }
    private func patchDemoDocument(_ path: String, fields: [String: [String: Any]]) async throws {
        _ = try await demoRequest(path, method: "PATCH", fields: fields)
    }
    private func demoRequest(_ path: String, method: String, fields: [String: [String: Any]]?, expectedStatus: Int = 200) async throws -> [String: Any] {
        // Fixed loopback + demo project. This helper cannot address production.
        guard ["users/closure-member", "directoryCategories", "directoryEditors/closure-editor", "directoryCategories/first-steps", "directoryCategories/" + directoryUIFixtureID,
               "users/closure-member/organizationBookmarks/closure-org",
               "likes/organization_follow_closure-org_closure-member",
               "users/closure-member/blockedUsers/closure-other", "users/closure-editor/blockedUsers/closure-other",
               "organizations/closure-org", "registrations/event_closure-event_closure-member", "organizations/closure-org/photos", "news/closure-news", "events/closure-event", "publicProfiles/closure-other", "likes/organization_follow_closure-org_closure-other", "organizations/closure-org/comments/closure-delete",
               "organizations/closure-org/comments/closure-report", "dsaCases", "serverConfiguration/organizationAccess"].contains(path)
                || ownedPhotoIDs.contains(where: { path == "organizations/closure-org/photos/" + $0 })
                || ownedDisposableUserIDs.contains(where: { path == "users/" + $0 })
                || (method == "GET" && ownedDeletionOperationIDs.contains(where: { path == "accountDeletionOperations/" + $0 }))
                || ownedRequestDocumentPaths.contains(path)
                || (method == "GET" && ["organizations", "users/closure-member/notificationInbox"].contains(path)) else {
            throw NSError(domain: "AuditFixture", code: 1)
        }
        if ["directoryCategories", "users/closure-member", "dsaCases", "organizations/closure-org/photos"].contains(path) {
            guard method == "GET", fields == nil else { throw NSError(domain: "AuditFixture", code: 2) }
        }
        var components = URLComponents(string: "http://127.0.0.1:28080/v1/projects/demo-uac-release-audit/databases/(default)/documents/" + path)!
        if let fields { components.queryItems = fields.keys.sorted().map { URLQueryItem(name: "updateMask.fieldPaths", value: $0) } }
        var request = URLRequest(url: components.url!); request.httpMethod = method
        request.setValue("Bearer owner", forHTTPHeaderField: "Authorization")
        if let fields {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["fields": fields])
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, expectedStatus)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testConnectedModerationNoticeOpensTheExactReturnedMaterial() async throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" else { throw XCTSkip("Fixed isolated demo required") }
        let noticeID = try await moderationNoticeID(source: "news:mod-audit-news", status: "needsRevision")
        let app = launchMember(account: "member")
        app.tabBars.buttons.element(boundBy: 4).tap()
        let inbox = app.buttons["profile.notifications.open"].firstMatch
        revealModeration(inbox, app); inbox.tap()
        let notice = app.buttons["notificationInbox.open." + noticeID].firstMatch
        revealModeration(notice, app); notice.tap()
        let destination = app.buttons["notificationDetail.openDestination"].firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout: 10)); capture(app, "sdk-moderation-notice-sheet-before-navigation"); destination.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "content.review.language").firstMatch.waitForExistence(timeout: 20), app.debugDescription)
        let edit = app.buttons["content.review.edit"].firstMatch
        revealModeration(edit, app); capture(app, "sdk-moderation-notice-exact-author-material")
        XCTAssertFalse(app.buttons["content.review.confirm"].exists)
    }

    func testConnectedModerationReturnNotificationCorrectionAndPublication() async throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" else { throw XCTSkip("Fixed isolated demo required") }
        let noticeWindowStart = Date()
        let path = "news/mod-audit-news"
        ownedRequestDocumentPaths.insert(path)
        let before = try await readDemoDocument(path)
        let beforeFields = try XCTUnwrap(before["fields"] as? [String: [String: Any]])
        let app = launchMember(account: "owner", moderationReviewer: true)
        app.tabBars.buttons.element(boundBy: 4).tap()
        let moderation = app.buttons["profile.moderation"].firstMatch
        revealModeration(moderation, app); moderation.tap()
        let row = app.buttons["content.moderation.open.mod-audit-news"].firstMatch
        revealModeration(row, app); row.tap()
        let revise = app.buttons["content.review.choice.needsRevision"].firstMatch
        revealModeration(revise, app); revise.tap()
        let reason = app.textFields["content.review.reason"].firstMatch
        revealModeration(reason, app); reason.tap(); reason.typeText("Уточніть заголовок перед публікацією. Контрольована перевірка.")
        if app.keyboards.firstMatch.exists { app.coordinate(withNormalizedOffset: .init(dx: 0.96, dy: 0.12)).tap() }
        let confirm = app.buttons["content.review.confirm"].firstMatch
        XCTAssertTrue(confirm.isEnabled); confirm.tap()
        let execute = app.alerts.buttons["content.review.execute"].firstMatch
        XCTAssertTrue(execute.waitForExistence(timeout: 5)); capture(app, "sdk-moderation-revision-confirmation"); execute.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 20))
        let returned = try await readDemoDocument(path)
        XCTAssertEqual((returned["fields"] as? [String: [String: Any]])?["moderationStatus"]?["stringValue"] as? String, "needsRevision")
        app.terminate()

        let noticeID = try await moderationNoticeID(source: "news:mod-audit-news", status: "needsRevision", after: noticeWindowStart)
        let author = launchMember(account: "member")
        author.tabBars.buttons.element(boundBy: 4).tap()
        let inbox = author.buttons["profile.notifications.open"].firstMatch
        revealModeration(inbox, author); inbox.tap()
        let notice = author.buttons.matching(NSPredicate(format: "identifier == %@", "notificationInbox.open." + noticeID)).firstMatch
        revealModeration(notice, author); notice.tap()
        let destination = author.buttons["notificationDetail.openDestination"].firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout: 10)); capture(author, "sdk-moderation-exact-recipient-notice"); destination.tap()
        let edit = author.buttons["content.review.edit"].firstMatch
        revealModeration(edit, author); capture(author, "sdk-moderation-author-returned-material"); edit.tap()
        let title = author.textFields["editor.news.title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 15)); title.tap(); title.typeText(" виправлено")
        let correctedTitle = try XCTUnwrap(title.value as? String)
        if author.keyboards.firstMatch.exists { author.coordinate(withNormalizedOffset: .init(dx: 0.96, dy: 0.12)).tap() }
        let next = author.buttons["editor.news.next"].firstMatch
        revealModeration(next, author); next.tap(); revealModeration(next, author); next.tap()
        let save = author.buttons["editor.news.submit"].firstMatch
        revealModeration(save, author); XCTAssertTrue(save.isEnabled); capture(author, "sdk-moderation-corrected-publication-preview"); save.tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 25))
        let corrected = try await readDemoDocument(path)
        let fields = try XCTUnwrap(corrected["fields"] as? [String: [String: Any]])
        XCTAssertEqual(fields["title"]?["stringValue"] as? String, correctedTitle)
        XCTAssertEqual(fields["moderationStatus"]?["stringValue"] as? String, "pendingReview")
        XCTAssertEqual(fields["moderationReason"]?["stringValue"] as? String, "")
        for key in ["imageURL", "category", "body", "summary", "subtitle", "organizationId", "organizationName", "authorId", "authorName", "sourceName", "sourceURL", "federalState", "regionScope", "sourceType", "additionalCategories", "tags", "externalAction", "mediaMetadata", "likeCount", "viewCount"] {
            XCTAssertEqual(fields[key] as NSDictionary?, beforeFields[key] as NSDictionary?, "Unedited field must survive correction: " + key)
        }
        let oldLanguages = ((beforeFields["localizations"]?["mapValue"] as? [String: Any])?["fields"] as? [String: [String: Any]]) ?? [:]
        let newLanguages = ((fields["localizations"]?["mapValue"] as? [String: Any])?["fields"] as? [String: [String: Any]]) ?? [:]
        XCTAssertEqual(newLanguages["de"] as NSDictionary?, oldLanguages["de"] as NSDictionary?, "Unedited German translation must survive")
        let oldUkrainian = (oldLanguages["uk"]?["mapValue"] as? [String: Any])?["fields"] as? [String: [String: Any]]
        let newUkrainian = (newLanguages["uk"]?["mapValue"] as? [String: Any])?["fields"] as? [String: [String: Any]]
        for key in ["subtitle", "body"] { XCTAssertEqual(newUkrainian?[key] as NSDictionary?, oldUkrainian?[key] as NSDictionary?) }
        capture(author, "sdk-moderation-author-resubmitted"); author.terminate()

        let reviewer = launchMember(account: "owner", moderationReviewer: true)
        reviewer.tabBars.buttons.element(boundBy: 4).tap()
        let entry = reviewer.buttons["profile.moderation"].firstMatch
        revealModeration(entry, reviewer); entry.tap()
        let pending = reviewer.buttons["content.moderation.open.mod-audit-news"].firstMatch
        revealModeration(pending, reviewer); pending.tap()
        let approve = reviewer.buttons["content.review.choice.approved"].firstMatch
        revealModeration(approve, reviewer); approve.tap()
        reviewer.buttons["content.review.confirm"].firstMatch.tap()
        let final = reviewer.alerts.buttons["content.review.execute"].firstMatch
        XCTAssertTrue(final.waitForExistence(timeout: 5)); capture(reviewer, "sdk-moderation-corrected-approval"); final.tap()
        XCTAssertTrue(pending.waitForNonExistence(timeout: 20))
        let approved = try await readDemoDocument(path)
        let approvedFields = try XCTUnwrap(approved["fields"] as? [String: [String: Any]])
        XCTAssertEqual(approvedFields["moderationStatus"]?["stringValue"] as? String, "approved")
        XCTAssertEqual(approvedFields["publishedAt"] as NSDictionary?, approvedFields["moderatedAt"] as NSDictionary?)
        reviewer.tabBars.buttons.element(boundBy: 0).tap()
        let published = reviewer.buttons["home.card.news-mod-audit-news"].firstMatch
        revealModeration(published, reviewer); capture(reviewer, "sdk-moderation-approved-news-in-live-feed")
    }

    func testConnectedEventModerationCorrectionResubmissionAndRejection() async throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" else { throw XCTSkip("Fixed isolated demo required") }
        let noticeWindowStart = Date()
        let path = "events/mod-audit-event"
        ownedRequestDocumentPaths.insert(path)
        let before = try await readDemoDocument(path)
        let original = try XCTUnwrap(before["fields"] as? [String: [String: Any]])
        let app = launchMember(account: "owner", moderationReviewer: true)
        app.tabBars.buttons.element(boundBy: 4).tap()
        let moderation = app.buttons["profile.moderation"].firstMatch
        revealModeration(moderation, app); moderation.tap()
        let type = app.segmentedControls["content.moderation.type"].firstMatch
        XCTAssertTrue(type.waitForExistence(timeout: 10)); type.buttons.element(boundBy: 1).tap()
        let row = app.buttons["content.moderation.open.mod-audit-event"].firstMatch
        revealModeration(row, app); row.tap()
        let revise = app.buttons["content.review.choice.needsRevision"].firstMatch
        revealModeration(revise, app); revise.tap()
        let reason = app.textFields["content.review.reason"].firstMatch
        revealModeration(reason, app); reason.tap(); reason.typeText("Уточніть назву події. Контрольована перевірка.")
        if app.keyboards.firstMatch.exists { app.coordinate(withNormalizedOffset: .init(dx: 0.96, dy: 0.12)).tap() }
        app.buttons["content.review.confirm"].firstMatch.tap()
        let execute = app.alerts.buttons["content.review.execute"].firstMatch
        XCTAssertTrue(execute.waitForExistence(timeout: 5)); execute.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 20)); app.terminate()
        let noticeID = try await moderationNoticeID(source: "event:mod-audit-event", status: "needsRevision", after: noticeWindowStart)
        let author = launchMember(account: "member")
        author.tabBars.buttons.element(boundBy: 4).tap()
        let inbox = author.buttons["profile.notifications.open"].firstMatch
        revealModeration(inbox, author); inbox.tap()
        let notice = author.buttons["notificationInbox.open." + noticeID].firstMatch
        revealModeration(notice, author); notice.tap()
        let destination = author.buttons["notificationDetail.openDestination"].firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout: 10)); destination.tap()
        let edit = author.buttons["content.review.edit"].firstMatch
        revealModeration(edit, author); capture(author, "sdk-event-moderation-exact-returned-material"); edit.tap()
        let title = author.textFields["editor.event.title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 15)); title.tap(); title.typeText(" виправлено")
        let correctedTitle = try XCTUnwrap(title.value as? String)
        if author.keyboards.firstMatch.exists { author.coordinate(withNormalizedOffset: .init(dx: 0.96, dy: 0.12)).tap() }
        let next = author.buttons["editor.event.next"].firstMatch
        for _ in 0..<3 { revealModeration(next, author); XCTAssertTrue(next.isEnabled); next.tap() }
        let save = author.buttons["editor.event.submit"].firstMatch
        revealModeration(save, author); XCTAssertTrue(save.isEnabled); capture(author, "sdk-event-correction-preview"); save.tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 25))
        let corrected = try await readDemoDocument(path)
        let fields = try XCTUnwrap(corrected["fields"] as? [String: [String: Any]])
        XCTAssertEqual(fields["title"]?["stringValue"] as? String, correctedTitle)
        XCTAssertEqual(fields["moderationStatus"]?["stringValue"] as? String, "pendingReview")
        XCTAssertEqual(fields["moderationReason"]?["stringValue"] as? String, "")
        for key in ["summary", "details", "imageURL", "category", "organizationId", "organizationName", "authorId", "authorName", "federalState", "regionScope", "sourceType", "city", "venue", "address", "startDate", "endDate", "occurrences", "pricing", "participationMode", "capacity", "registeredCount", "externalAction", "mediaMetadata"] {
            XCTAssertEqual(fields[key] as NSDictionary?, original[key] as NSDictionary?, "Unedited event field must survive: " + key)
        }
        XCTAssertNil(fields["publishedAt"])
        capture(author, "sdk-event-resubmitted-readback"); author.terminate()
        let reviewer = launchMember(account: "owner", moderationReviewer: true)
        reviewer.tabBars.buttons.element(boundBy: 4).tap()
        let entry = reviewer.buttons["profile.moderation"].firstMatch
        revealModeration(entry, reviewer); entry.tap()
        let eventType = reviewer.segmentedControls["content.moderation.type"].firstMatch
        XCTAssertTrue(eventType.waitForExistence(timeout: 10)); eventType.buttons.element(boundBy: 1).tap()
        let pending = reviewer.buttons["content.moderation.open.mod-audit-event"].firstMatch
        revealModeration(pending, reviewer); pending.tap()
        let reject = reviewer.buttons["content.review.choice.rejected"].firstMatch
        revealModeration(reject, reviewer); reject.tap()
        let rejection = reviewer.textFields["content.review.reason"].firstMatch
        revealModeration(rejection, reviewer); rejection.tap(); rejection.typeText("Контрольовану перевірку завершено. Не публікувати.")
        if reviewer.keyboards.firstMatch.exists { reviewer.coordinate(withNormalizedOffset: .init(dx: 0.96, dy: 0.12)).tap() }
        reviewer.buttons["content.review.confirm"].firstMatch.tap()
        let final = reviewer.alerts.buttons["content.review.execute"].firstMatch
        XCTAssertTrue(final.waitForExistence(timeout: 5)); capture(reviewer, "sdk-event-rejection-confirmation"); final.tap()
        XCTAssertTrue(pending.waitForNonExistence(timeout: 20))
        let rejected = try await readDemoDocument(path)
        XCTAssertEqual((rejected["fields"] as? [String: [String: Any]])?["moderationStatus"]?["stringValue"] as? String, "rejected")
        _ = try await moderationNoticeID(source: "event:mod-audit-event", status: "rejected", after: noticeWindowStart)
    }

    private func revealModeration(_ target: XCUIElement, _ app: XCUIApplication) {
        _ = target.waitForExistence(timeout: 5)
        if app.alerts.firstMatch.exists, target.exists, target.isHittable { return }
        for _ in 0..<24 {
            let scroll = app.scrollViews.allElementsBoundByIndex.first(where: { $0.isHittable })
            let top = max(scroll?.frame.minY ?? 80, app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY : 80) + 12
            var bottom = min(scroll?.frame.maxY ?? app.frame.height, app.frame.height - 35)
            let footer = app.buttons["content.review.confirm"].firstMatch
            if footer.exists, footer.isHittable, (!target.exists || target.identifier != "content.review.confirm"),
               footer.frame.minY > app.frame.height * 0.6 { bottom = min(bottom, footer.frame.minY - 18) }
            let bar = app.tabBars.firstMatch
            if bar.exists && bar.isHittable { bottom = min(bottom, bar.frame.minY - 12) }
            if target.exists && target.isHittable && target.frame.midY > top && target.frame.midY < bottom { return }
            let upward = target.exists && target.frame.midY < top
            let upper = min(max((top + 35) / app.frame.height, 0.2), 0.55)
            let lower = max(min((bottom - 20) / app.frame.height, 0.8), upper + 0.15)
            app.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: upward ? upper : lower))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: upward ? lower : upper)))
        }
        XCTFail("Moderation control not visible in its scroll viewport: \(target)")
    }

    private func moderationNoticeID(source: String, status: String, after: Date? = nil) async throws -> String {
        for _ in 0..<30 {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:28080/v1/projects/demo-uac-release-audit/databases/(default)/documents/users/closure-member:runQuery")!)
            request.httpMethod = "POST"; request.setValue("Bearer owner", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["structuredQuery": ["from": [["collectionId": "notificationInbox"]],
                "where": ["fieldFilter": ["field": ["fieldPath": "sourceId"], "op": "EQUAL", "value": ["stringValue": source]]],
                "orderBy": [["field": ["fieldPath": "createdAt"], "direction": "DESCENDING"]], "limit": 20]])
            let (data, response) = try await URLSession.shared.data(for: request)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            let result = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
            for row in result {
                guard let document = row["document"] as? [String: Any], let fields = document["fields"] as? [String: [String: Any]],
                      let metadata = fields["metadata"]?["mapValue"] as? [String: Any], let values = metadata["fields"] as? [String: [String: Any]],
                      values["moderationStatus"]?["stringValue"] as? String == status,
                      fields["recipientUserId"]?["stringValue"] as? String == "closure-member",
                      let name = document["name"] as? String, let id = name.split(separator: "/").last else { continue }
                if let after {
                    guard let raw = fields["createdAt"]?["timestampValue"] as? String else { continue }
                    let parser = ISO8601DateFormatter()
                    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    var created = parser.date(from: raw)
                    if created == nil { parser.formatOptions = [.withInternetDateTime]; created = parser.date(from: raw) }
                    guard let created, created >= after else { continue }
                }
                return String(id)
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw NSError(domain: "ModerationNotificationNotDelivered", code: 1)
    }

    private func launchMember(language: String = "uk", appearance: String = "light", large: Bool = false, account: String = "member", maximumText: Bool = false, moderationReviewer: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-sdk-ui-audit", "-selectedAppLanguage", language, "-selectedAppAppearance", appearance,
                               "-UIPreferredContentSizeCategoryName", maximumText ? "UICTContentSizeCategoryAccessibilityXXXL" : large ? "UICTContentSizeCategoryAccessibilityM" : "UICTContentSizeCategoryL"]
        app.launchEnvironment = ["UACFirebaseEmulators": "1"]
        if moderationReviewer { app.launchEnvironment["UACEmulatorModerationReviewer"] = "1" }
        if maximumText { app.launchArguments.append("-FIRDebugEnabled") }
        app.launch()
        if moderationReviewer {
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))
            return app
        }
        let signIn = app.buttons["auth.landing.signIn"]
        if app.tabBars.firstMatch.waitForExistence(timeout: 8) {
            app.tabBars.buttons.element(boundBy: 4).tap()
            let logout = app.buttons["profile.logout.button"]
            reveal(logout, app); logout.tap()
            let confirm = app.alerts.buttons["profile.logout.confirm"].firstMatch
            XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        }
        if signIn.waitForExistence(timeout: 20) {
            signIn.tap()
            let email = app.textFields["auth.login.email"]
            XCTAssertTrue(email.waitForExistence(timeout: 8)); email.tap(); email.typeText("closure-" + account + "@uac.test")
            let password = app.secureTextFields["auth.login.password"]
            password.tap(); password.typeText("Emulator-Only-2026!")
            app.swipeUp()
            let submit = app.buttons["auth.login.submit"]
            reveal(submit, app); submit.tap()
        }
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))
        let later = app.buttons["auth.passkeySuggestion.later"]
        if later.waitForExistence(timeout: 5) { reveal(later, app); capture(app, "sdk-passkey-suggestion"); later.tap() }
        return app
    }

    private func reveal(_ element: XCUIElement, _ app: XCUIApplication, preferUpwardScroll: Bool = false) {
        _ = element.waitForExistence(timeout: 8)
        for _ in 0..<32 {
            let bottomInset: CGFloat = app.tabBars.firstMatch.exists ? 100 : 30
            if element.exists && element.frame.width > 0 && element.frame.height > 0 && element.frame.midY > 100 && element.frame.midY < app.frame.height - bottomInset { return }
            let towardTop = element.exists ? element.frame.midY < 100 : preferUpwardScroll
            let keyboardVisible = app.keyboards.firstMatch.exists
            let lower: CGFloat = keyboardVisible ? 0.43 : 0.65
            let upper: CGFloat = keyboardVisible ? 0.25 : 0.35
            app.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: towardTop ? upper : lower))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: towardTop ? lower : upper)))
        }
        XCTAssertTrue(element.exists && element.frame.width > 0 && element.frame.height > 0)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
