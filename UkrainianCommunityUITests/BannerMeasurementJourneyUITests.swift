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

    func testEditorOpensOnlyItsOwnReportAndOverviewIsInline() {
        for scope in ["editor", "overview", "management"] {
            let app = XCUIApplication()
            app.launchArguments = ["-ui-testing"]
            app.launchEnvironment = ["UITestBannerReportAudit": "1", "UITestBannerReportScope": scope,
                "UITestForceOwnerSession": "1", "UITestAppLanguage": "uk", "UITestAppAppearance": "dark"]
            app.launch()
            if scope == "editor" {
                let stats = app.buttons["bannerEditor.statistics"].firstMatch
                XCTAssertTrue(stats.waitForExistence(timeout: 15))
                stats.tap()
                XCTAssertTrue(app.otherElements["screen.bannerReport"].waitForExistence(timeout: 10))
                XCTAssertFalse(app.buttons["bannerReport.bannerFilter"].exists)
                XCTAssertTrue(app.staticTexts["SERLEST"].exists)
                XCTAssertFalse(app.staticTexts["UAC"].exists)
            } else if scope == "management" {
                let stats = app.buttons["bannerManagement.statistics.serlest"].firstMatch
                for _ in 0..<12 { if stats.isHittable { break }; app.swipeUp() }
                XCTAssertTrue(stats.isHittable)
                stats.tap()
                XCTAssertTrue(app.otherElements["screen.bannerReport"].waitForExistence(timeout: 10))
                XCTAssertFalse(app.buttons["bannerReport.bannerFilter"].exists)
                XCTAssertTrue(app.staticTexts["SERLEST"].exists)
            } else {
                XCTAssertTrue(app.staticTexts["45"].waitForExistence(timeout: 15))
                XCTAssertTrue(app.otherElements["ownerAnalytics.bannerOverview"].exists)
                XCTAssertFalse(app.buttons["ownerAnalytics.bannerReport"].exists)
            }
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "banner-" + scope; shot.lifetime = .keepAlways; add(shot)
            app.terminate()
        }
    }

    func testRegionFilterFindsUsersOutsideFirstForty() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launchEnvironment = ["UITestForceOwnerSession": "1", "UITestUserRefresh": "1",
            "UITestUserRegionFilter": "1", "UITestAppLanguage": "uk", "UITestResetAppLock": "1"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        app.tabBars.buttons.element(boundBy: 4).tap()
        let users = app.buttons["profile.userManagement"].firstMatch
        for _ in 0..<12 { if users.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(users.isHittable); users.tap()
        let picker = app.buttons["userManagement.regionFilter"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 12))
        for _ in 0..<4 { if picker.isHittable { break }; app.swipeUp() }
        picker.tap()
        let vienna = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Відень")).firstMatch
        XCTAssertTrue(vienna.waitForExistence(timeout: 5)); vienna.tap()
        let row = app.otherElements["userManagement.user.region-40"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10) || app.descendants(matching: .any)["userManagement.user.region-40"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["userManagement.user.region-1"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "users-region-beyond-first-page"; shot.lifetime = .keepAlways; add(shot)
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
