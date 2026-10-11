import XCTest

final class RequiredRegistrationUITests: XCTestCase {
    @MainActor
    func testSignedOutUserSeesRegistrationGateInUkrainianAndGerman() {
        for language in ["uk", "de"] {
            let app = XCUIApplication()
            app.launchArguments = ["-ui-testing"]
            app.launchEnvironment["UITestForceSignedOutSession"] = "1"
            app.launchEnvironment["UITestResetUserSettings"] = "1"
            app.launchEnvironment["UITestAppLanguage"] = language
            app.launch()

            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "auth.landing.screen").firstMatch.waitForExistence(timeout: 20))
            XCTAssertFalse(app.tabBars.firstMatch.exists)
            XCTAssertFalse(app.buttons["auth.provider.google"].firstMatch.exists)
            XCTAssertFalse(app.buttons["auth.provider.apple"].firstMatch.exists)

            let createAccount = app.buttons["auth.landing.register"].firstMatch
            XCTAssertTrue(createAccount.exists)
            createAccount.tap()
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "auth.register.screen").firstMatch.waitForExistence(timeout: 10))
            XCTAssertFalse(app.tabBars.firstMatch.exists)
            app.terminate()
        }
    }
}
