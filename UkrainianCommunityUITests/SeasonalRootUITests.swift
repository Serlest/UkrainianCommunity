import XCTest

@MainActor final class SeasonalRootUITests: XCTestCase {
    func testActualRootUsesPublicScheduleAndHonorsLocalOptOut() throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" else { throw XCTSkip("Requires public schedule in isolated loopback emulators") }
        func launch(enabled: Bool) -> XCUIApplication {
            let app = XCUIApplication()
            app.launchArguments = ["-ui-testing", "-seasonalEffectsEnabled", enabled ? "YES" : "NO"]
            app.launchEnvironment = ["UACFirebaseEmulators":"1", "UITestForceGuestSession":"1", "UITestAppLanguage":"uk", "UITestAppAppearance":"light"]
            app.launch(); return app
        }
        let off = launch(enabled: false)
        let offSearch = off.buttons["header.search.toggle"]
        XCTAssertTrue(offSearch.waitForExistence(timeout:30))
        let baseline = offSearch.frame.minY
        off.terminate()
        let on = launch(enabled: true)
        let onSearch = on.buttons["header.search.toggle"]
        XCTAssertTrue(onSearch.waitForExistence(timeout:30))
        let shifted = NSPredicate { _,_ in onSearch.exists && onSearch.frame.minY >= baseline + 40 }
        expectation(for:shifted,evaluatedWith:nil)
        waitForExpectations(timeout:20)
        let capture = XCTAttachment(screenshot:on.screenshot());capture.name="Seasonal-ActualRoot-PublicSchedule";capture.lifetime = .keepAlways;add(capture)
        XCTAssertTrue(onSearch.isHittable)
        let visibleY = onSearch.frame.minY
        XCUIDevice.shared.press(.home); on.activate()
        XCTAssertTrue(onSearch.waitForExistence(timeout:10))
        XCTAssertEqual(onSearch.frame.minY, visibleY, accuracy:1)
        for label in ["Події", "Організації", "Довідник", "Профіль"] {
            let tab = on.tabBars.buttons[label]
            XCTAssertTrue(tab.exists);tab.tap();XCTAssertTrue(tab.isSelected)
            let screenshot = XCTAttachment(screenshot:on.screenshot());screenshot.name="Seasonal-ActualRoot-" + label;screenshot.lifetime = .keepAlways;add(screenshot)
        }
        on.terminate()
    }
}
