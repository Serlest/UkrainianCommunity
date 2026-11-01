import XCTest

@MainActor final class SeasonalViceFlightsUITests:XCTestCase {
    private func launch(effects:Bool,appearance:String="light",scope:String="gta") -> XCUIApplication {
        let app=XCUIApplication();app.launchArguments=["-ui-testing"]
        app.launchEnvironment=["UITestSeasonal":"1","UITestSeasonalScope":scope,"UITestSeasonalLongFeed":"1","UITestSeasonalEffects":effects ? "1":"0","UITestForceOwnerSession":"1","UITestAppLanguage":"uk","UITestAppAppearance":appearance]
        app.launch();XCTAssertTrue(app.buttons[scope.hasPrefix("editor") ? "seasonal.preview.fullScreen":"seasonal.fixture.bell"].waitForExistence(timeout:20))
        return app
    }
    private func shot(_ app:XCUIApplication,_ name:String) {
        let a=XCTAttachment(screenshot:XCUIScreen.main.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)
    }
    func testTwoBannersScrollRotationAndOptOut() {
        defer { XCUIDevice.shared.orientation = .portrait }
        let app=launch(effects:true)
        Thread.sleep(forTimeInterval:8);shot(app,"ViceFlights-City-Portrait-Light")
        app.swipeUp();app.swipeUp()
        Thread.sleep(forTimeInterval:9);shot(app,"ViceFlights-Club-WhileScrolled")
        app.terminate()
        // The feed fixture's window stays portrait on this simulator. Use the existing
        // actual full-screen editor preview for an asserted landscape presentation.
        let editor=launch(effects:true,scope:"editor-gta")
        editor.buttons["seasonal.preview.fullScreen"].tap()
        XCTAssertTrue(editor.buttons["seasonal.preview.close"].waitForExistence(timeout:10))
        XCUIDevice.shared.orientation = .landscapeLeft
        let wide=NSPredicate { _,_ in editor.frame.width>editor.frame.height }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:wide,object:nil)],timeout:10),.completed)
        XCTAssertTrue(editor.tabBars.firstMatch.waitForExistence(timeout:10))
        Thread.sleep(forTimeInterval:10);shot(editor,"ViceFlights-City-Landscape")
        XCTAssertTrue(editor.buttons["seasonal.preview.close"].isHittable)
        XCTAssertEqual(editor.state,.runningForeground)
        editor.terminate();XCUIDevice.shared.orientation = .portrait
        let dark=launch(effects:true,appearance:"dark")
        Thread.sleep(forTimeInterval:24);shot(dark,"ViceFlights-Club-Portrait-Dark")
        dark.terminate()
        let off=launch(effects:false);shot(off,"ViceFlights-OptOut")
        XCTAssertTrue(off.buttons["seasonal.fixture.bell"].isHittable);off.terminate()
    }
    private func benchmark(effects:Bool) {
        let app=launch(effects:effects)
        defer { app.terminate() }
        Thread.sleep(forTimeInterval:5)
        let options=XCTMeasureOptions();options.iterationCount=3
        measure(metrics:[XCTOSSignpostMetric.scrollDraggingMetric,XCTCPUMetric(application:app),XCTMemoryMetric(application:app)],options:options) {
            app.swipeUp();app.swipeUp();app.swipeDown();app.swipeDown()
        }
        XCTAssertEqual(app.state,.runningForeground)
    }
    func testPerformanceWithoutFlights() { benchmark(effects:false) }
    func testPerformanceWithFlights() { benchmark(effects:true) }
}
