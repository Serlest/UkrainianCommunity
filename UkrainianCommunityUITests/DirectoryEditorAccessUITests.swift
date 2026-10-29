import XCTest

@MainActor final class DirectoryEditorAccessUITests: XCTestCase {
    func testGrantAndRevokeWithLongIdentityInUkrainianAndGerman() {
        for language in ["uk", "de"] {
            let app = XCUIApplication()
            app.launchArguments = ["-ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]
            app.launchEnvironment = ["UITestForceOwnerSession":"1", "UITestDirectoryAccess":"1", "UITestAppLanguage":language, "UITestAppAppearance":language == "de" ? "dark":"light", "UITestResetUserSettings":"1", "UITestResetAppLock":"1"]
            app.launch()
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout:20))
            app.tabBars.buttons.element(boundBy:4).tap()
            let link = app.buttons["profile.directoryEditors"].firstMatch
            scroll(link, app:app); XCTAssertTrue(link.isHittable); link.tap()
            let revoke = app.buttons["directoryAccess.revoke.directory-member-0"].firstMatch
            XCTAssertTrue(revoke.waitForExistence(timeout:10))
            XCTAssertFalse(app.tabBars.firstMatch.isHittable)
            capture(app, "directory-access-top-" + language)
            scroll(revoke,app:app); revoke.tap()
            let revokeConfirm = app.sheets.buttons[language == "uk" ? "Відкликати доступ":"Zugriff entziehen"].firstMatch
            XCTAssertTrue(revokeConfirm.waitForExistence(timeout:5)); revokeConfirm.tap()
            XCTAssertTrue(revoke.waitForNonExistence(timeout:5))
            let search = app.textFields["directoryAccess.search"].firstMatch
            scroll(search, app:app); XCTAssertTrue(search.isHittable); search.tap(); search.typeText("Candidate 1")
            let grant = app.buttons["directoryAccess.grant.directory-member-1"].firstMatch
            scroll(grant, app:app); XCTAssertTrue(grant.waitForExistence(timeout:8))
            capture(app,"directory-access-search-" + language)
            // Dismiss the keyboard through the Return key before opening confirmation.
            search.typeText("\n")
            scroll(grant,app:app); grant.tap()
            let confirm = app.sheets.buttons[language == "uk" ? "Надати доступ":"Zugriff erteilen"].firstMatch
            XCTAssertTrue(confirm.waitForExistence(timeout:5)); confirm.tap()
            let status = app.staticTexts[language == "uk" ? "Має доступ":"Zugriff aktiv"].firstMatch
            XCTAssertTrue(status.waitForExistence(timeout:8))
            capture(app,"directory-access-granted-" + language)
            let back = app.buttons["navigation.back"].firstMatch
            for _ in 0..<20 {
                if back.isHittable { break }
                app.swipeDown()
            }
            XCTAssertTrue(back.isHittable); back.tap()
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
            XCTAssertTrue(app.tabBars.firstMatch.isHittable)
            app.terminate()
        }
    }
    private func capture(_ app: XCUIApplication, _ name: String) { let attachment = XCTAttachment(screenshot:app.screenshot()); attachment.name=name; attachment.lifetime = .keepAlways; add(attachment) }
    private func scroll(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<14 {
            if element.exists && element.isHittable && element.frame.maxY < app.frame.maxY - 80 { return }
            app.swipeUp()
        }
    }
}

extension DirectoryEditorAccessUITests {
    func testStandardTextShowsIdentityDateAndControls() {
        for language in ["uk", "de"] {
            let app = XCUIApplication()
            app.launchArguments = ["-ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
            app.launchEnvironment = ["UITestForceOwnerSession":"1", "UITestDirectoryAccess":"1", "UITestAppLanguage":language, "UITestAppAppearance":language == "de" ? "dark":"light", "UITestResetUserSettings":"1", "UITestResetAppLock":"1"]
            app.launch(); XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout:20)); app.tabBars.buttons.element(boundBy:4).tap()
            let link = app.buttons["profile.directoryEditors"].firstMatch
            scroll(link,app:app); link.tap()
            let revoke = app.buttons["directoryAccess.revoke.directory-member-0"].firstMatch
            XCTAssertTrue(revoke.waitForExistence(timeout:10)); scroll(revoke,app:app)
            XCTAssertTrue(revoke.isHittable)
            capture(app,"directory-access-standard-" + language)
            app.terminate()
        }
    }
}
