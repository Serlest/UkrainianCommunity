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
            scroll(partial,app); XCTAssertTrue(partial.waitForExistence(timeout:8)); capture(app,"control-history-"+language)
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
            let tirol = app.buttons["publicationControl.region.tirol"].firstMatch
            scroll(tirol,app); XCTAssertTrue(tirol.waitForExistence(timeout:5)); tirol.tap()
            XCTAssertFalse(app.staticTexts[language == "uk" ? "Уся Австрія":"Ganz Österreich"].firstMatch.exists)
            capture(app,"control-region-filter-"+language); app.terminate()
        }
    }
}

extension PublicationControlUITests {
    func testLargestTextDateSheetAndEmptyRegionalHistory() {
        for language in ["uk", "de"] {
            let app = XCUIApplication()
            app.launchArguments = ["-ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            app.launchEnvironment = ["UITestForceOwnerSession":"1", "UITestPublicationControl":"1", "UITestPublicationSyncErrors":"42", "UITestAppLanguage":language, "UITestAppAppearance":language == "de" ? "dark":"light", "UITestResetUserSettings":"1"]
            app.launch(); XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout:20)); app.tabBars.buttons.element(boundBy:4).tap()
            let link = app.buttons["profile.contentPlanning"].firstMatch; scroll(link,app); link.tap()
            let date = app.buttons["publicationControl.day"].firstMatch
            XCTAssertTrue(date.waitForExistence(timeout:10)); scroll(date,app)
            XCTAssertLessThanOrEqual(date.frame.maxX,app.frame.maxX); XCTAssertGreaterThanOrEqual(date.frame.minX,app.frame.minX)
            let metric = app.staticTexts["publicationControl.metric.newspaper"].firstMatch
            scroll(metric,app)
            XCTAssertTrue(metric.isHittable); XCTAssertLessThanOrEqual(metric.frame.maxX,app.frame.maxX)
            capture(app,"control-largest-metrics-"+language)
            scroll(date,app)
            capture(app,"control-largest-summary-"+language)
            date.tap(); let done = app.buttons["publicationControl.calendar.done"]
            XCTAssertTrue(done.waitForExistence(timeout:5)); capture(app,"control-largest-date-"+language); done.tap()
            let history = app.buttons["publicationControl.tab.history"].firstMatch; scroll(history,app); history.tap()
            let picker = app.buttons["publicationControl.region"].firstMatch; scroll(picker,app); picker.tap()
            let unknown = app.buttons["publicationControl.region.unknown"].firstMatch
            scroll(unknown,app)
            XCTAssertTrue(unknown.waitForExistence(timeout:5)); unknown.tap()
            let empty = app.staticTexts[language == "uk" ? "За цим регіоном звітів немає":"Für diese Region liegen keine Berichte vor"].firstMatch
            scroll(empty,app); XCTAssertTrue(empty.waitForExistence(timeout:8)); capture(app,"control-empty-regional-history-"+language)
            app.terminate()
        }
    }
}

extension PublicationControlUITests {
    func testEventDestinationAndRemovedMaterial() {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing"]
        app.launchEnvironment = ["UITestForceOwnerSession":"1", "UITestPublicationControl":"1", "UITestAppLanguage":"de", "UITestResetUserSettings":"1"]
        app.launch(); XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout:20)); app.tabBars.buttons.element(boundBy:4).tap()
        let link = app.buttons["profile.contentPlanning"].firstMatch; scroll(link,app); link.tap()
        let removed = app.buttons["publicationControl.item.removed"].firstMatch; scroll(removed,app)
        XCTAssertTrue(removed.exists); XCTAssertFalse(removed.isEnabled)
        let event = app.buttons["publicationControl.item.event-1"].firstMatch; scroll(event,app); event.tap()
        XCTAssertTrue(app.staticTexts["Ukrainischer Gemeinschaftsabend"].firstMatch.waitForExistence(timeout:10))
        capture(app,"control-event-destination"); app.terminate()
    }
}

extension PublicationControlUITests {
    func testLargestRegionLabelKeepsItsFullText() {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launchEnvironment = ["UITestForceOwnerSession":"1", "UITestPublicationControl":"1", "UITestAppLanguage":"de", "UITestAppAppearance":"dark", "UITestResetUserSettings":"1"]
        app.launch(); XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout:20)); app.tabBars.buttons.element(boundBy:4).tap()
        let link = app.buttons["profile.contentPlanning"].firstMatch; scroll(link,app); link.tap()
        let history = app.buttons["publicationControl.tab.history"].firstMatch; scroll(history,app); history.tap()
        let filter = app.buttons["publicationControl.region"].firstMatch; scroll(filter,app); filter.tap()
        let unknown = app.buttons["publicationControl.region.unknown"].firstMatch; scroll(unknown,app); XCTAssertTrue(unknown.isHittable); unknown.tap()
        scroll(filter,app); XCTAssertTrue(filter.label.contains("Region nicht angegeben")); XCTAssertGreaterThan(filter.frame.height,50)
        XCTAssertLessThanOrEqual(filter.frame.maxX,app.frame.maxX); capture(app,"control-full-region-label-largest-de")
        app.terminate()
    }
    func testCalendarCancelAndConfirmKeepSelectedDay() {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launchEnvironment = ["UITestForceOwnerSession":"1", "UITestPublicationControl":"1", "UITestAppLanguage":"de", "UITestResetUserSettings":"1"]
        app.launch(); XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout:20)); app.tabBars.buttons.element(boundBy:4).tap()
        let link = app.buttons["profile.contentPlanning"].firstMatch; scroll(link,app); link.tap()
        let date = app.buttons["publicationControl.day"].firstMatch; XCTAssertTrue(date.waitForExistence(timeout:10)); let initial = date.label
        var calendar = Calendar(identifier:.gregorian); calendar.timeZone = TimeZone(identifier:"Europe/Vienna")!
        let today = calendar.component(.day,from:Date()), target = max(1,today-1)
        func choose() {
            let done = app.buttons["publicationControl.calendar.done"]; XCTAssertTrue(done.waitForExistence(timeout:5))
            let cell = app.buttons.matching(NSPredicate(format:"label MATCHES %@", ".*(?<![0-9])\(target)(?![0-9]).*")).firstMatch
            XCTAssertTrue(cell.waitForExistence(timeout:5)); cell.tap()
        }
        date.tap(); choose(); app.buttons["Abbrechen"].firstMatch.tap(); XCTAssertEqual(date.label,initial)
        date.tap(); choose(); app.buttons["publicationControl.calendar.done"].tap()
        if today>1 { XCTAssertNotEqual(date.label,initial) }
        let selected = date.label; date.tap(); XCTAssertTrue(app.buttons["publicationControl.calendar.done"].waitForExistence(timeout:5))
        capture(app,"control-calendar-selected-day-de"); app.buttons["publicationControl.calendar.done"].tap(); XCTAssertEqual(date.label,selected)
        app.terminate()
    }
}
