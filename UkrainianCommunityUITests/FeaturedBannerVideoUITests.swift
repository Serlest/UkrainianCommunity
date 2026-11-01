import XCTest

@MainActor final class FeaturedBannerVideoUITests: XCTestCase {
    private func launch(language: String = "uk", dark: Bool = false, autoplay: Bool = true, editor: Bool = false, largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("functions/src/featured/fixtures/banner-video-audio.mp4")
        app.launchArguments = ["-ui-testing", "-bannerVideoAutoplayEnabled", autoplay ? "YES" : "NO"]
        app.launchEnvironment = ["UACFirebaseEmulators": "1", "UITestForceOwnerSession": "1", "UITestBanner14": "1",
            "UITestBanner14Scope": editor ? "video-editor" : "video", "UITestBannerVideoFixture": "1",
            "UITestBannerVideoFixturePath": fixture.path, "UITestBannerVideoLargeText": largeText ? "1" : "0", "UITestAppLanguage": language, "UITestAppAppearance": dark ? "dark" : "light"]
        app.launch(); return app
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testMutedAutoplayControlsAndFullscreenLinkWaitForDismissal() throws {
        let app = launch(); defer { app.terminate() }
        let sound = app.buttons["featuredBanner.video.sound"], expand = app.buttons["featuredBanner.video.expand"]
        XCTAssertTrue(expand.waitForExistence(timeout: 15))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: sound)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        XCTAssertEqual(sound.label, "Увімкнути звук")
        capture(app, "VideoBanner-Light-UA-Muted")
        sound.tap(); XCTAssertEqual(sound.label, "Вимкнути звук")
        expand.tap()
        let close = app.buttons["featuredBanner.video.fullscreen.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5)); capture(app, "VideoBanner-Fullscreen-UA")
        XCTAssertEqual(app.buttons["featuredBanner.video.fullscreen.sound"].label, "Увімкнути звук")
        let open = app.buttons["featuredBanner.video.fullscreen.openLink"]; XCTAssertTrue(open.isHittable); open.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["banner14-1"].waitForExistence(timeout: 5))
    }
    func testAutoplayOptOutStillAllowsManualViewingAndDarkGermanControls() throws {
        let app = launch(language: "de", dark: true, autoplay: false); defer { app.terminate() }
        let sound = app.buttons["featuredBanner.video.sound"], expand = app.buttons["featuredBanner.video.expand"]
        XCTAssertTrue(expand.waitForExistence(timeout: 15)); XCTAssertFalse(sound.isEnabled)
        capture(app, "VideoBanner-Dark-DE-PosterOnly")
        expand.tap(); XCTAssertTrue(app.buttons["featuredBanner.video.fullscreen.close"].waitForExistence(timeout: 5))
        let unmute = app.buttons["featuredBanner.video.fullscreen.sound"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: unmute)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        XCTAssertEqual(unmute.label, "Ton einschalten")
        unmute.tap(); XCTAssertEqual(unmute.label, "Ton ausschalten")
        capture(app, "VideoBanner-Dark-DE-ManualFullscreen")
        app.buttons["featuredBanner.video.fullscreen.close"].tap()
        XCTAssertTrue(expand.waitForExistence(timeout: 5)); XCTAssertFalse(sound.isEnabled)
    }
    func testLeavingViewportReleasesVideoAndEditorRetainsExistingPresentation() throws {
        let app = launch(); defer { app.terminate() }
        let sound = app.buttons["featuredBanner.video.sound"]
        XCTAssertTrue(sound.waitForExistence(timeout: 15))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: sound)], timeout: 10), .completed)
        app.swipeUp(); app.swipeUp()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false OR enabled == false"), object: sound)], timeout: 5), .completed)
        app.terminate()
        let editor = launch(editor: true)
        XCTAssertTrue(editor.switches["bannerEditor.video.enabled"].waitForExistence(timeout: 15))
        XCTAssertEqual(editor.switches["bannerEditor.video.enabled"].value as? String, "1")
        for _ in 0..<18 {
            if editor.buttons["bannerEditor.video.choose"].isHittable { break }
            let scroll = editor.scrollViews.firstMatch
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).press(forDuration: 0.05,
                thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55)))
        }
        XCTAssertTrue(editor.switches["bannerEditor.video.enabled"].isHittable)
        XCTAssertTrue(editor.buttons["bannerEditor.video.choose"].isHittable)
        capture(editor, "VideoBanner-Editor-Existing-UA")
        editor.terminate()
    }
    func testLargeTextAndRotationKeepIndependentControlsAvailable() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = launch(language: "de", dark: true, largeText: true)
        defer { XCUIDevice.shared.orientation = .portrait; app.terminate() }
        let expand = app.buttons["featuredBanner.video.expand"]
        XCTAssertTrue(expand.waitForExistence(timeout: 15)); XCTAssertTrue(expand.isHittable)
        capture(app, "VideoBanner-LargeText-DE-Portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        // Accessibility text can make the full 16:9 artwork taller than the landscape
        // viewport. It must remain reachable by scrolling, not shrink the artwork.
        XCTAssertTrue(expand.exists)
        capture(app, "VideoBanner-LargeText-DE-Landscape")
        expand.tap()
        let close = app.buttons["featuredBanner.video.fullscreen.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5)); XCTAssertTrue(close.isHittable)
        capture(app, "VideoBanner-LargeText-DE-Landscape-Fullscreen")
        close.tap()
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(expand.waitForExistence(timeout: 5)); XCTAssertTrue(expand.isHittable)
    }
    func testRotatingWhileFullscreenIsOpenKeepsThePresentation() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = launch()
        defer { XCUIDevice.shared.orientation = .portrait; app.terminate() }
        let expand = app.buttons["featuredBanner.video.expand"]
        XCTAssertTrue(expand.waitForExistence(timeout: 15)); expand.tap()
        let close = app.buttons["featuredBanner.video.fullscreen.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(close.waitForExistence(timeout: 5)); XCTAssertTrue(close.isHittable)
        capture(app, "VideoBanner-Fullscreen-RemainsOpen-OnRotation")
        close.tap()
    }
}
