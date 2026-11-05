import XCTest

@MainActor final class ContentSharingUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testNewsAndEventSystemShareSheetsInBothLanguages() {
        for language in ["uk", "de"] {
            for event in [false, true] {
                let app = XCUIApplication()
                app.launchArguments = ["-ui-testing"]
                app.launchEnvironment = ["UITestResetUserSettings": "1", "UITestResetAppLock": "1",
                    "UITestAppLanguage": language, "UITestAppAppearance": language == "uk" ? "light" : "dark",
                    "UITestForceGuestSession": "1", event ? "UITestEventsAudit" : "UITestNewsAudit": "1"]
                app.launch()
                XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
                if event { app.tabBars.buttons.element(boundBy: 1).tap() }
                let card = app.descendants(matching: .any).matching(identifier:
                    event ? "event.card.audit-event-own" : "home.card.news-audit-own").firstMatch
                XCTAssertTrue(card.waitForExistence(timeout: 10))
                for _ in 0..<8 where !card.isHittable { app.swipeUp() }
                card.tap()
                let share = app.buttons["detail.header.share"].firstMatch
                XCTAssertTrue(share.waitForExistence(timeout: 8)); XCTAssertTrue(share.isHittable)
                share.tap()
                let copy = app.cells.matching(NSPredicate(format: "label IN %@", ["Copy", "Kopieren", "Скопіювати", "Копіювати"])).firstMatch
                XCTAssertTrue(copy.waitForExistence(timeout: 8), app.debugDescription)
                let image = XCTAttachment(screenshot: app.screenshot())
                image.name = "share-\(event ? "event" : "news")-\(language)"; image.lifetime = .keepAlways; add(image)
                let tree = XCTAttachment(string: app.debugDescription)
                tree.name = (image.name ?? "share") + "-accessibility"; tree.lifetime = .keepAlways; add(tree)
                // Copy exercises a real receiver without sending test content to anyone.
                copy.tap()
                XCTAssertTrue(copy.waitForNonExistence(timeout: 5))
                XCTAssertTrue(share.isHittable)
                app.buttons["navigation.back"].firstMatch.tap()
                XCTAssertTrue(card.waitForExistence(timeout: 8))
                app.terminate()
            }
        }
    }
}
