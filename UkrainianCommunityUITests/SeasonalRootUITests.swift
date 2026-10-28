import XCTest

@MainActor final class SeasonalRootUITests: XCTestCase {
    func testLocalOwnerPreviewUsesActualRootAcrossTabsAndRestoresOptOut() throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"]=="1" else { throw XCTSkip("Isolated demo transport required") }
        let app=XCUIApplication();app.launchArguments=["-ui-testing","-seasonalEffectsEnabled","NO"]
        app.launchEnvironment=["UACFirebaseEmulators":"1","UITestForceOwnerSession":"1","UITestAppLanguage":"uk","UITestAppAppearance":"light"]
        app.launch()
        let profile=app.tabBars.buttons["Профіль"];XCTAssertTrue(profile.waitForExistence(timeout:30));profile.tap()
        let management=app.buttons["profile.seasonalManagement"]
        for _ in 0..<20 where !management.exists || !management.isHittable {
            if management.exists && management.frame.midY<100 { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(management.isHittable);management.tap()
        let preview=app.buttons["seasonal.quick.preview.uac.preset.christmas"]
        XCTAssertTrue(preview.waitForExistence(timeout:10))
        for _ in 0..<12 where !preview.isHittable { app.swipeUp() }
        XCTAssertTrue(preview.isHittable);preview.tap()
        let stop=app.buttons["seasonal.localPreview.stop"];XCTAssertTrue(stop.waitForExistence(timeout:10))
        for label in ["Новини","Події","Організації","Довідник","Профіль"] {
            let tab=app.tabBars.buttons[label];XCTAssertTrue(tab.isHittable);tab.tap();XCTAssertTrue(tab.isSelected)
            Thread.sleep(forTimeInterval:1)
            let a=XCTAttachment(screenshot:app.screenshot());a.name="ActualRoot-LocalWinter-"+label;a.lifetime = .keepAlways;add(a)
        }
        app.tabBars.buttons["Новини"].tap();app.swipeUp();app.swipeDown()
        XCTAssertTrue(stop.isHittable);stop.tap();XCTAssertTrue(stop.waitForNonExistence(timeout:5))
        app.terminate()
    }

    func testSnowRimAccumulatesOnActualLightRootWithoutCoveringTabs() throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"]=="1" else { throw XCTSkip("Isolated demo transport required") }
        let app=XCUIApplication();app.launchArguments=["-ui-testing","-seasonalEffectsEnabled","YES"]
        app.launchEnvironment=["UACFirebaseEmulators":"1","UITestForceGuestSession":"1","UITestAppLanguage":"uk","UITestAppAppearance":"light"]
        app.launch();XCTAssertTrue(app.buttons["header.search.toggle"].waitForExistence(timeout:30))
        func shot(_ name:String) { let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a) }
        shot("ActualRoot-Snow-Rim-Initial")
        for _ in 0..<6 { Thread.sleep(forTimeInterval:15);XCTAssertEqual(app.state,.runningForeground) }
        for label in ["Новини","Події","Організації","Довідник","Профіль"] { XCTAssertTrue(app.tabBars.buttons[label].isHittable) }
        shot("ActualRoot-Snow-Rim-After-90s")
        app.terminate()
    }

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
        // Decorative overlays must never introduce a top safe-area row.
        XCTAssertEqual(onSearch.frame.minY,baseline,accuracy:1)
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
