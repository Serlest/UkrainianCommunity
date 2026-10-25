import XCTest

@MainActor
final class AuditClosureNavigationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testUniqueNavigationFamiliesRestoreRootsAndKeepTabPolicy() {
        let app = launch(owner: true)
        app.tabBars.buttons.element(boundBy: 4).tap()
        // Ordinary pushed profile destinations keep the root tab bar.
        open("profile.savedContent", app)
        XCTAssertTrue(app.tabBars.firstMatch.isHittable); capture(app, "navigation-personal-push")
        back(app)
        open("profile.settings.open", app)
        XCTAssertTrue(app.tabBars.firstMatch.isHittable); capture(app, "navigation-settings-push")
        back(app)
        // Modal editors cannot leave an interactive root bar under the form.
        open("profile.edit.open", app)
        XCTAssertTrue(app.buttons["profile.edit.save"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.tabBars.firstMatch.isHittable); capture(app, "navigation-modal-editor")
        app.buttons["editor.close"].firstMatch.tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 8))
        // Both administrative shell families deliberately hide the bar.
        for route in ["profile.userManagement", "profile.directoryEditors", "profile.contentPlanning"] {
            open(route, app)
            XCTAssertTrue(app.buttons["navigation.back"].firstMatch.waitForExistence(timeout: 8))
            capture(app, "navigation-admin-" + route)
            expectation(for: NSPredicate(format: "isHittable == false"), evaluatedWith: app.tabBars.firstMatch)
            waitForExpectations(timeout: 5)
            back(app); XCTAssertTrue(app.tabBars.firstMatch.isHittable)
        }
        // Directory editing is pushed, so leaving its nested editor must restore
        // the catalog's tab policy, not just dismiss an unrelated sheet.
        app.tabBars.buttons.element(boundBy: 3).tap()
        open("directory.manage", app)
        open("directory.category.manage.first-steps", app)
        XCTAssertTrue(app.buttons["directory.category.publish"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.tabBars.firstMatch.isHittable); capture(app, "navigation-directory-pushed-editor")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.tabBars.firstMatch.isHittable)
        for index in 0..<5 {
            app.tabBars.buttons.element(boundBy: index).tap()
            XCTAssertTrue(app.tabBars.buttons.element(boundBy: index).isSelected)
        }
        capture(app, "navigation-all-roots-restored")
        app.terminate()
        let member = launch(owner: false)
        member.tabBars.buttons.element(boundBy: 4).tap()
        XCTAssertTrue(member.buttons["profile.savedContent"].waitForExistence(timeout: 8))
        for id in ["profile.userManagement", "profile.directoryEditors"] { XCTAssertFalse(member.buttons[id].exists) }
        open("profile.savedContent", member); XCTAssertTrue(member.tabBars.firstMatch.isHittable)
        back(member); capture(member, "navigation-restricted-member-positive-root")
        member.terminate()
    }

    private func launch(owner: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launchEnvironment = ["UITestResetUserSettings":"1", "UITestResetAppLock":"1", "UITestResetContentDrafts":"1",
            "UITestDirectoryRecentPreview":"1", "UITestAppLanguage":"uk", "UITestAppAppearance":"light", "UITestDirectoryAccess":"1", "UITestUserRefresh":"1", "UITestPublicationControl":"1"]
        if owner { app.launchEnvironment["UITestForceOwnerSession"] = "1" }
        else { app.launchEnvironment["UITestProfileRole"] = "member" }
        app.launch(); XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20)); return app
    }
    private func open(_ id: String, _ app: XCUIApplication) {
        let element = app.buttons[id].firstMatch
        for _ in 0..<24 {
            if element.exists && element.isHittable && element.frame.midY > 60 && element.frame.midY < app.frame.height - 90 { element.tap(); return }
            if element.exists && element.frame.midY < 60 { app.swipeDown() }
            else { app.swipeUp() }
        }
        XCTFail("Unreachable route " + id)
    }
    private func back(_ app: XCUIApplication) { app.buttons["navigation.back"].firstMatch.tap() }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name
        attachment.lifetime = .keepAlways; add(attachment)
    }
}
