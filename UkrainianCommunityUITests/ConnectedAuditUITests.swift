import XCTest

/// Real UI and actual SDK graph against the fixed demo emulators; no fixture roles/repositories.
@MainActor
final class ConnectedAuditUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

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

    func testActualPhotoPickerCropCancelAndApplyPreserveEditor() throws {
        try photoJourney(language: "uk", appearance: "light", large: false)
    }

    func testActualPhotoPickerGermanDarkAtAccessibilitySize() throws {
        try photoJourney(language: "de", appearance: "dark", large: true)
    }

    private func photoJourney(language: String, appearance: String, large: Bool) throws {
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
        // Upload/persistence is a separate SDK journey; terminating discards the
        // unsaved crop here and never changes a production profile.
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

    private func readDemoDocument(_ path: String) async throws -> [String: Any] {
        try await demoRequest(path, method: "GET", fields: nil)
    }
    private func patchDemoDocument(_ path: String, fields: [String: [String: Any]]) async throws {
        _ = try await demoRequest(path, method: "PATCH", fields: fields)
    }
    private func demoRequest(_ path: String, method: String, fields: [String: [String: Any]]?, expectedStatus: Int = 200) async throws -> [String: Any] {
        // Fixed loopback + demo project. This helper cannot address production.
        guard ["directoryEditors/closure-editor", "directoryCategories/first-steps",
               "users/closure-member/organizationBookmarks/closure-org",
               "likes/organization_follow_closure-org_closure-member",
               "users/closure-member/blockedUsers/closure-other"].contains(path) else {
            throw NSError(domain: "AuditFixture", code: 1)
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

    private func launchMember(language: String = "uk", appearance: String = "light", large: Bool = false, account: String = "member") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-sdk-ui-audit", "-selectedAppLanguage", language, "-selectedAppAppearance", appearance,
                               "-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityM" : "UICTContentSizeCategoryL"]
        app.launchEnvironment = ["UACFirebaseEmulators": "1"]
        app.launch()
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
        if later.waitForExistence(timeout: 5) { capture(app, "sdk-passkey-suggestion"); later.tap() }
        return app
    }

    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
