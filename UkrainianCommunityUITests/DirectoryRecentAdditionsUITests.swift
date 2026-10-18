import XCTest

final class DirectoryRecentAdditionsUITests: XCTestCase {
    @MainActor
    func testCompactPreviewLanguageAppearanceAndLargeText() {
        continueAfterFailure = false
        for (language, appearance, largeText) in [("uk", "light", false), ("uk", "dark", false),
                                                   ("de", "light", false), ("de", "dark", true)] {
            let app = XCUIApplication()
            app.launchArguments = ["-ui-testing", "-selectedAppAppearance", appearance]
            if largeText {
                app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            }
            app.launchEnvironment = ["UITestResetUserSettings": "1", "UITestAppLanguage": language,
                "UITestForceOwnerSession": "1", "UITestDirectoryRecentPreview": "1",
                "UITestDirectoryRecentEmpty": "0", "UITestResetAppLock": "1"]
            app.launch()
            let tab = app.tabBars.buttons.element(boundBy: 3)
            XCTAssertTrue(tab.waitForExistence(timeout: 15)); tab.tap()
            let first = app.buttons["directory.recent.preview-1"]
            let more = app.buttons["directory.recent.showAll"]
            for _ in 0..<10 {
                if more.exists && more.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(first.exists)
            XCTAssertGreaterThanOrEqual(first.frame.height, 44)
            XCTAssertFalse(app.buttons["directory.recent.preview-4"].exists)
            XCTAssertTrue(more.isHittable)
            XCTAssertGreaterThan(first.label.count, 40, "VoiceOver keeps the complete long title")
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "compact-\(language)-\(appearance)-\(largeText ? "AXXXL" : "standard")"
            screenshot.lifetime = .keepAlways; add(screenshot)
            app.terminate()
        }
    }

    @MainActor
    func testPreviewShowsThreeThenOpensFullFeedAndReturns() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launchEnvironment = ["UITestResetUserSettings": "1", "UITestAppLanguage": "uk",
                                 "UITestForceOwnerSession": "1", "UITestDirectoryRecentPreview": "1",
                                 "UITestDirectoryRecentEmpty": "0", "UITestResetAppLock": "1"]
        app.launch()
        let tab = app.tabBars.buttons.element(boundBy: 3)
        XCTAssertTrue(tab.waitForExistence(timeout: 15)); tab.tap()
        let more = app.buttons["directory.recent.showAll"]
        for _ in 0..<10 {
            if more.exists && more.isHittable { break }
            app.swipeUp()
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Three latest directory articles without placeholder hero"
        shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.lifetime = .keepAlways; add(tree)
        XCTAssertTrue(app.buttons["directory.recent.preview-3"].exists)
        XCTAssertFalse(app.buttons["directory.recent.preview-4"].exists)
        XCTAssertTrue(more.exists && more.isHittable); more.tap()
        XCTAssertTrue(app.buttons["directory.recent.preview-5"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["directory.recent.showAll"].exists)
        let fifth = app.buttons["directory.recent.preview-5"]
        for _ in 0..<10 {
            if fifth.isHittable { break }
            app.swipeUp()
        }
        let full = XCTAttachment(screenshot: app.screenshot())
        full.name = "Full recent feed includes fifth article"
        full.lifetime = .keepAlways; add(full)
        fifth.tap()
        let target = XCTAttachment(screenshot: app.screenshot())
        target.name = "Opened recent article screen"
        target.lifetime = .keepAlways; add(target)
        XCTAssertTrue(app.staticTexts["Яке у вас житло"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Матеріал більше недоступний"].exists)
        let article = XCTAttachment(screenshot: app.screenshot())
        article.name = "Recent article destination"
        article.lifetime = .keepAlways; add(article)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["directory.recent.preview-5"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["directory.recent.showAll"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["directory.recent.preview-4"].exists)
    }

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
