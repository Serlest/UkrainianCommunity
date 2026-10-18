import XCTest

@MainActor
final class HeaderGlassUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testDetailHeaderControlsMatchInLightAndDarkAndMenusOpen() {
        for appearance in ["light", "dark"] {
            for kind in ["news", "events", "organizations"] {
                let app = openDetail(kind, appearance: appearance)
                let back = app.buttons["navigation.back"].firstMatch
                let bookmark = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "detail.header.action.bookmark")).firstMatch
                let share = app.buttons["detail.header.share"].firstMatch
                let more = app.buttons["detail.header.more-actions"].firstMatch
                for control in [back, bookmark, share, more] {
                    XCTAssertTrue(control.waitForExistence(timeout: 8))
                    XCTAssertTrue(control.isHittable)
                    XCTAssertGreaterThanOrEqual(control.frame.width, 44)
                    XCTAssertGreaterThanOrEqual(control.frame.height, 44)
                    XCTAssertEqual(control.frame.height, back.frame.height, accuracy: 1)
                    XCTAssertEqual(control.frame.width, back.frame.width, accuracy: 1)
                }
                capture("header-\(kind)-\(appearance)", app: app)
                more.tap()
                XCTAssertTrue(app.buttons["Melden"].waitForExistence(timeout: 5))
                capture("menu-\(kind)-\(appearance)", app: app)
                app.terminate()
            }
        }
    }

    func testShareStillOpensSystemActivitySheet() {
        let app = openDetail("news", appearance: "dark")
        let share = app.buttons["detail.header.share"].firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 8)); share.tap()
        let activity = app.otherElements["ActivityListView"].firstMatch
        XCTAssertTrue(activity.waitForExistence(timeout: 8) || app.sheets.firstMatch.exists)
        capture("header-share-system-sheet", app: app)
        app.terminate()
    }

    private func openDetail(_ kind: String, appearance: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-selectedAppAppearance", appearance]
        app.launchEnvironment = ["UITestForceAuthenticatedSession": "1", "UITestResetUserSettings": "1",
            "UITestAppLanguage": "de", "UITestResetAppLock": "1"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        let index = kind == "events" ? 1 : (kind == "organizations" ? 2 : 0)
        app.tabBars.buttons.element(boundBy: index).tap()
        if kind == "news" {
            let bell = app.buttons["notificationInbox.bell"].firstMatch
            XCTAssertTrue(bell.waitForExistence(timeout: 8))
            XCTAssertTrue(bell.isHittable)
            XCTAssertGreaterThanOrEqual(bell.frame.width, 44)
            XCTAssertGreaterThanOrEqual(bell.frame.height, 44)
            capture("header-home-\(appearance)", app: app)
        }
        let id = kind == "events" ? "event.card.event-1"
            : (kind == "organizations" ? "organization.card.org-1" : "home.card.news-news-1")
        let card = app.buttons[id].firstMatch
        for _ in 0..<8 {
            if card.exists && card.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(card.exists && card.isHittable); card.tap()
        return app
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
