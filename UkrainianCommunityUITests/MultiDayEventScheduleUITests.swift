import XCTest

final class MultiDayEventScheduleUITests: XCTestCase {
    @MainActor
    func testHackathonGermanSchedule() throws {
        try verify(scenario: "hackathon", language: "de", largeText: false)
    }

    @MainActor
    func testMarktplatzGermanSchedule() throws {
        try verify(scenario: "marktplatz", language: "de", largeText: false)
    }

    @MainActor
    func testHackathonUkrainianScheduleAtAX5() throws {
        try verify(scenario: "hackathon", language: "uk", largeText: true)
    }

    @MainActor
    func testMarktplatzGermanScheduleAtAX5() throws {
        try verify(scenario: "marktplatz", language: "de", largeText: true)
    }

    @MainActor
    private func verify(scenario: String, language: String, largeText: Bool) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launchEnvironment["UITestResetUserSettings"] = "1"
        app.launchEnvironment["UITestForceGuestSession"] = "1"
        app.launchEnvironment["UITestAppLanguage"] = language
        app.launchEnvironment["UITestMultiDayEventSchedule"] = scenario
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        defer { app.terminate() }

        let tab = app.descendants(matching: .any).matching(identifier: "tab.events").firstMatch
        if tab.waitForExistence(timeout: 10) && tab.isHittable {
            tab.tap()
        } else {
            let fallback = app.tabBars.buttons[language == "de" ? "Veranstaltungen" : "Події"].firstMatch
            XCTAssertTrue(fallback.waitForExistence(timeout: 10))
            fallback.tap()
        }
        let card = app.descendants(matching: .any).matching(identifier: "event.card.schedule-\(scenario)").firstMatch
        reveal(card, in: app)
        let endpoints = expectedEndpoints(scenario: scenario, language: language)
        XCTAssertTrue(card.label.contains(endpoints.start), "Feed must include the full start: \(card.label)")
        XCTAssertTrue(card.label.contains(endpoints.end), "Feed must include the full end: \(card.label)")
        capture("\(scenario)-\(language)-feed-AX\(largeText)", app: app)
        card.tap()

        let header = app.descendants(matching: .any).matching(identifier: "event.schedule.header").firstMatch
        reveal(header, in: app)
        XCTAssertTrue(header.label.contains(endpoints.start), header.label)
        XCTAssertTrue(header.label.contains(endpoints.end), header.label)
        assertHorizontalBounds(header, in: app)
        capture("\(scenario)-\(language)-header-AX\(largeText)", app: app)

        for (name, expected) in [("start", endpoints.start), ("end", endpoints.end)] {
            let row = app.descendants(matching: .any).matching(identifier: "event.schedule.\(name).schedule-\(scenario)").firstMatch
            reveal(row, in: app)
            XCTAssertTrue(row.label.contains(expected), row.label)
            assertHorizontalBounds(row, in: app)
            capture("\(scenario)-\(language)-\(name)-AX\(largeText)", app: app)
        }
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        _ = element.waitForExistence(timeout: 10)
        for _ in 0..<16 {
            if element.exists && element.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable, "Missing or unreachable: \(element)")
    }

    @MainActor
    private func assertHorizontalBounds(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertGreaterThanOrEqual(element.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(element.frame.maxX, app.frame.maxX)
    }

    @MainActor
    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func expectedEndpoints(scenario: String, language: String) -> (start: String, end: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Vienna")!
        let start = calendar.date(from: scenario == "hackathon"
            ? DateComponents(year: 2026, month: 9, day: 11, hour: 9)
            : DateComponents(year: 2026, month: 11, day: 13, hour: 11))!
        let end = calendar.date(from: scenario == "hackathon"
            ? DateComponents(year: 2026, month: 9, day: 12, hour: 16)
            : DateComponents(year: 2026, month: 12, day: 23, hour: 21))!
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language)
        // Match the app's device-local display, while fixture timestamps remain Vienna-based.
        formatter.timeZone = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return (formatter.string(from: start), formatter.string(from: end))
    }
}
