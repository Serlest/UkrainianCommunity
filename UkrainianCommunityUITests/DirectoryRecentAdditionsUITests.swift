import XCTest

final class DirectoryRecentAdditionsUITests: XCTestCase {
    @MainActor
    func testRecentSectionHasLocalizedEmptyStateBeforeStartCategories() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launchEnvironment["UITestResetUserSettings"] = "1"
        app.launchEnvironment["UITestAppLanguage"] = "uk"
        app.launchEnvironment["UITestForceOwnerSession"] = "1"
        app.launchEnvironment["UITestDirectoryRecentEmpty"] = "1"
        app.launch()
        let tab = app.tabBars.buttons.element(boundBy: 3)
        XCTAssertTrue(tab.waitForExistence(timeout: 15))
        tab.tap()
        let heading = app.staticTexts["Останнє додане"]
        for _ in 0..<7 {
            if heading.exists && heading.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(heading.exists)
        XCTAssertTrue(app.staticTexts["Нові матеріали з’являться тут після публікації."].exists)
        XCTAssertFalse(app.buttons["directory.recent.more"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Directory recent additions empty state"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
