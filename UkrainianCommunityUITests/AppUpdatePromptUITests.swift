import XCTest

final class AppUpdatePromptUITests: XCTestCase {
    @MainActor
    func testLaterReappearsOnNextOpeningInBothLanguages() {
        continueAfterFailure = false
        for (language, title, later, update) in [
            ("de", "Update für UAC verfügbar", "Später", "Jetzt aktualisieren"),
            ("uk", "Доступне оновлення UAC", "Пізніше", "Оновити зараз"),
        ] {
            let app = XCUIApplication()
            app.launchArguments = ["-ui-testing"]
            app.launchEnvironment = ["UITestForceGuestSession": "1", "UITestResetUserSettings": "1",
                "UITestAppLanguage": language, "UITestAppAppearance": language == "de" ? "light" : "dark",
                "UITestAvailableAppVersion": "9.0"]
            app.launch()
            let alert = app.alerts[title]
            XCTAssertTrue(alert.waitForExistence(timeout: 15))
            XCTAssertEqual(app.alerts.count, 1)
            // The initial UIKit alert omits custom IDs; after foregrounding,
            // SwiftUI can expose a nested button. Its visible label is stable.
            let laterButton = alert.buttons.matching(NSPredicate(format: "label == %@", later)).firstMatch
            let updateButton = alert.buttons.matching(NSPredicate(format: "label == %@", update)).firstMatch
            XCTAssertEqual(laterButton.label, later)
            XCTAssertEqual(updateButton.label, update)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "App update prompt — \(language)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            XCTAssertTrue(laterButton.isHittable)
            laterButton.tap()
            XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
            XCUIDevice.shared.press(.home)
            app.activate()
            XCTAssertTrue(alert.waitForExistence(timeout: 10))
            XCTAssertEqual(app.alerts.count, 1)
            XCTAssertTrue(laterButton.isHittable)
            laterButton.tap()
            XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
            app.terminate()
            app.launch()
            XCTAssertTrue(alert.waitForExistence(timeout: 15))
            app.terminate()
        }
    }
}
