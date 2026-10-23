import XCTest

@MainActor
final class ActivityHistoryUITests: XCTestCase {
    func testSearchOpenDeleteAndClearInBothLanguages() {
        continueAfterFailure = false
        for language in ["uk", "de"] {
            let app = XCUIApplication()
            app.launchArguments = ["-ui-testing"]
            if language == "de" {
                app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]
            }
            app.launchEnvironment = ["UITestForceOwnerSession": "1", "UITestResetUserSettings": "1",
                "UITestAppLanguage": language, "UITestResetAppLock": "1", "UITestActivityHistory": "1",
                "UITestLegalEvidence": "1", "UITestAppAppearance": language == "de" ? "dark" : "light"]
            app.launch()
            let profile = app.tabBars.buttons.element(boundBy: 4)
            XCTAssertTrue(profile.waitForExistence(timeout: 20)); profile.tap()
            let entry = app.buttons["profile.activityHistory"]
            reveal(entry, app); entry.tap()
            let search = app.textFields["activityHistory.search"]
            XCTAssertTrue(search.waitForExistence(timeout: 8))
            search.tap(); search.typeText("zz-no-match")
            XCTAssertFalse(app.buttons["activityHistory.open.activity-news"].exists)
            capture(app, "history-empty-filter-" + language)
            search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "zz-no-match".count))
            search.typeText("\n")
            capture(app, "history-controls-" + language)
            if language == "de" {
                let filter = app.buttons["activityHistory.filter"].firstMatch
                reveal(filter, app); filter.tap()
                let news = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Neuigkeiten:")).firstMatch
                XCTAssertTrue(news.waitForExistence(timeout: 5)); news.tap()
            } else {
                app.buttons["activityHistory.filter.news"].tap()
            }
            XCTAssertFalse(app.buttons["activityHistory.open.activity-event"].exists)
            let newsRow = app.buttons["activityHistory.open.activity-news"]
            reveal(newsRow, app); newsRow.tap()
            XCTAssertTrue(search.waitForNonExistence(timeout: 5))
            let detailBack = app.buttons["navigation.back"].firstMatch
            XCTAssertTrue(detailBack.waitForExistence(timeout: 8)); detailBack.tap()
            XCTAssertFalse(app.buttons["activityHistory.open.activity-event"].exists)
            if language == "de" {
                let filter = app.buttons["activityHistory.filter"].firstMatch
                reveal(filter, app); filter.tap()
                let all = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Alle:")).firstMatch
                XCTAssertTrue(all.waitForExistence(timeout: 5)); all.tap()
            } else {
                let all = app.buttons["activityHistory.filter.all"]
                reveal(all, app); all.tap()
            }
            for id in ["activity-news", "activity-event", "activity-org"] {
                let row = app.buttons["activityHistory.open." + id]
                reveal(row, app); capture(app, "history-" + id + "-" + language)
                row.tap()
                XCTAssertTrue(search.waitForNonExistence(timeout: 5))
                let back = app.buttons["navigation.back"].firstMatch
                XCTAssertTrue(back.waitForExistence(timeout: 8)); back.tap()
            }
            let remove = app.buttons["activityHistory.delete.activity-news"]
            reveal(remove, app); remove.tap()
            let confirm = app.buttons["activityHistory.delete.confirm"].firstMatch
            XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
            XCTAssertTrue(app.buttons["activityHistory.open.activity-news"].waitForNonExistence(timeout: 8))
            let clear = app.buttons[language == "uk" ? "Очистити історію" : "Verlauf löschen"].firstMatch
            reveal(clear, app); clear.tap()
            let clearConfirm = app.buttons["activityHistory.clear.confirm"].firstMatch
            XCTAssertTrue(clearConfirm.waitForExistence(timeout: 5)); clearConfirm.tap()
            XCTAssertTrue(app.buttons["activityHistory.open.activity-event"].waitForNonExistence(timeout: 8))
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
