import XCTest

@MainActor
final class SharedControlsUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testPublicationKeepsIncompleteReportWarningVisibleAfterRetry() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launchEnvironment = ["UITestForceOwnerSession": "1", "UITestPublicationControl": "1",
            "UITestPublicationSyncErrors": "2", "UITestAppLanguage": "uk", "UITestAppAppearance": "dark",
            "UITestResetUserSettings": "1", "UITestResetAppLock": "1"]
        app.launch()
        let profile = app.tabBars.buttons.element(boundBy: 4)
        XCTAssertTrue(profile.waitForExistence(timeout: 20)); profile.tap()
        let entry = app.buttons["profile.contentPlanning"]
        reveal(entry, app); entry.tap()
        let warning = app.staticTexts["publicationControl.syncWarning"]
        reveal(warning, app)
        let count = app.staticTexts["publicationControl.syncWarning.count"]
        XCTAssertTrue(count.label.contains("2"))
        let retry = app.buttons["publicationControl.syncWarning.retry"]
        reveal(retry, app); retry.tap()
        XCTAssertTrue(warning.waitForExistence(timeout: 8))
        XCTAssertTrue(count.label.contains("2"))
        capture(app, "publication-incomplete-reports-after-retry")
        app.terminate()
    }

    func testSharedSearchClearsAndDismissesKeyboardInBothAppearances() {
        for language in ["uk", "de"] {
            let app = XCUIApplication()
            app.launchArguments = ["-ui-testing"]
            if language == "de" {
                app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]
            }
            app.launchEnvironment = ["UITestForceOwnerSession": "1", "UITestResetUserSettings": "1",
                "UITestResetAppLock": "1", "UITestAppLanguage": language,
                "UITestAppAppearance": language == "de" ? "dark" : "light"]
            app.launch()
            let profile = app.tabBars.buttons.element(boundBy: 4)
            XCTAssertTrue(profile.waitForExistence(timeout: 20)); profile.tap()
            let entry = app.buttons["profile.moderation"]
            reveal(entry, app); entry.tap()
            let search = app.textFields["content.moderation.search"]
            reveal(search, app)
            search.tap(); search.typeText("zz-no-match")
            let clear = app.buttons["content.moderation.search.clear"]
            XCTAssertTrue(clear.waitForExistence(timeout: 5)); clear.tap()
            XCTAssertFalse((search.value as? String ?? "").contains("zz-no-match"))
            search.tap(); search.typeText("zz-no-match\n")
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
            // The AX text glyph frame can be 22 points even when its container
            // is 44. Verify the padded hit area through its actual behavior.
            search.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
                .withOffset(CGVector(dx: 0, dy: -4)).tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            capture(app, "shared-search-" + language)
            app.terminate()
        }
    }

    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<18 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
}
