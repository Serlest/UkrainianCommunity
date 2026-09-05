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
        capture("\(scenario)-\(language)-feed-AX\(largeText)", element: card, app: app)
        card.tap()

        let header = app.descendants(matching: .any).matching(identifier: "event.schedule.header").firstMatch
        reveal(header, in: app)
        XCTAssertTrue(header.label.contains(endpoints.start), header.label)
        XCTAssertTrue(header.label.contains(endpoints.end), header.label)
        XCTAssertEqual(header.label, "\(endpoints.start) – \(endpoints.end)", "The interval must be one accessibility label, without the decorative calendar name")
        assertHorizontalBounds(header, in: app)
        capture("\(scenario)-\(language)-header-AX\(largeText)", element: header, app: app)

        for (name, expected) in [("start", endpoints.start), ("end", endpoints.end)] {
            let row = app.descendants(matching: .any).matching(identifier: "event.schedule.\(name).schedule-\(scenario)").firstMatch
            reveal(row, in: app)
            XCTAssertTrue(row.label.contains(expected), row.label)
            assertHorizontalBounds(row, in: app)
            capture("\(scenario)-\(language)-\(name)-AX\(largeText)", element: row, app: app)
        }
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        _ = element.waitForExistence(timeout: 10)
        for _ in 0..<24 {
            guard element.exists else {
                app.swipeUp()
                continue
            }
            let viewport = captureViewport(in: app)
            let frame = element.frame
            let fits = frame.height <= viewport.height
            // A hittable edge is insufficient. Fit the whole element, or align the
            // start of a tall element so capture can record all successive slices.
            let displacement: CGFloat
            if frame.minY < viewport.minY {
                displacement = frame.minY - viewport.minY
            } else if fits && frame.maxY > viewport.maxY {
                displacement = frame.maxY - viewport.maxY
            } else if !fits && frame.minY > viewport.minY + 4 {
                displacement = frame.minY - viewport.minY
            } else {
                break
            }
            scrollContent(upBy: displacement, in: app)
        }
        XCTAssertTrue(element.exists && element.isHittable, "Missing or unreachable: \(element)")
        let viewport = captureViewport(in: app)
        if element.frame.height <= viewport.height {
            XCTAssertGreaterThanOrEqual(element.frame.minY, viewport.minY - 4, "Top is obscured")
            XCTAssertLessThanOrEqual(element.frame.maxY, viewport.maxY + 4, "Bottom is obscured")
        }
    }

    @MainActor
    private func captureViewport(in app: XCUIApplication) -> CGRect {
        let frame = app.frame
        // Reserve safe areas and the floating navigation/tab controls. Include
        // native bars when available; floating app controls may not expose a bar.
        let nav = app.navigationBars.firstMatch
        let tabs = app.tabBars.firstMatch
        let top = max(frame.minY + 100, nav.exists ? nav.frame.maxY + 8 : frame.minY)
        let bottom = min(frame.maxY - 100, tabs.exists ? tabs.frame.minY - 8 : frame.maxY)
        return CGRect(x: frame.minX, y: top, width: frame.width, height: max(1, bottom - top))
    }

    @MainActor
    private func scrollContent(upBy displacement: CGFloat, in app: XCUIApplication) {
        let viewport = captureViewport(in: app)
        let distance = min(abs(displacement), viewport.height * 0.4)
        let startY = displacement > 0 ? viewport.midY + distance / 2 : viewport.midY - distance / 2
        let endY = displacement > 0 ? startY - distance : startY + distance
        let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        let start = origin.withOffset(CGVector(dx: viewport.midX - app.frame.minX, dy: startY - app.frame.minY))
        let end = origin.withOffset(CGVector(dx: viewport.midX - app.frame.minX, dy: endY - app.frame.minY))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    @MainActor
    private func assertHorizontalBounds(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertGreaterThanOrEqual(element.frame.minX, app.frame.minX)
        XCTAssertLessThanOrEqual(element.frame.maxX, app.frame.maxX)
    }

    @MainActor
    private func capture(_ name: String, element: XCUIElement, app: XCUIApplication) {
        // Tall AX5 cards cannot fit one image. Capture overlapping slices through
        // the bottom, where the schedule is placed, instead of only their top edge.
        for index in 0..<16 {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "\(name)-slice-\(index + 1)"
            attachment.lifetime = .keepAlways
            add(attachment)
            let viewport = captureViewport(in: app)
            if element.frame.maxY <= viewport.maxY + 4 { return }
            scrollContent(upBy: min(element.frame.maxY - viewport.maxY, viewport.height * 0.4), in: app)
        }
        XCTFail("Capture did not reach the bottom of \(name)")
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
