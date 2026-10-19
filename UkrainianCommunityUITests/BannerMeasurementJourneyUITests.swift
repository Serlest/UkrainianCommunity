import XCTest

@MainActor
final class BannerMeasurementJourneyUITests: XCTestCase {
    func testRealCarouselEmitsViewAndClickWithRegion() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launchEnvironment = ["UITestBannerAudit": "1", "UITestForceAuthenticatedSession": "1"]
        app.launch()
        let counts = app.staticTexts["bannerAudit.counts"]
        XCTAssertTrue(counts.waitForExistence(timeout: 15))
        let viewed = NSPredicate(format: "label == %@", "1:0:tirol")
        expectation(for: viewed, evaluatedWith: counts)
        waitForExpectations(timeout: 8)
        app.buttons["featuredBanner.card.audit-banner"].tap()
        XCTAssertEqual(counts.label, "1:1:tirol")
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertEqual(counts.label, "1:1:tirol")
        app.terminate()
    }

    func testReportFiltersAndExportInBothLanguages() {
        for language in ["uk", "de"] {
            let app = XCUIApplication()
            app.launchArguments = ["-ui-testing"]
            app.launchEnvironment = ["UITestBannerReportAudit": "1", "UITestAppLanguage": language,
                                     "UITestAppAppearance": language == "uk" ? "light" : "dark",
                                     "UITestForceAuthenticatedSession": "1"]
            app.launch()
            XCTAssertTrue(app.otherElements["screen.bannerReport"].waitForExistence(timeout: 15))
            XCTAssertTrue(app.buttons["bannerReport.bannerFilter"].waitForExistence(timeout: 8))
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "banner-report-\(language)"
            attachment.lifetime = .keepAlways
            add(attachment)
            if !app.buttons["bannerReport.regionFilter"].isHittable { app.swipeUp() }
            app.buttons["bannerReport.regionFilter"].tap()
            let tirol = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", language == "uk" ? "Тіроль" : "Tirol")).firstMatch
            XCTAssertTrue(tirol.waitForExistence(timeout: 5))
            tirol.tap()
            app.swipeUp()
            let regionShot = XCTAttachment(screenshot: app.screenshot())
            regionShot.name = "banner-regions-\(language)"; regionShot.lifetime = .keepAlways; add(regionShot)
            app.swipeUp()
            let chartShot = XCTAttachment(screenshot: app.screenshot())
            chartShot.name = "banner-chart-\(language)"; chartShot.lifetime = .keepAlways; add(chartShot)
            let export = app.buttons["bannerReport.export"]
            for _ in 0..<6 {
                if export.isHittable { break }
                app.swipeDown()
            }
            XCTAssertTrue(export.isHittable)
            export.tap()
            let save = app.buttons["Save"].firstMatch
            XCTAssertTrue(save.waitForExistence(timeout: 5) || app.buttons["Sichern"].exists || app.buttons["Зберегти"].exists)
            let exported = XCTAttachment(screenshot: app.screenshot())
            exported.name = "banner-export-\(language)"; exported.lifetime = .keepAlways; add(exported)
            app.terminate()
        }
    }
}
