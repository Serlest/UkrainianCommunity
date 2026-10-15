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
        app.launchEnvironment["UITestLegalReverification"] = "success"
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
        XCUIDevice.shared.press(.home)
        app.activate()
        let verifying = app.otherElements["startup.access.verifying"].firstMatch
        XCTAssertTrue(verifying.waitForExistence(timeout: 5))
        XCTAssertTrue(verifying.waitForNonExistence(timeout: 15))
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.buttons["Готово"].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testUserOpensOwnRequestAndNotificationsFromProfileAndBell() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launchEnvironment["UITestResetUserSettings"] = "1"
        app.launchEnvironment["UITestAppLanguage"] = "uk"
        app.launchEnvironment["UITestForceAuthenticatedSession"] = "1"
        app.launchEnvironment["UITestFeedbackInbox"] = "1"
        app.launchEnvironment["UITestNotificationDetails"] = "1"
        app.launch()
        let profile = app.tabBars.buttons.element(boundBy: 4)
        XCTAssertTrue(profile.waitForExistence(timeout: 15)); profile.tap()
        let mine = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Мої звернення")).firstMatch
        reveal(mine, app); mine.tap()
        let request = app.buttons["feedback.mine.open.directory-feedback-fixture"]
        XCTAssertTrue(request.waitForExistence(timeout: 8)); request.tap()
        let done = app.buttons["Готово"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
        XCTAssertTrue(request.waitForExistence(timeout: 5))
        app.buttons["Назад"].firstMatch.tap()
        let inbox = app.buttons["profile.notifications.open"]
        reveal(inbox, app); inbox.tap()
        openAndCloseNotification(app)
        app.buttons["Назад"].firstMatch.tap()
        let bell = app.buttons["notificationInbox.bell"]
        reveal(bell, app); bell.tap()
        openAndCloseNotification(app)
        app.buttons["Назад"].firstMatch.tap()
        XCTAssertTrue(bell.waitForExistence(timeout: 5))
        XCTAssertTrue(profile.isSelected)
    }

    @MainActor
    private func openAndCloseNotification(_ app: XCUIApplication) {
        let row = app.buttons["notificationInbox.open.detail-info"]
        XCTAssertTrue(row.waitForExistence(timeout: 8)); row.tap()
        let close = app.buttons["notificationDetail.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5)); close.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
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
