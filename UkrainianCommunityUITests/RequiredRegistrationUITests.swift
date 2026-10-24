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
            XCTAssertTrue(app.buttons["auth.register.continue"].firstMatch.exists)
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
            XCTAssertEqual(app.buttons["auth.provider.apple"].label, language == "uk" ? "Продовжити з Apple" : "Mit Apple fortfahren")
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
    func testSignInLocksOtherMethodsAndKeepsCredentialsAfterNetworkFailure() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launchEnvironment = ["UITestForceSignedOutSession": "1", "UITestAuthDelayedFailure": "1",
            "UITestResetUserSettings": "1", "UITestAppLanguage": "uk", "UITestAppAppearance": "dark"]
        app.launch()
        XCTAssertTrue(app.buttons["auth.landing.signIn"].waitForExistence(timeout: 20))
        app.buttons["auth.landing.signIn"].tap()
        let email = app.textFields.firstMatch
        XCTAssertTrue(email.waitForExistence(timeout: 10))
        email.tap()
        email.typeText("member@example.test")
        let password = app.secureTextFields.firstMatch
        password.tap()
        password.typeText("test-password")
        app.swipeUp()
        let submit = app.buttons["auth.login.submit"].firstMatch
        XCTAssertTrue(submit.isEnabled)
        submit.tap()
        XCTAssertFalse(app.buttons["auth.login.changeMethod"].isEnabled)
        XCTAssertFalse(app.buttons["auth.login.register"].isEnabled)
        XCTAssertFalse(app.buttons["auth.login.forgotPassword"].isEnabled)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "auth.login.error").firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["auth.login.changeMethod"].isEnabled)
        XCTAssertTrue(submit.isEnabled)
        XCTAssertEqual(email.value as? String, "member@example.test")
        capture(app, "auth-network-retry-preserved")
        app.terminate()
    }

    @MainActor
    func testProtectedRolesCanResolveSecurityBeforeUnavailableLegalVerification() {
        for role in ["owner", "admin"] {
            let app = XCUIApplication()
            app.launchArguments = ["-ui-testing"]
            app.launchEnvironment = ["UITestResetUserSettings": "1", "UITestAppLanguage": "uk",
                "UITestAppAppearance": "dark", "UITestOwnerSecondFactor": "missing",
                "UITestStartupSecurityBeforeLegal": "1", "UITestLegalReverification": "cold-offline", "UITestResetAppLock": "1"]
            if role == "owner" { app.launchEnvironment["UITestForceOwnerSession"] = "1" }
            else { app.launchEnvironment["UITestProfileRole"] = "admin" }
            app.launch()
            XCTAssertTrue(app.otherElements["auth.mfa.privilegedRequirement"].firstMatch.waitForExistence(timeout: 20))
            XCTAssertFalse(app.buttons["startup.retry"].exists)
            XCTAssertTrue(app.buttons["auth.mfa.privilegedRequirement.retry"].firstMatch.waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["auth.mfa.privilegedRequirement.enroll"].exists, "Unknown factor state must not be presented as no authenticator")
            capture(app, "startup-security-before-legal-" + role)
            app.terminate()
        }
    }

    @MainActor
    func testProtectedStartupNeverShowsRequirementOrPrematureEmptyNews() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launchEnvironment = ["UITestForceOwnerSession": "1", "UITestStartupSecurityDelay": "1",
            "UITestNewsBrowseDelay": "1", "UITestResetUserSettings": "1", "UITestAppLanguage": "uk",
            "UITestAppAppearance": "light", "UITestResetAppLock": "1"]
        app.launch()
        let verifying = app.otherElements["startup.security.verifying"].firstMatch
        XCTAssertTrue(verifying.waitForExistence(timeout: 10))
        XCTAssertFalse(app.otherElements["auth.mfa.privilegedRequirement"].exists)
        capture(app, "protected-startup-neutral-verification")
        let loading = app.descendants(matching: .any)["home.news.loading"].firstMatch
        XCTAssertTrue(loading.waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["home.news.empty"].exists)
        capture(app, "news-first-load-no-false-empty")
        XCTAssertTrue(app.buttons["home.card.news-news-1"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(app.otherElements["auth.mfa.privilegedRequirement"].exists)
        XCTAssertEqual(app.tabBars.buttons.count, 5)
        capture(app, "protected-startup-ready-news")
    }

    @MainActor
    func testColdStartupRetainsOneSplashAcrossSecurityAndLegalChecks() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launchEnvironment = ["UITestForceOwnerSession": "1", "UITestStartupSecurityDelay": "1",
            "UITestLegalReverification": "cold-slow", "UITestResetUserSettings": "1",
            "UITestAppLanguage": "uk", "UITestAppAppearance": "dark", "UITestResetAppLock": "1"]
        app.launch()
        let security = app.otherElements["startup.security.verifying"].firstMatch
        XCTAssertTrue(security.waitForExistence(timeout: 10))
        let instance = security.value as? String
        XCTAssertNotNil(instance)
        XCTAssertFalse(instance?.isEmpty ?? true)
        let legal = app.otherElements["startup.access.verifying"].firstMatch
        XCTAssertTrue(legal.waitForExistence(timeout: 10))
        XCTAssertEqual(legal.value as? String, instance, "Changing startup phase must not recreate the splash or restart its video/logo")
        capture(app, "same-splash-during-legal-check")
        XCTAssertTrue(app.buttons["home.card.news-news-1"].firstMatch.waitForExistence(timeout: 20))
        XCTAssertFalse(legal.exists)
        XCTAssertFalse(security.exists)
        capture(app, "one-transition-to-news-dark")
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

}
