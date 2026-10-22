import XCTest
@MainActor final class PublicationControlUITests: XCTestCase {
    func testOwnerOpensControlViewsIssuesHistoryAndActualMaterial() {
        for language in ["uk", "de"] {
            let app = XCUIApplication(); app.launchArguments = ["-ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]
            app.launchEnvironment = ["UITestForceOwnerSession":"1", "UITestPublicationControl":"1", "UITestAppLanguage":language, "UITestAppAppearance":language == "de" ? "dark":"light", "UITestResetUserSettings":"1"]
            app.launch(); XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout:20)); app.tabBars.buttons.element(boundBy:4).tap()
            let link = app.buttons["profile.contentPlanning"].firstMatch; scroll(link,app); link.tap()
            let item = app.buttons["publicationControl.item.news-1"].firstMatch
            XCTAssertTrue(item.waitForExistence(timeout:10)); XCTAssertFalse(app.tabBars.firstMatch.isHittable); capture(app,"control-overview-"+language)
            let issues = app.buttons["publicationControl.tab.issues"].firstMatch; scroll(issues,app); issues.tap(); XCTAssertTrue(issues.isSelected)
            let partial = app.staticTexts[language == "uk" ? "Перевірено частково":"Teilweise geprüft"].firstMatch
            scroll(partial,app); XCTAssertTrue(partial.waitForExistence(timeout:8)); capture(app,"control-issues-"+language)
            app.swipeDown(); let history = app.buttons["publicationControl.tab.history"].firstMatch; scroll(history,app); history.tap(); XCTAssertTrue(history.isSelected)
            XCTAssertTrue(partial.waitForExistence(timeout:8)); capture(app,"control-history-"+language)
            let publications = app.buttons["publicationControl.tab.items"].firstMatch; app.swipeDown(); scroll(publications,app); publications.tap(); XCTAssertTrue(publications.isSelected)
            scroll(item,app); XCTAssertTrue(item.isHittable); item.tap()
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", language == "uk" ? "Громадський центр відкриває" : "Gemeinschaftszentrum startet")).firstMatch.waitForExistence(timeout:8))
            capture(app,"control-material-"+language); app.terminate()
        }
    }
    private func scroll(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<14 {
            if element.exists && element.isHittable && element.frame.minY > app.frame.minY + 90 && element.frame.maxY < app.frame.maxY - 70 { return }
            if element.exists && element.frame.minY < app.frame.minY + 90 { app.swipeDown() } else { app.swipeUp() }
        }
    }
    private func capture(_ app: XCUIApplication, _ name: String) { let a = XCTAttachment(screenshot:app.screenshot()); a.name=name; a.lifetime = .keepAlways; add(a) }
}

extension PublicationControlUITests {
    func testStandardLayoutAndRegionFilter() {
        for language in ["uk", "de"] {
            let app = XCUIApplication(); app.launchArguments = ["-ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
            app.launchEnvironment = ["UITestForceOwnerSession":"1", "UITestPublicationControl":"1", "UITestAppLanguage":language, "UITestAppAppearance":language == "de" ? "dark":"light", "UITestResetUserSettings":"1"]
            app.launch(); XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout:20)); app.tabBars.buttons.element(boundBy:4).tap()
            let link = app.buttons["profile.contentPlanning"].firstMatch; scroll(link,app); link.tap()
            let item = app.buttons["publicationControl.item.news-1"].firstMatch
            XCTAssertTrue(item.waitForExistence(timeout:10)); capture(app,"control-standard-"+language)
            let regions = app.buttons["publicationControl.tab.regions"].firstMatch; scroll(regions,app); regions.tap(); XCTAssertTrue(regions.isSelected)
            let picker = app.buttons["publicationControl.region"].firstMatch; scroll(picker,app); XCTAssertTrue(picker.exists); picker.tap()
            let tirol = app.buttons[language == "uk" ? "Тіроль":"Tirol"].firstMatch
            XCTAssertTrue(tirol.waitForExistence(timeout:5)); tirol.tap()
            XCTAssertFalse(app.staticTexts[language == "uk" ? "Уся Австрія":"Ganz Österreich"].firstMatch.exists)
            capture(app,"control-region-filter-"+language); app.terminate()
        }
    }
}
