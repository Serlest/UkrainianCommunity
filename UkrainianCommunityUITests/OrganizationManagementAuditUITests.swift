import XCTest

@MainActor
final class OrganizationManagementAuditUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testOwnerEditCancelSaveAndReopen() {
        let app = launch(); manage(app)
        let edit = app.buttons["organization.management.editInfo"].firstMatch
        reveal(edit, app); edit.tap()
        let name = app.textFields["organization.editor.name"].firstMatch
        reveal(name, app); let original = name.value as! String
        name.tap(); name.typeText(" Updated"); dismissKeyboard(app)
        let cancel = app.buttons["Скасувати"].firstMatch
        reveal(cancel, app); cancel.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        capture(app, "organization-edit-discard-dialog")
        app.alerts.buttons["Продовжити редагування"].tap()
        reveal(name, app); XCTAssertTrue((name.value as? String)?.contains("Updated") == true)
        for step in ["basics", "location", "features"] {
            capture(app, "organization-edit-" + step)
            let next = app.buttons["organizationEditor.next"].firstMatch
            reveal(next, app); XCTAssertTrue(next.isEnabled); next.tap()
        }
        let submit = app.buttons["organizationEditor.submit"].firstMatch
        reveal(submit, app); capture(app, "organization-edit-preview"); submit.tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 10))
        reveal(edit, app); edit.tap(); reveal(name, app)
        XCTAssertEqual(name.value as? String, original + " Updated")
        capture(app, "organization-edit-persisted")
    }

    func testMemberCreatesRequestThroughAllStepsAndRules() {
        let app = launch(role: "member")
        let create = app.buttons["organization.management.create"].firstMatch
        reveal(create, app); create.tap()
        let name = app.textFields["organization.editor.name"].firstMatch
        reveal(name, app); name.tap(); name.typeText("Audit New Request"); dismissKeyboard(app)
        let description = app.descendants(matching: .any).matching(identifier: "organization.editor.description").firstMatch
        reveal(description, app); description.tap(); description.typeText("Community support and cultural events for Ukrainian families.")
        dismissKeyboard(app)
        next(app)
        let region = app.buttons["organization.editor.region"].firstMatch
        if region.exists { reveal(region, app); region.tap() }
        else {
            let fallback = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Оберіть землю")).firstMatch
            reveal(fallback, app); fallback.tap()
        }
        app.buttons["Тіроль"].firstMatch.tap()
        let city = app.textFields["organization.editor.city"].firstMatch
        reveal(city, app); city.tap(); city.typeText("Innsbruck"); dismissKeyboard(app)
        capture(app, "organization-create-location"); next(app)
        capture(app, "organization-create-features"); next(app)
        let read = app.buttons["organizationEditor.rules.read"].firstMatch
        reveal(read, app); read.tap()
        let close = app.buttons["organizationEditor.rules.close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 8)); capture(app, "organization-create-rules"); close.tap()
        let consent = app.switches["organizationEditor.rules.confirm"].firstMatch
        reveal(consent, app); XCTAssertTrue(consent.isEnabled); consent.tap()
        let submit = app.buttons["organizationEditor.submit"].firstMatch
        reveal(submit, app); XCTAssertTrue(submit.isEnabled); capture(app, "organization-create-ready"); submit.tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 10))
        let saved = app.staticTexts["Audit New Request"].firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10)); capture(app, "organization-request-saved")
        let preview = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "organization.request.preview.")).firstMatch
        reveal(preview, app); preview.tap()
        let done = app.buttons["Готово"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 8)); capture(app, "organization-own-request-preview"); done.tap()
        let remove = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "organization.request.delete.")).firstMatch
        reveal(remove, app); remove.tap()
        let confirm = app.popovers.buttons["Відкликати заявку"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); capture(app, "organization-withdraw-confirmation")
        confirm.tap()
        XCTAssertTrue(saved.waitForNonExistence(timeout: 10))
    }

    func testGermanDarkManagementNestedWindowsAtLargeText() {
        let app = launch(germanDark: true); manage(app)
        capture(app, "organization-managed-de-dark")
        let edit = app.buttons["organization.management.editInfo"].firstMatch
        reveal(edit, app); edit.tap()
        for section in ["basics", "location", "features"] {
            capture(app, "organization-editor-de-dark-" + section); next(app)
        }
        let submit = app.buttons["organizationEditor.submit"].firstMatch
        reveal(submit, app); capture(app, "organization-editor-de-dark-preview")
        let cancel = app.buttons["Abbrechen"].firstMatch; reveal(cancel, app); cancel.tap()
        let add = app.buttons["organization.management.addTeamMember"].firstMatch
        reveal(add, app); add.tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 8))
        capture(app, "organization-team-candidates-de-dark")
        app.buttons["Abbrechen"].firstMatch.tap()
        let followers = app.buttons["organization.management.subscribers"].firstMatch
        reveal(followers, app); followers.tap()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 8)); capture(app, "organization-subscribers-de-dark")
        app.buttons["navigation.back"].firstMatch.tap()
        let photo = app.buttons["Audit photo"].firstMatch
        reveal(photo, app); photo.tap()
        let done = app.buttons["Fertig"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 8)); capture(app, "organization-management-photo-de-dark"); done.tap()
    }

    func testAdminWarnedBlockedAndGuestEntryRights() {
        for role in ["admin", "warned", "blocked", "guest"] {
            let app = XCUIApplication()
            app.launchArguments = ["-ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
            app.launchEnvironment = ["UITestResetUserSettings":"1", "UITestResetAppLock":"1", "UITestAppLanguage":"uk"]
            if role == "guest" { app.launchEnvironment["UITestForceGuestSession"] = "1" }
            else { app.launchEnvironment["UITestProfileRole"] = role }
            app.launch()
            let profile = app.tabBars.buttons.element(boundBy: 4)
            XCTAssertTrue(profile.waitForExistence(timeout: 20)); profile.tap()
            let entry = app.buttons["profile.organizationManagement"].firstMatch
            if role == "blocked" || role == "guest" {
                XCTAssertFalse(entry.exists)
            } else {
                reveal(entry, app); entry.tap()
                XCTAssertTrue(app.buttons["organization.management.create"].firstMatch.waitForExistence(timeout: 8))
                XCTAssertFalse(app.buttons["organization.manage.org-1"].exists)
            }
            capture(app, "organization-entry-" + role); app.terminate()
        }
    }

    private func launch(role: String = "owner", germanDark: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-UIPreferredContentSizeCategoryName", germanDark ? "UICTContentSizeCategoryAccessibilityM" : "UICTContentSizeCategoryL"]
        app.launchEnvironment = ["UITestResetUserSettings":"1", "UITestResetAppLock":"1", "UITestResetContentDrafts":"1",
            "UITestAppLanguage":germanDark ? "de":"uk", "UITestAppAppearance":germanDark ? "dark":"light", "UITestGallery":"1"]
        if role == "owner" { app.launchEnvironment["UITestForceOwnerSession"] = "1" }
        else { app.launchEnvironment["UITestProfileRole"] = role }
        app.launch()
        let profile = app.tabBars.buttons.element(boundBy: 4)
        XCTAssertTrue(profile.waitForExistence(timeout: 20)); profile.tap()
        let entry = app.buttons["profile.organizationManagement"].firstMatch
        reveal(entry, app); entry.tap(); return app
    }
    private func manage(_ app: XCUIApplication) {
        let item = app.buttons["organization.manage.org-1"].firstMatch
        reveal(item, app); item.tap()
        XCTAssertTrue(app.buttons["organization.management.editInfo"].firstMatch.waitForExistence(timeout: 8))
    }
    private func next(_ app: XCUIApplication) {
        let button = app.buttons["organizationEditor.next"].firstMatch
        reveal(button, app); XCTAssertTrue(button.isEnabled); button.tap()
    }
    private func dismissKeyboard(_ app: XCUIApplication) {
        if app.keyboards.firstMatch.exists {
            app.coordinate(withNormalizedOffset: .init(dx: 0.75, dy: 0.12)).tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        }
    }
    private func reveal(_ item: XCUIElement, _ app: XCUIApplication) {
        _ = item.waitForExistence(timeout: 8)
        for _ in 0..<60 {
            if item.exists && item.isHittable && item.frame.midY > 45 && item.frame.midY < app.frame.height - 125 { return }
            let down = item.exists && item.frame.midY < 45
            app.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: down ? 0.35 : 0.70)).press(forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: down ? 0.65 : 0.40)))
        }
        XCTAssertTrue(item.exists && item.isHittable)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let value = XCTAttachment(screenshot: app.screenshot()); value.name = name; value.lifetime = .keepAlways; add(value)
    }
}
