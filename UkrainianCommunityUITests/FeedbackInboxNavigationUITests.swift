import XCTest

final class FeedbackInboxNavigationUITests: XCTestCase {
    @MainActor
    func testOwnerOpensFeedbackAndReturnsToInbox() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launchEnvironment["UITestResetUserSettings"] = "1"
        app.launchEnvironment["UITestAppLanguage"] = "uk"
        app.launchEnvironment["UITestForceOwnerSession"] = "1"
        app.launchEnvironment["UITestFeedbackInbox"] = "1"
        app.launch()
        let profile = app.tabBars.buttons.element(boundBy: 4)
        XCTAssertTrue(profile.waitForExistence(timeout: 15)); profile.tap()
        let inbox = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Відгуки користувачів")).firstMatch
        reveal(inbox, app); inbox.tap()
        let row = app.buttons["feedbackInbox.open.directory-feedback-fixture"]
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap()
        XCTAssertTrue(app.buttons["Готово"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Feedback navigation fixture"].firstMatch.exists)
        app.buttons["Готово"].firstMatch.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.buttons["Готово"].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<14 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists)
    }
}
