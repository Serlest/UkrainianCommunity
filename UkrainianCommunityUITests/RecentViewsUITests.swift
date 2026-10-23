import XCTest

@MainActor
final class RecentViewsUITests: XCTestCase {
    func testSearchOpenDeleteAndClearInBothLanguages() {
        continueAfterFailure = false
        for language in ["uk", "de"] {
            let app = XCUIApplication()
            app.launchArguments = ["-ui-testing"]
            if language == "de" {
                app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]
            }
            app.launchEnvironment = ["UITestForceOwnerSession": "1", "UITestResetUserSettings": "1",
                "UITestAppLanguage": language, "UITestResetAppLock": "1", "UITestRecentViews": "1",
                "UITestLegalEvidence": "1", "UITestAppAppearance": language == "de" ? "dark" : "light"]
            app.launch()
            let profile = app.tabBars.buttons.element(boundBy: 4)
            XCTAssertTrue(profile.waitForExistence(timeout: 20)); profile.tap()
            let entry = app.buttons["profile.recentViews"]
            reveal(entry, app); entry.tap()
            let search = app.textFields["recentViews.search"]
            XCTAssertTrue(search.waitForExistence(timeout: 8))
            search.tap(); search.typeText("zz-no-match")
            XCTAssertFalse(app.buttons["recentViews.open.news_news-1"].exists)
            capture(app, "history-empty-filter-" + language)
            search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "zz-no-match".count))
            search.typeText("\n")
            capture(app, "history-controls-" + language)
            if language == "de" {
                let filter = app.buttons["recentViews.filter"].firstMatch
                reveal(filter, app); filter.tap()
                let news = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Neuigkeiten:")).firstMatch
                XCTAssertTrue(news.waitForExistence(timeout: 5)); news.tap()
            } else {
                app.buttons["recentViews.filter.news"].tap()
            }
            XCTAssertFalse(app.buttons["recentViews.open.event_event-1"].exists)
            let newsRow = app.buttons["recentViews.open.news_news-1"]
            reveal(newsRow, app); newsRow.tap()
            XCTAssertTrue(search.waitForNonExistence(timeout: 5))
            let detailBack = app.buttons["navigation.back"].firstMatch
            XCTAssertTrue(detailBack.waitForExistence(timeout: 8)); detailBack.tap()
            XCTAssertFalse(app.buttons["recentViews.open.event_event-1"].exists)
            if language == "de" {
                let filter = app.buttons["recentViews.filter"].firstMatch
                reveal(filter, app); filter.tap()
                let all = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Alle:")).firstMatch
                XCTAssertTrue(all.waitForExistence(timeout: 5)); all.tap()
            } else {
                let all = app.buttons["recentViews.filter.all"]
                reveal(all, app); all.tap()
            }
            for id in ["news_news-1", "event_event-1", "organization_org-1"] {
                let row = app.buttons["recentViews.open." + id]
                reveal(row, app); capture(app, "history-" + id + "-" + language)
                row.tap()
                XCTAssertTrue(search.waitForNonExistence(timeout: 5))
                let back = app.buttons["navigation.back"].firstMatch
                XCTAssertTrue(back.waitForExistence(timeout: 8)); back.tap()
            }
            let remove = app.buttons["recentViews.delete.news_news-1"]
            reveal(remove, app); remove.tap()
            let confirm = app.buttons["recentViews.delete.confirm"].firstMatch
            XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
            XCTAssertTrue(app.buttons["recentViews.open.news_news-1"].waitForNonExistence(timeout: 8))
            let clear = app.buttons[language == "uk" ? "Очистити історію" : "Verlauf löschen"].firstMatch
            reveal(clear, app); clear.tap()
            let clearConfirm = app.buttons["recentViews.clear.confirm"].firstMatch
            XCTAssertTrue(clearConfirm.waitForExistence(timeout: 5)); clearConfirm.tap()
            XCTAssertTrue(app.buttons["recentViews.open.event_event-1"].waitForNonExistence(timeout: 8))
            capture(app, "history-cleared-" + language)
            app.terminate()
        }
    }
    private func reveal(_ item: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<24 {
            if item.exists && item.isHittable { return }
            let upward = !item.exists || item.frame.midY > app.frame.midY
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: upward ? 0.8 : 0.3))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: upward ? 0.3 : 0.8)))
        }
        XCTFail("Cannot reach \(item): \(app.debugDescription)")
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
