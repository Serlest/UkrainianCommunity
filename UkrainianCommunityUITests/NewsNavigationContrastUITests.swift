import XCTest

@MainActor
final class NewsNavigationContrastUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testLightNewsAndEverySelectedTab() { audit(appearance: "light", language: "uk") }
    func testDarkNewsAndEverySelectedTab() { audit(appearance: "dark", language: "de") }

    private func audit(appearance: String, language: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launchEnvironment = ["UITestForceAuthenticatedSession": "1", "UITestResetUserSettings": "1",
            "UITestResetAppLock": "1", "UITestAppLanguage": language, "UITestAppAppearance": appearance]
        app.launch()
        let tabs = app.tabBars.buttons
        XCTAssertTrue(tabs.element(boundBy: 0).waitForExistence(timeout: 20))
        XCTAssertEqual(tabs.count, 5)
        let news = app.buttons["home.card.news-news-1"].firstMatch
        XCTAssertTrue(news.waitForExistence(timeout: 15))
        capture(app, "\(appearance)-news-top")
        app.swipeUp()
        capture(app, "\(appearance)-news-scrolled")
        for index in 0..<5 {
            let tab = tabs.element(boundBy: index)
            XCTAssertTrue(tab.isHittable)
            XCTAssertFalse(tab.label.isEmpty)
            tab.tap()
            XCTAssertTrue(tab.isSelected)
            capture(app, "\(appearance)-tab-\(index)")
        }
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
