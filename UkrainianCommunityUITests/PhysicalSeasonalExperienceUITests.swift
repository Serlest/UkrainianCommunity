import XCTest
import UIKit

/// Explicit opt-in production reads and LOCAL previews only. Never publishes or saves a library.
@MainActor final class PhysicalSeasonalExperienceUITests:XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure=false
        #if targetEnvironment(simulator)
        throw XCTSkip("Physical iPhone required")
        #else
        guard ProcessInfo.processInfo.environment["UACPhysicalSeasonal"]=="1" else { throw XCTSkip("Opt-in physical visual audit") }
        let context=XCTAttachment(string:"Low Power Mode: \(ProcessInfo.processInfo.isLowPowerModeEnabled); Reduce Motion: \(UIAccessibility.isReduceMotionEnabled)")
        context.name="Physical-Seasonal-Accessibility-And-Power";context.lifetime = .keepAlways;add(context)
        #endif
    }
    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication();app.terminate();app.launchArguments=[];app.launch()
        super.tearDown()
    }
    private func capture(_ app:XCUIApplication,_ name:String) {
        XCTAssertEqual(app.state,.runningForeground)
        // App-window cropping can retain portrait bounds during rotation on a
        // physical device. Capture the actual display for visual evidence.
        let a=XCTAttachment(screenshot:XCUIScreen.main.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)
    }
    private func reveal(_ item:XCUIElement,_ app:XCUIApplication,down:Bool=false) {
        for _ in 0..<20 where !item.exists || !item.isHittable || item.frame.midY<100 || item.frame.midY>app.frame.height-110 {
            if down || (item.exists && item.frame.midY<100) { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(item.exists && item.isHittable)
    }
    private func management(_ app:XCUIApplication) {
        let stop=app.buttons["seasonal.localPreview.stop"];if stop.exists { stop.tap() }
        let profile=app.tabBars.buttons.matching(NSPredicate(format:"identifier == %@ OR label IN %@","tab.profile",["Профіль","Profil","Profile"])).firstMatch
        XCTAssertTrue(profile.waitForExistence(timeout:20));profile.tap()
        let entry=app.buttons["profile.seasonalManagement"];reveal(entry,app);entry.tap()
        XCTAssertTrue(app.buttons["seasonal.quick.preview.uac.preset.halloween"].waitForExistence(timeout:25))
        let switchControl=app.buttons["seasonal.quick.uac.preset.halloween"]
        let loaded=NSPredicate { _,_ in switchControl.exists && switchControl.isEnabled }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:loaded,object:nil)],timeout:25),.completed,"Private and public server documents must load on first navigation")
    }
    private func measureFeed(_ app:XCUIApplication) {
        let news=app.tabBars.buttons["Новини"];XCTAssertTrue(news.waitForExistence(timeout:15));news.tap()
        Thread.sleep(forTimeInterval:5)
        XCTAssertTrue(app.buttons["header.search.toggle"].exists,"Benchmark must start on the news root")
        app.swipeUp();app.swipeDown()
        let options=XCTMeasureOptions();options.iterationCount=3
        measure(metrics:[XCTOSSignpostMetric.scrollDraggingMetric,XCTCPUMetric(application:app),XCTMemoryMetric(application:app)],options:options) {
            app.swipeUp();app.swipeUp();app.swipeUp()
            app.swipeDown();app.swipeDown();app.swipeDown()
        }
        capture(app,"Physical-Winter-Scroll-Benchmark")
        XCTAssertTrue(app.buttons["header.search.toggle"].exists,"Unexpected navigation invalidates the scroll comparison")
    }
    func testQuickSceneCatalogHasNoLegacyLanguageDuplicates() {
        let app=XCUIApplication();app.launchArguments=["-selectedAppLanguage","uk"];app.launch()
        management(app)
        for kind in ["halloween","gta","christmas","newyear"] {
            XCTAssertEqual(app.buttons.matching(identifier:"seasonal.quick.preview.uac.preset."+kind).count,1)
        }
        XCTAssertFalse(app.staticTexts["Halloween"].exists)
        XCTAssertFalse(app.staticTexts["Christmas · Warm Evergreen"].exists)
        XCTAssertFalse(app.staticTexts["New Year · Golden Midnight"].exists)
        capture(app,"Physical-Quick-Catalog-Ukrainian-No-Duplicates")
    }
    func testViceBadgeAndLocalSceneReplacement() {
        let app=XCUIApplication()
        for appearance in ["light","dark"] {
            app.launchArguments=["-selectedAppLanguage","uk","-selectedAppAppearance",appearance];app.launch()
            for scene in ["gta","halloween","christmas","gta"] {
                management(app)
                let preview=app.buttons["seasonal.quick.preview.uac.preset."+scene];reveal(preview,app);preview.tap()
                app.tabBars.buttons["Новини"].tap()
                let stop=app.buttons["seasonal.localPreview.stop"]
                XCTAssertTrue(stop.waitForExistence(timeout:10))
                Thread.sleep(forTimeInterval:2)
                capture(app,"SceneReplacement-"+appearance+"-"+scene)
                if scene == "gta" {
                    XCUIDevice.shared.orientation = .landscapeLeft
                    Thread.sleep(forTimeInterval:2);capture(app,"ViceBadge-"+appearance+"-Landscape")
                    XCUIDevice.shared.orientation = .portrait
                    Thread.sleep(forTimeInterval:1)
                }
                stop.tap();XCTAssertTrue(stop.waitForNonExistence(timeout:5))
            }
            app.terminate()
        }
    }
    func testSavedCalendarConflictsAreVisibleWithoutPublishing() {
        let app=XCUIApplication()
        for (language,appearance) in [("uk","light"),("de","dark")] {
            app.launchArguments=["-selectedAppLanguage",language,"-selectedAppAppearance",appearance];app.launch()
            management(app)
            let advanced=app.buttons["seasonal.advanced"];reveal(advanced,app);advanced.tap()
            let warning=app.descendants(matching:.any).matching(identifier:"seasonal.schedule.overlap").firstMatch
            reveal(warning,app);capture(app,"CalendarOverlap-"+language+"-"+appearance)
            XCTAssertTrue(app.buttons["seasonal.publish"].exists)
            app.terminate()
        }
    }
    func testAllScenesSurviveBothLandscapeDirectionsAndReturnToPortrait() {
        let app=XCUIApplication()
        for appearance in ["light","dark"] {
            app.launchArguments=["-selectedAppLanguage","uk","-selectedAppAppearance",appearance];app.launch()
            for scene in ["halloween","gta","christmas","newyear"] {
                management(app)
                let preview=app.buttons["seasonal.quick.preview.uac.preset."+scene];reveal(preview,app);preview.tap()
                app.tabBars.buttons["Новини"].tap()
                let stop=app.buttons["seasonal.localPreview.stop"]
                XCTAssertTrue(stop.waitForExistence(timeout:10))
                capture(app,"SeasonalRotation-"+scene+"-"+appearance+"-PortraitBefore")
                for (name,orientation) in [("Left",UIDeviceOrientation.landscapeLeft),("Right",.landscapeRight)] {
                    XCUIDevice.shared.orientation=orientation
                    let wide=NSPredicate { _,_ in app.frame.width>app.frame.height }
                    XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:wide,object:nil)],timeout:10),.completed)
                    Thread.sleep(forTimeInterval:2)
                    XCTAssertTrue(stop.isHittable);XCTAssertTrue(app.tabBars.buttons["Новини"].isHittable)
                    capture(app,"SeasonalRotation-"+scene+"-"+appearance+"-"+name)
                    app.swipeUp();capture(app,"SeasonalRotation-"+scene+"-"+appearance+"-"+name+"-Scrolled");app.swipeDown()
                }
                XCUIDevice.shared.orientation = .portrait
                let tall=NSPredicate { _,_ in app.frame.height>app.frame.width }
                XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:tall,object:nil)],timeout:10),.completed)
                capture(app,"SeasonalRotation-"+scene+"-"+appearance+"-PortraitRestored")
                stop.tap();XCTAssertTrue(stop.waitForNonExistence(timeout:5))
            }
            app.terminate()
        }
    }
    func testEditorFullScreenPreviewKeepsWinterSceneDuringRotation() {
        let app=XCUIApplication();app.launchArguments=["-selectedAppLanguage","uk"];app.launch()
        management(app)
        let edit=app.buttons["seasonal.quick.edit.uac.preset.christmas"];reveal(edit,app);edit.tap()
        let open=app.buttons["seasonal.preview.fullScreen"];XCTAssertTrue(open.waitForExistence(timeout:10));reveal(open,app);open.tap()
        let close=app.buttons["seasonal.preview.close"];XCTAssertTrue(close.waitForExistence(timeout:10))
        for (name,orientation) in [("Left",UIDeviceOrientation.landscapeLeft),("Right",.landscapeRight)] {
            XCUIDevice.shared.orientation=orientation
            let wide=NSPredicate { _,_ in app.frame.width>app.frame.height }
            XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:wide,object:nil)],timeout:10),.completed)
            Thread.sleep(forTimeInterval:2)
            XCTAssertTrue(close.isHittable);capture(app,"SeasonalRotation-EditorPreview-"+name)
        }
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval:2);close.tap()
        XCTAssertTrue(open.waitForExistence(timeout:10))
        capture(app,"SeasonalRotation-EditorPreview-PortraitReturned")
    }
    func testWinterNavigationRimFollowsFloatingItemsInBothLanguages() {
        let app=XCUIApplication()
        for (language,appearance,scene) in [("uk","light","christmas"),("de","dark","newyear")] {
            app.launchArguments=["-selectedAppLanguage",language,"-selectedAppAppearance",appearance];app.launch()
            management(app)
            let preview=app.buttons["seasonal.quick.preview.uac.preset."+scene];reveal(preview,app);preview.tap()
            let news=app.tabBars.buttons.matching(NSPredicate(format:"label IN %@",["Новини","Nachrichten"])).firstMatch
            XCTAssertTrue(news.waitForExistence(timeout:10));news.tap()
            capture(app,"WinterNavigation-"+language+"-Portrait")
            for (name,orientation) in [("Left",UIDeviceOrientation.landscapeLeft),("Right",.landscapeRight)] {
                XCUIDevice.shared.orientation=orientation
                let wide=NSPredicate { _,_ in app.frame.width>app.frame.height }
                XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:wide,object:nil)],timeout:10),.completed)
                Thread.sleep(forTimeInterval:2)
                XCTAssertTrue(news.isHittable)
                capture(app,"WinterNavigation-"+language+"-"+name)
                app.swipeUp();capture(app,"WinterNavigation-"+language+"-"+name+"-Scrolled");app.swipeDown()
            }
            XCUIDevice.shared.orientation = .portrait
            let tall=NSPredicate { _,_ in app.frame.height>app.frame.width }
            XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:tall,object:nil)],timeout:10),.completed)
            capture(app,"WinterNavigation-"+language+"-PortraitRestored")
            let stop=app.buttons["seasonal.localPreview.stop"];XCTAssertTrue(stop.isHittable);stop.tap()
            app.terminate()
        }
    }
    func testPhotographicHangersFitBothThemesAfterViewportReduction() {
        let app=XCUIApplication()
        for appearance in ["light","dark"] {
            app.launchArguments=["-selectedAppAppearance",appearance];app.launch()
            for scene in ["gta","christmas","newyear"] {
                management(app)
                let preview=app.buttons["seasonal.quick.preview.uac.preset."+scene];reveal(preview,app);preview.tap()
                app.tabBars.buttons["Новини"].tap()
                let search=app.buttons["header.search.toggle"]
                for _ in 0..<6 where !search.isHittable { app.swipeDown() }
                XCTAssertTrue(search.isHittable)
                Thread.sleep(forTimeInterval:2)
                capture(app,"Physical-Bounded-Hangers-"+scene+"-"+appearance)
                app.buttons["seasonal.localPreview.stop"].tap()
            }
        }
    }
    func testHolidayFlightsSnowAndPersistentHangersDuringRealScroll() {
        let app=XCUIApplication();app.launchArguments=["-selectedAppAppearance","light"];app.launch()
        for scene in ["halloween","gta","christmas","newyear"] {
            management(app)
            let preview=app.buttons["seasonal.quick.preview.uac.preset."+scene];reveal(preview,app);preview.tap()
            app.tabBars.buttons["Новини"].tap()
            capture(app,"Physical141-"+scene+"-BeforeScroll")
            app.swipeUp();app.swipeUp();app.swipeUp()
            capture(app,"Physical141-"+scene+"-PinnedAfterScroll")
            if scene=="christmas" || scene=="newyear" {
                // Observe the actual infrequent production timing, without a fast-forward flag.
                for frame in 0..<7 {
                    Thread.sleep(forTimeInterval:1.4)
                    capture(app,"Physical141-"+scene+"-Flight-"+String(frame))
                }
            }
            app.swipeDown();app.swipeDown();app.swipeDown()
            capture(app,"Physical141-"+scene+"-ReturnedHeader")
            app.buttons["seasonal.localPreview.stop"].tap()
        }
    }
    func testNewYearBurstTimingWithoutScrollDelay() {
        let app=XCUIApplication()
        for appearance in ["light","dark"] {
            app.launchArguments=["-selectedAppAppearance",appearance];app.launch()
            management(app)
            let preview=app.buttons["seasonal.quick.preview.uac.preset.newyear"];reveal(preview,app);preview.tap()
            app.tabBars.buttons["Новини"].tap()
            for frame in 0..<16 {
                Thread.sleep(forTimeInterval:0.55)
                capture(app,"Physical-Multicolour-"+appearance+"-"+String(format:"%02d",frame))
            }
            app.buttons["seasonal.localPreview.stop"].tap();app.terminate()
        }
    }
    func testABaselinePhysicalScrollWithoutEffects() {
        let app=XCUIApplication();app.launchArguments=["-selectedAppAppearance","light","-seasonalEffectsEnabled","NO"];app.launch()
        measureFeed(app)
        app.launchArguments=[];app.launch()
    }
    func testBWinterPhysicalScrollWithSharedSnowAndTree() {
        let app=XCUIApplication();app.launchArguments=["-selectedAppAppearance","light","-seasonalEffectsEnabled","NO"];app.launch()
        management(app)
        let preview=app.buttons["seasonal.quick.preview.uac.preset.christmas"];reveal(preview,app);preview.tap()
        measureFeed(app)
        app.buttons["seasonal.localPreview.stop"].tap()
        app.launchArguments=[];app.launch()
    }
    func testFourScenesOnRealFeedsInLightAndDarkWithoutPublishing() throws {
        let app=XCUIApplication()
        for appearance in ["light","dark"] {
            app.launchArguments=["-selectedAppAppearance",appearance];app.launch()
            for scene in ["halloween","gta","christmas","newyear"] {
                management(app)
                let preview=app.buttons["seasonal.quick.preview.uac.preset."+scene];reveal(preview,app);preview.tap()
                let stop=app.buttons["seasonal.localPreview.stop"];XCTAssertTrue(stop.waitForExistence(timeout:10))
                for (index,label) in ["Новини","Події","Організації","Довідник","Профіль"].enumerated() {
                    let tab=app.tabBars.buttons[label];XCTAssertTrue(tab.isHittable);tab.tap();XCTAssertTrue(tab.isSelected)
                    Thread.sleep(forTimeInterval:1)
                    capture(app,"Physical-Seasonal-"+scene+"-"+appearance+"-tab-"+String(index))
                }
                app.tabBars.buttons["Новини"].tap()
                app.swipeUp();app.swipeUp();capture(app,"Physical-Seasonal-"+scene+"-"+appearance+"-scroll")
                app.swipeDown();app.swipeDown()
                if scene=="christmas" {
                    Thread.sleep(forTimeInterval:3);capture(app,"Physical-Seasonal-Snow-"+appearance+"-frame-A")
                    Thread.sleep(forTimeInterval:2);capture(app,"Physical-Seasonal-Snow-"+appearance+"-frame-B")
                }
                stop.tap();XCTAssertTrue(stop.waitForNonExistence(timeout:5))
            }
        }
        // Remove only transient launch arguments; user defaults are not changed.
        app.launchArguments=[];app.launch()
    }
    func testLocalWinterPreviewIdleAccumulationAndOrientation() throws {
        let app=XCUIApplication();app.launchArguments=["-selectedAppAppearance","light"];app.launch()
        management(app)
        let preview=app.buttons["seasonal.quick.preview.uac.preset.christmas"];reveal(preview,app);preview.tap()
        app.tabBars.buttons["Новини"].tap()
        capture(app,"Physical-Winter-Accumulation-Start")
        for _ in 0..<6 { Thread.sleep(forTimeInterval:15);XCTAssertEqual(app.state,.runningForeground) }
        capture(app,"Physical-Winter-Accumulation-90s")
        XCUIDevice.shared.orientation = .landscapeLeft;Thread.sleep(forTimeInterval:2)
        let landscape=NSPredicate { _,_ in app.frame.width>app.frame.height }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:landscape,object:nil)],timeout:10),.completed)
        capture(app,"Physical-Winter-Landscape")
        XCUIDevice.shared.orientation = .portrait;Thread.sleep(forTimeInterval:2)
        XCTAssertGreaterThan(app.frame.height,app.frame.width)
        capture(app,"Physical-Winter-Portrait-Return")
        app.buttons["seasonal.localPreview.stop"].tap()
        app.launchArguments=[];app.launch()
    }
}
