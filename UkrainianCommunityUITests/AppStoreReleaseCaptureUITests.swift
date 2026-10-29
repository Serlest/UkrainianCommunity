import XCTest

/// Opt-in capture of the real, already authenticated application. No fixtures,
/// writes, consent changes or server scene activation. Launch overrides are volatile.
@MainActor final class AppStoreReleaseCaptureUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(ProcessInfo.processInfo.environment["UACAppStoreCapture"] == "1")
        XCUIDevice.shared.orientation = .portrait
    }
    override func tearDown() {
        let app = XCUIApplication()
        app.terminate()
        app.launchArguments = []
        app.launchEnvironment = [:]
        app.launch()
        super.tearDown()
    }
    func testCapturePublicTabs() {
        let app = XCUIApplication()
        for language in ["uk", "de"] {
            app.launchArguments = ["-selectedAppLanguage", language, "-selectedAppAppearance", "light", "-seasonalEffectsEnabled", "NO"]
            app.launch()
            let tabs = app.tabBars.firstMatch
            XCTAssertTrue(tabs.waitForExistence(timeout: 40), "An existing authenticated session is required; never bypass the startup gate")
            for (index, entry) in [("news", ["Новини", "News"]), ("events", ["Події", "Veranstaltungen"]), ("organizations", ["Організації", "Organisationen"]), ("directory", ["Довідник", "Ratgeber"])] {
                let tab = app.tabBars.buttons.matching(NSPredicate(format: "identifier == %@ OR label IN %@", "tab." + index, entry)).firstMatch
                XCTAssertTrue(tab.waitForExistence(timeout: 15), "Missing public tab " + index)
                tab.tap()
                // Allow real network images and their native layout to settle.
                Thread.sleep(forTimeInterval: 8)
                XCTAssertFalse(app.buttons["seasonal.localPreview.stop"].exists)
                let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                shot.name = "AppStore13-" + language + "-" + index
                shot.lifetime = .keepAlways
                add(shot)
            }
            app.terminate()
        }
    }
}
