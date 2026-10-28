import XCTest

@MainActor final class SeasonalPerformanceUITests:XCTestCase {
    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["UACSeasonalPerformance"]=="1" else { throw XCTSkip("Opt-in isolated compositor benchmark") }
    }
    private func exercise(effects:Bool) {
        let app=XCUIApplication();app.launchArguments=["-ui-testing"]
        app.launchEnvironment=["UITestSeasonal":"1","UITestSeasonalScope":"christmas","UITestSeasonalLongFeed":"1","UITestSeasonalEffects":effects ? "1":"0","UITestForceOwnerSession":"1","UITestAppLanguage":"uk","UITestAppAppearance":"light"]
        app.launch()
        let bell=app.buttons["seasonal.fixture.bell"];XCTAssertTrue(bell.waitForExistence(timeout:15))
        app.swipeUp();XCTAssertFalse(bell.isHittable);app.swipeDown()
        let options=XCTMeasureOptions();options.iterationCount=3
        measure(metrics:[XCTOSSignpostMetric.scrollDraggingMetric,XCTCPUMetric(application:app),XCTMemoryMetric(application:app)],options:options) {
            app.swipeUp();app.swipeUp();app.swipeUp()
            app.swipeDown();app.swipeDown();app.swipeDown()
        }
        app.swipeDown();app.swipeDown();XCTAssertTrue(bell.isHittable)
        let a=XCTAttachment(screenshot:app.screenshot());a.name=effects ? "WinterPerformance-Effects-On":"WinterPerformance-Effects-Off";a.lifetime = .keepAlways;add(a)
        app.terminate()
    }
    func testABaselineWinterFeedWithoutEffects() { exercise(effects:false) }
    func testBWinterFeedWithSharedSnowAndGarland() { exercise(effects:true) }
}
