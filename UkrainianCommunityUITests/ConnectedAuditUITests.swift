import XCTest

/// Real UI and actual SDK graph against the fixed demo emulators; no fixture roles/repositories.
@MainActor
final class ConnectedAuditUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testMemberBookmarkThroughUIAndReopenAfterProcessRestart() throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" else {
            throw XCTSkip("Requires local audit emulator fixtures")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-sdk-ui-audit", "-selectedAppLanguage", "uk", "-selectedAppAppearance", "light"]
        app.launchEnvironment = ["UACFirebaseEmulators": "1"]
        app.launch()
        let signIn = app.buttons["auth.landing.signIn"]
        if signIn.waitForExistence(timeout: 20) {
            signIn.tap()
            let email = app.textFields["auth.login.email"]
            XCTAssertTrue(email.waitForExistence(timeout: 8)); email.tap(); email.typeText("closure-member@uac.test")
            let password = app.secureTextFields["auth.login.password"]
            password.tap(); password.typeText("Emulator-Only-2026!")
            app.swipeUp()
            let submit = app.buttons["auth.login.submit"]
            reveal(submit, app); submit.tap()
        }
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))
        let later = app.buttons["auth.passkeySuggestion.later"]
        if later.waitForExistence(timeout: 5) { capture(app, "sdk-passkey-suggestion"); later.tap() }
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
