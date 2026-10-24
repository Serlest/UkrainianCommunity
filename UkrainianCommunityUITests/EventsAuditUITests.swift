import XCTest

@MainActor
final class EventsAuditUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testOwnerEditsAndReopensExactEvent() {
        let app = launch("owner")
        open("own", app)
        app.buttons["detail.header.more-actions"].tap()
        app.buttons["Редагувати"].tap()
        let title = app.textFields["editor.event.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 8)); title.tap(); title.typeText(" Updated")
        dismissKeyboard(app)
        let next = app.buttons["editor.event.next"].firstMatch
        for step in 0..<3 {
            reveal(next, app); capture(app, "event-editor-step-\(step)"); XCTAssertTrue(next.isEnabled); next.tap()
        }
        let submit = app.buttons["editor.event.submit"].firstMatch
        reveal(submit, app); capture(app, "event-preview"); XCTAssertTrue(submit.isEnabled); submit.tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Audit Event own Updated"].firstMatch.waitForExistence(timeout: 10))
        capture(app, "event-saved-detail")
        app.buttons["navigation.back"].firstMatch.tap()
        open("own", app)
        XCTAssertTrue(app.staticTexts["Audit Event own Updated"].firstMatch.waitForExistence(timeout: 8))
    }
    func testOwnAndForeignPermissionsForAllUsableRoles() {
        for role in ["owner", "admin", "org-owner", "org-admin", "org-moderator", "mixed", "member", "warned"] {
            for scope in ["own", "foreign"] {
                let app = launch(role); open(scope, app)
                let more = app.buttons["detail.header.more-actions"].firstMatch
                XCTAssertTrue(more.waitForExistence(timeout: 8)); more.tap()
                let authorized = role == "owner" || (scope == "own" && ["org-owner", "org-admin", "org-moderator", "mixed"].contains(role))
                if authorized { XCTAssertTrue(app.buttons["Редагувати"].waitForExistence(timeout: 8)) }
                XCTAssertEqual(app.buttons["Редагувати"].exists, authorized, "\(role), \(scope)")
                capture(app, "event-menu-\(role)-\(scope)")
                app.terminate()
            }
        }
    }
    func testGuestRegistrationRequiresSignInAndBlockedInteractionsAreDisabled() {
        let guest = launch("guest"); open("own", guest)
        let register = guest.buttons["event.register.audit-event-own"].firstMatch
        reveal(register, guest); register.tap()
        XCTAssertTrue(guest.alerts.firstMatch.waitForExistence(timeout: 5)); capture(guest, "event-guest-register")
        guest.terminate()
        let blocked = launch("blocked"); open("own", blocked)
        let disabled = blocked.buttons["event.register.audit-event-own"].firstMatch
        reveal(disabled, blocked); XCTAssertFalse(disabled.isEnabled)
        capture(blocked, "event-blocked-register")
    }
    func testRegistrationCancellationAndBookmarkPersistAfterReturning() {
        let app = launch("member"); open("own", app)
        let register = app.buttons["event.register.audit-event-own"].firstMatch
        reveal(register, app); register.tap()
        let confirm = app.buttons["event.registration.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); capture(app, "event-registration-confirm"); confirm.tap()
        let cancelledTitle = NSPredicate(format: "label CONTAINS %@", "Скасувати")
        expectation(for: cancelledTitle, evaluatedWith: register); waitForExpectations(timeout: 8)
        capture(app, "event-registered")
        app.buttons["navigation.back"].firstMatch.tap(); open("own", app)
        reveal(register, app); XCTAssertTrue(register.label.contains("Скасувати")); register.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        expectation(for: NSPredicate(format: "NOT (label CONTAINS %@)", "Скасувати"), evaluatedWith: register)
        waitForExpectations(timeout: 8)
        app.swipeDown(); app.swipeDown()
        let save = app.buttons["detail.header.action.bookmark"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 5)); save.tap()
        XCTAssertTrue(app.buttons["detail.header.action.bookmark.fill"].waitForExistence(timeout: 5))
        app.buttons["navigation.back"].firstMatch.tap(); open("own", app)
        XCTAssertTrue(app.buttons["detail.header.action.bookmark.fill"].waitForExistence(timeout: 5))
        capture(app, "event-bookmark-reopened")
    }
    func testUnsavedEditRequiresExplicitDiscard() {
        let app = launch("owner"); open("own", app)
        app.buttons["detail.header.more-actions"].tap(); app.buttons["Редагувати"].tap()
        let title = app.textFields["editor.event.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 8)); title.tap(); title.typeText(" Unsaved")
        dismissKeyboard(app)
        let close = app.buttons["editor.close"].firstMatch
        if close.exists { close.tap() } else { app.buttons["Скасувати"].firstMatch.tap() }
        XCTAssertTrue(app.alerts["Відхилити зміни?"].waitForExistence(timeout: 5))
        capture(app, "event-unsaved-edit")
    }
    func testOwnerOpensParticipantsOnlyWhenRequested() {
        let app = launch("owner"); open("own", app)
        let register = app.buttons["event.register.audit-event-own"].firstMatch
        reveal(register, app); register.tap()
        let confirm = app.buttons["event.registration.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        let participants = app.buttons["event.attendees.open"].firstMatch
        reveal(participants, app); participants.tap()
        let search = app.textFields["event.attendees.search"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        capture(app, "event-participants-loaded")
        search.tap(); search.typeText("No matching participant")
        capture(app, "event-participants-search-empty")
        dismissKeyboard(app)
    }
    func testGermanDarkDetailAtAccessibilitySize() {
        let app = launch("member", germanDark: true); open("own", app)
        capture(app, "event-de-dark-AX-header")
        for i in 0..<5 { app.swipeUp(); capture(app, "event-de-dark-AX-\(i)") }
    }
    private func launch(_ role: String, germanDark: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-UIPreferredContentSizeCategoryName", germanDark ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launchEnvironment = ["UITestResetUserSettings":"1", "UITestResetAppLock":"1", "UITestResetContentDrafts":"1", "UITestAppLanguage":germanDark ? "de":"uk", "UITestAppAppearance":germanDark ? "dark":"light", "UITestEventsAudit":"1"]
        if role == "owner" { app.launchEnvironment["UITestForceOwnerSession"] = "1" }
        else if role == "guest" { app.launchEnvironment["UITestForceGuestSession"] = "1" }
        else { app.launchEnvironment["UITestProfileRole"] = role }
        app.launch()
        let tab = app.tabBars.buttons[germanDark ? "Termine":"Події"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        return app
    }
    private func open(_ scope: String, _ app: XCUIApplication) {
        let card = app.descendants(matching: .any).matching(identifier: "event.card.audit-event-" + scope).firstMatch
        reveal(card, app); card.tap()
        XCTAssertTrue(app.buttons["navigation.back"].waitForExistence(timeout: 8))
    }
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        _ = element.waitForExistence(timeout: 8)
        for _ in 0..<16 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }
    private func dismissKeyboard(_ app: XCUIApplication) {
        if app.keyboards.firstMatch.exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.12)).tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        }
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
