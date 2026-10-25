import XCTest

/// Real UI and actual SDK graph against the fixed demo emulators; no fixture roles/repositories.
@MainActor
final class ConnectedAuditUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testMemberBookmarkThroughUIAndReopenAfterProcessRestart() throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" else {
            throw XCTSkip("Requires local audit emulator fixtures")
        }
        let app = launchMember()
        let card = app.buttons["home.card.news-closure-news"].firstMatch
        reveal(card, app); XCTAssertTrue(card.waitForExistence(timeout: 15)); card.tap()
        let bookmark = app.buttons["detail.header.action.bookmark"].firstMatch
        XCTAssertTrue(bookmark.waitForExistence(timeout: 10)); bookmark.tap()
        XCTAssertTrue(app.buttons["detail.header.action.bookmark.fill"].waitForExistence(timeout: 10))
        capture(app, "sdk-news-bookmarked")
        app.terminate(); app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))
        app.tabBars.buttons.element(boundBy: 4).tap()
        let saved = app.buttons["profile.savedContent"]
        reveal(saved, app); XCTAssertTrue(saved.exists); saved.tap()
        let row = app.buttons["saved.open.news-closure-news"]
        reveal(row, app); XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
        let remove = app.buttons["detail.header.action.bookmark.fill"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 10)); capture(app, "sdk-bookmark-after-restart"); remove.tap()
        XCTAssertTrue(bookmark.waitForExistence(timeout: 10))
    }

    func testActualPhotoPickerCropCancelAndApplyPreserveEditor() throws {
        try photoJourney(language: "uk", appearance: "light", large: false)
    }

    func testActualPhotoPickerGermanDarkAtAccessibilitySize() throws {
        try photoJourney(language: "de", appearance: "dark", large: true)
    }

    private func photoJourney(language: String, appearance: String, large: Bool) throws {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" else {
            throw XCTSkip("Requires local audit emulator and simulator photo fixture")
        }
        let app = launchMember(language: language, appearance: appearance, large: large)
        app.tabBars.buttons.element(boundBy: 4).tap()
        let edit = app.buttons["profile.edit.open"]
        reveal(edit, app); XCTAssertTrue(edit.exists); edit.tap()
        let picker = app.buttons["profile.edit.photo"]
        XCTAssertTrue(picker.waitForExistence(timeout: 10)); picker.tap()
        let photo = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 10))
        capture(app, "sdk-profile-system-photo-picker")
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let apply = app.buttons["imageCrop.apply"]
        XCTAssertTrue(apply.waitForExistence(timeout: 15))
        let zoomIn = app.buttons["imageCrop.control.plus.magnifyingglass"]
        reveal(zoomIn, app); XCTAssertTrue(zoomIn.isHittable); zoomIn.tap()
        let zoomOut = app.buttons["imageCrop.control.minus.magnifyingglass"]
        XCTAssertTrue(zoomOut.isEnabled); zoomOut.tap()
        for symbol in ["arrow.left", "arrow.right", "arrow.up", "arrow.down", "minus.magnifyingglass", "plus.magnifyingglass"] {
            let control = app.buttons["imageCrop.control." + symbol]
            reveal(control, app); XCTAssertTrue(control.isHittable)
            XCTAssertGreaterThanOrEqual(control.frame.width, 44)
            XCTAssertGreaterThanOrEqual(control.frame.height, 44)
        }
        capture(app, "sdk-profile-crop-controls-" + language + "-" + appearance)
        app.buttons["imageCrop.cancel"].tap()
        XCTAssertTrue(apply.waitForNonExistence(timeout: 5)); XCTAssertTrue(picker.exists)
        picker.tap(); XCTAssertTrue(photo.waitForExistence(timeout: 10)); photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(apply.waitForExistence(timeout: 15)); app.buttons["imageCrop.reset"].tap(); apply.tap()
        XCTAssertTrue(apply.waitForNonExistence(timeout: 15))
        XCTAssertTrue(app.buttons["profile.edit.save"].isEnabled)
        capture(app, "sdk-profile-cropped-preview-" + language + "-" + appearance)
        // Upload/persistence is a separate SDK journey; terminating discards the
        // unsaved crop here and never changes a production profile.
        app.terminate()
    }

    private func launchMember(language: String = "uk", appearance: String = "light", large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-sdk-ui-audit", "-selectedAppLanguage", language, "-selectedAppAppearance", appearance,
                               "-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityM" : "UICTContentSizeCategoryL"]
        app.launchEnvironment = ["UACFirebaseEmulators": "1"]
        app.launch()
        let signIn = app.buttons["auth.landing.signIn"]
        if signIn.waitForExistence(timeout: 20) {
            signIn.tap()
            let email = app.textFields["auth.login.email"]
            XCTAssertTrue(email.waitForExistence(timeout: 8)); email.tap(); email.typeText("closure-member@uac.test")
            let password = app.secureTextFields["auth.login.password"]
            password.tap(); password.typeText("Emulator-Only-2026!")
            app.swipeUp()
            let submit = app.buttons["auth.login.submit"]
            reveal(submit, app); submit.tap()
        }
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))
        let later = app.buttons["auth.passkeySuggestion.later"]
        if later.waitForExistence(timeout: 5) { capture(app, "sdk-passkey-suggestion"); later.tap() }
        return app
    }

    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
