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
    @MainActor
    func testAuthScreenAppearanceAndPasswordResetNavigation() {
        for (language, appearance, forgot) in [("uk", "light", "Забули пароль?"), ("de", "dark", "Passwort vergessen?")] {
            let app = XCUIApplication()
            app.launchArguments = ["-ui-testing"]
            app.launchEnvironment = ["UITestForceSignedOutSession": "1", "UITestResetUserSettings": "1",
                                     "UITestAppLanguage": language, "UITestAppAppearance": appearance]
            app.launch()
            XCTAssertTrue(app.buttons["auth.landing.signIn"].waitForExistence(timeout: 20))
            capture(app, "auth-landing-" + language)
            app.buttons["auth.landing.signIn"].tap()
            XCTAssertTrue(app.buttons["auth.login.submit"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["auth.login.submit"].isEnabled)
            capture(app, "auth-login-" + language)
            let reset = app.buttons[forgot].firstMatch
            for _ in 0..<6 {
                if reset.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(reset.isHittable)
            reset.tap()
            XCTAssertTrue(app.buttons["auth.reset.submit"].waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["auth.reset.submit"].isEnabled)
            capture(app, "auth-reset-" + language)
            app.terminate()
            app.launch()
            XCTAssertTrue(app.buttons["auth.landing.register"].waitForExistence(timeout: 20))
            app.buttons["auth.landing.register"].tap()
            XCTAssertTrue(app.buttons["auth.register.emailMethod"].waitForExistence(timeout: 10))
            capture(app, "auth-register-methods-" + language)
            app.buttons["auth.register.emailMethod"].tap()
            XCTAssertTrue(app.buttons["auth.register.federalState"].waitForExistence(timeout: 10))
            capture(app, "auth-register-fields-" + language)
            app.terminate()
        }
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

}
