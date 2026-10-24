import XCTest

final class RootTabHeaderAlignmentUITests: XCTestCase {
    @MainActor
    func testGuestCanSelectAllFiveRootTabs() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launchEnvironment = ["UITestForceGuestSession": "1", "UITestResetUserSettings": "1",
                                 "UITestAppLanguage": "uk", "UITestResetAppLock": "1"]
        app.launch()
        let tabs = app.tabBars.buttons
        XCTAssertTrue(tabs.element(boundBy: 0).waitForExistence(timeout: 20))
        XCTAssertEqual(tabs.count, 5)
        for index in 0..<5 {
            let tab = tabs.element(boundBy: index)
            XCTAssertTrue(tab.isHittable)
            tab.tap()
            XCTAssertTrue(tab.isSelected)
        }
        app.terminate()
    }

    @MainActor
    func testRootDestinationsForAdminAndEveryOrganizationRole() {
        let screens = ["screen.home", "screen.events", "screen.organizations", "screen.directory", "screen.profile"]
        for role in ["admin", "org-owner", "org-admin", "org-moderator", "mixed"] {
            let app = XCUIApplication()
            app.launchArguments = ["-ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
            app.launchEnvironment = ["UITestProfileRole": role, "UITestResetUserSettings": "1",
                "UITestAppLanguage": "uk", "UITestAppAppearance": "dark", "UITestResetAppLock": "1"]
            app.launch()
            let tabs = app.tabBars.buttons
            XCTAssertTrue(tabs.element(boundBy: 0).waitForExistence(timeout: 20))
            XCTAssertEqual(tabs.count, 5)
            for (index, screen) in screens.enumerated() {
                let tab = tabs.element(boundBy: index)
                XCTAssertTrue(tab.isHittable); tab.tap(); XCTAssertTrue(tab.isSelected)
                XCTAssertTrue(app.descendants(matching: .any).matching(identifier: screen).firstMatch.waitForExistence(timeout: 8), role + ": " + screen)
            }
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "root-navigation-" + role; shot.lifetime = .keepAlways; add(shot)
            app.terminate()
        }
    }

    @MainActor
    func testBrandHeaderKeepsSameVerticalPositionAcrossTabs() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launchEnvironment["UITestResetUserSettings"] = "1"
        app.launchEnvironment["UITestAppLanguage"] = "de"
        app.launchEnvironment["UITestForceAuthenticatedSession"] = "1"
        app.launchEnvironment["UITestResetAppLock"] = "1"
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 20))
        let brand = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Ukrainian Community"))
            .firstMatch
        XCTAssertTrue(brand.waitForExistence(timeout: 20))
        let newsTop = brand.frame.minY

        XCTAssertEqual(tabBar.buttons.count, 5)
        for (index, name) in ["Nachrichten", "Termine", "Organisation", "Ratgeber", "Profil"].enumerated() {
            let tab = tabBar.buttons.element(boundBy: index)
            XCTAssertTrue(tab.isHittable)
            tab.tap()
            XCTAssertTrue(tab.isSelected)
            XCTAssertTrue(brand.waitForExistence(timeout: 10), "Missing brand header on \(name)")
            XCTAssertEqual(brand.frame.minY, newsTop, accuracy: 2, "Header offset on \(name)")
        }
    }
}
