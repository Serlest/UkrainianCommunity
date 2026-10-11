import XCTest

final class RequiredRegistrationUITests: XCTestCase {
    @MainActor
    func testEmailMethodOpensSignInInUkrainianAndGerman() {
        for (language, title) in [
            ("uk", "Продовжити з email"),
            ("de", "Mit E-Mail fortfahren")
        ] {
            let app = XCUIApplication()
            app.launchArguments = ["-ui-testing"]
            app.launchEnvironment["UITestForceSignedOutSession"] = "1"
            app.launchEnvironment["UITestResetUserSettings"] = "1"
            app.launchEnvironment["UITestAppLanguage"] = language
            app.launch()

            let emailMethod = app.buttons["auth.landing.signIn"].firstMatch
            XCTAssertTrue(emailMethod.waitForExistence(timeout: 20))
            XCTAssertEqual(emailMethod.label, title)
            emailMethod.tap()
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "auth.login.screen").firstMatch.waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["auth.login.submit"].firstMatch.exists)
            app.terminate()
        }
    }

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
            XCTAssertTrue(app.buttons["auth.provider.google"].firstMatch.exists)
            XCTAssertTrue(app.buttons["auth.provider.apple"].firstMatch.exists)

            let createAccount = app.buttons["auth.landing.register"].firstMatch
            XCTAssertTrue(createAccount.exists)
            createAccount.tap()
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "auth.register.screen").firstMatch.waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["auth.provider.google"].firstMatch.exists)
            XCTAssertTrue(app.buttons["auth.provider.apple"].firstMatch.exists)
            let emailMethod = app.buttons["auth.register.emailMethod"].firstMatch
            XCTAssertTrue(emailMethod.exists)
            emailMethod.tap()
            XCTAssertTrue(app.buttons["auth.register.submit"].firstMatch.exists)
            XCTAssertTrue(app.buttons["auth.register.changeMethod"].firstMatch.exists)
            XCTAssertFalse(app.tabBars.firstMatch.exists)
            app.terminate()
        }
    }
}
