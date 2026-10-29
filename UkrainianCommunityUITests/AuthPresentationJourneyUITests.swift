import XCTest

@MainActor
final class AuthPresentationJourneyUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testModeSwitchingAndPasswordVisibilityInBothLanguages() {
        for language in ["uk", "de"] {
            let app = launch(language: language)
            app.buttons["auth.landing.signIn"].tap()
            let email = app.textFields["auth.login.email"]
            XCTAssertTrue(email.waitForExistence(timeout: 10))
            email.tap(); email.typeText("member@example.test")
            let password = app.secureTextFields["auth.login.password"]
            password.coordinate(withNormalizedOffset: .init(dx: 0.2, dy: 0.5)).tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            password.typeText("Valid-password-2026")
            app.buttons["auth.login.password.visibility"].firstMatch.tap()
            XCTAssertEqual(app.textFields["auth.login.password"].value as? String, "Valid-password-2026")
            XCTAssertTrue(app.keyboards.firstMatch.exists)
            XCTAssertFalse(app.sheets.firstMatch.exists, "Revealing an unsubmitted password must not summon a save-password sheet")
            app.buttons["auth.login.password.visibility"].firstMatch.tap()
            XCTAssertTrue(app.secureTextFields["auth.login.password"].exists)
            capture(app, "login-keyboard-" + language)
            app.swipeUp()
            let register = app.buttons["auth.login.register"]
            reveal(register, in: app); register.tap()
            XCTAssertTrue(app.textFields["auth.register.email"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.textFields["auth.register.email"].value as? String, "member@example.test")
            let signIn = app.buttons["auth.register.signIn"].firstMatch
            reveal(signIn, in: app); signIn.tap()
            XCTAssertTrue(app.buttons["auth.login.submit"].waitForExistence(timeout: 10))
            app.navigationBars.buttons.firstMatch.tap()
            XCTAssertTrue(app.buttons["auth.landing.signIn"].waitForExistence(timeout: 10), "One back action must reach method selection")
            capture(app, "auth-methods-" + language)
            app.terminate()
        }
    }

    func testRegistrationStepsPreserveDataAndRequireReviewedDocuments() {
        let app = launch(language: "uk")
        openRegistration(app)
        fillDetails(app)
        let next = app.buttons["auth.register.continue"]
        reveal(next, in: app); capture(app, "details-before-continue"); XCTAssertTrue(next.isEnabled); next.tap()
        XCTAssertTrue(app.staticTexts["auth.register.confirmationEmail"].waitForExistence(timeout: 10))
        let terms = app.switches["auth.consent.terms"]
        reveal(terms, in: app); XCTAssertFalse(terms.isEnabled)
        XCTAssertEqual(terms.value as? String, "0")
        for link in ["auth.consent.termsLink", "auth.consent.privacyLink"] {
            let document = app.buttons[link]
            reveal(document, in: app); document.tap()
            let reviewed = app.buttons["legal.document.reviewComplete"]
            reveal(reviewed, in: app, attempts: 45); XCTAssertTrue(reviewed.isHittable); reviewed.tap()
        }
        for id in ["auth.consent.terms", "auth.consent.privacy", "auth.consent.age"] {
            let toggle = app.switches[id]
            reveal(toggle, in: app); XCTAssertTrue(toggle.isEnabled); toggle.tap()
        }
        let analytics = app.switches["auth.register.analyticsConsent"]
        reveal(analytics, in: app); XCTAssertEqual(analytics.value as? String, "0")
        let submit = app.buttons["auth.register.submit"]
        reveal(submit, in: app); XCTAssertTrue(submit.isEnabled)
        capture(app, "registration-ready-without-optional-consent")
        // Do not submit: this journey tests presentation and legal gating, not account creation.
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.textFields["auth.register.displayName"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["auth.register.displayName"].value as? String, "Test Person")
        XCTAssertEqual(app.textFields["auth.register.email"].value as? String, "member@example.test")
        reveal(next, in: app); next.tap()
        reveal(submit, in: app); XCTAssertTrue(submit.isEnabled, "Back/forward must preserve reviewed versions and explicit agreements")
    }

    func testResetPrefillsEmailAndOffersReturnAfterSuccess() {
        let app = launch(language: "de", resetSuccess: true)
        app.buttons["auth.landing.signIn"].tap()
        let email = app.textFields["auth.login.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 10))
        email.tap(); email.typeText("member@example.test")
        app.swipeUp()
        let forgot = app.buttons["auth.login.forgotPassword"]
        reveal(forgot, in: app); forgot.tap()
        XCTAssertTrue(app.textFields["auth.reset.email"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["auth.reset.email"].value as? String, "member@example.test")
        app.buttons["auth.reset.submit"].tap()
        let back = app.buttons["auth.reset.backToSignIn"]
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["auth.reset.submit"].isEnabled)
        capture(app, "password-reset-success-de")
        back.tap()
        XCTAssertTrue(app.textFields["auth.login.email"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["auth.login.email"].value as? String, "member@example.test")
    }

    func testGermanLargeTextRegistrationDetailsRemainUsable() {
        let app = launch(language: "de", large: true)
        openRegistration(app)
        fillDetails(app)
        let next = app.buttons["auth.register.continue"]
        reveal(next, in: app); XCTAssertTrue(next.isHittable); XCTAssertTrue(next.isEnabled)
        capture(app, "registration-details-de-dark-large")
        next.tap()
        let terms = app.buttons["auth.consent.termsLink"]
        reveal(terms, in: app); XCTAssertTrue(terms.isHittable)
        capture(app, "registration-documents-de-dark-large")
    }

    private func launch(language: String, large: Bool = false, resetSuccess: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-UIPreferredContentSizeCategoryName",
            large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launchEnvironment = ["UITestForceSignedOutSession": "1", "UITestResetUserSettings": "1",
            "UITestAppLanguage": language, "UITestAppAppearance": language == "de" ? "dark" : "light"]
        if resetSuccess { app.launchEnvironment["UITestAuthDelayedFailure"] = "1"; app.launchEnvironment["UITestResetSuccess"] = "1" }
        app.launch()
        XCTAssertTrue(app.buttons["auth.landing.signIn"].waitForExistence(timeout: 20))
        return app
    }
    private func openRegistration(_ app: XCUIApplication) {
        let create = app.buttons["auth.landing.register"]
        reveal(create, in: app); create.tap()
        let method = app.buttons["auth.register.emailMethod"]
        XCTAssertTrue(method.waitForExistence(timeout: 10)); method.tap()
        XCTAssertTrue(app.textFields["auth.register.displayName"].waitForExistence(timeout: 10))
    }
    private func fillDetails(_ app: XCUIApplication) {
        for (id, value) in [("auth.register.displayName", "Test Person"), ("auth.register.email", "member@example.test")] {
            let field = app.textFields[id]; reveal(field, in: app); field.tap(); field.typeText(value)
        }
        for id in ["auth.register.password", "auth.register.repeatedPassword"] {
            let field = app.secureTextFields[id]; reveal(field, in: app)
            field.coordinate(withNormalizedOffset: .init(dx: 0.2, dy: 0.5)).tap()
            if dismissPasswordSuggestion(in: app) { field.coordinate(withNormalizedOffset: .init(dx: 0.2, dy: 0.5)).tap() }
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            field.typeText("V")
            let suggestionDismissed = dismissPasswordSuggestion(in: app)
            field.tap()
            field.typeText(suggestionDismissed ? "Valid-password-2026" : "alid-password-2026")
        }
        app.swipeUp()
        let region = app.buttons["auth.register.federalState"]
        reveal(region, in: app); region.tap()
        let vienna = app.buttons["auth.register.region.wien"].firstMatch
        reveal(vienna, in: app); XCTAssertTrue(vienna.isHittable); vienna.tap()
    }
    private func dismissPasswordSuggestion(in app: XCUIApplication) -> Bool {
        var dismissed = false
        // Password AutoFill may offer to generate a password for .newPassword.
        // Keep production AutoFill enabled and choose manual entry in this journey.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for surface in [app, springboard] {
            let close = surface.buttons.matching(NSPredicate(format: "label == 'Schließen' OR label == 'Close' OR label == 'Закрити'")).firstMatch
            if close.exists && close.isHittable { close.tap(); dismissed = true }
        }
        return dismissed
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, attempts: Int = 25) {
        for _ in 0..<attempts {
            if element.exists && element.isHittable { return }
            if element.exists && element.frame.midY < app.frame.minY + 110 { app.swipeDown() }
            else { app.swipeUp() }
        }
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
