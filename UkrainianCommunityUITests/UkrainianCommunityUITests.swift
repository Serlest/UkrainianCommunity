//
//  UkrainianCommunityUITests.swift
//  UkrainianCommunityUITests
//
//  Created by Philipp Timofeev on 28.04.26.
//

import XCTest

final class UkrainianCommunityUITests: XCTestCase {
    private let rootTabs: [MainTabSpec] = [
        MainTabSpec(screenIdentifier: "screen.home", tabIdentifier: "tab.home", tabLabel: "Start"),
        MainTabSpec(screenIdentifier: "screen.events", tabIdentifier: "tab.events", tabLabel: "Veranstaltungen"),
        MainTabSpec(screenIdentifier: "screen.organizations", tabIdentifier: "tab.organizations", tabLabel: "Organisationen"),
        MainTabSpec(screenIdentifier: "screen.profile", tabIdentifier: "tab.profile", tabLabel: "Profil")
    ]

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launchEnvironment["UITestResetUserSettings"] = "1"
        app.launchEnvironment["UITestAppLanguage"] = "de"
        app.launchEnvironment["UITestForceGuestSession"] = "1"
        app.launch()
        return app
    }

    private func launchAuthenticatedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launchEnvironment["UITestResetUserSettings"] = "1"
        app.launchEnvironment["UITestAppLanguage"] = "de"
        app.launchEnvironment["UITestForceAuthenticatedSession"] = "1"
        app.launch()
        return app
    }

    private func attachScreenshot(
        named name: String,
        from app: XCUIApplication,
        lifetime: XCTAttachment.Lifetime = .keepAlways
    ) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = lifetime
        add(attachment)
    }

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    private func assertRootScreen(
        screenIdentifier: String,
        tabLabel: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let tab = rootTabs.first(where: {
            $0.screenIdentifier == screenIdentifier && $0.tabLabel == tabLabel
        }) else {
            XCTFail("Unknown root tab: \(screenIdentifier)", file: file, line: line)
            return
        }

        tapRootTab(tab, in: app, file: file, line: line)
    }

    private func tapRootTab(
        _ tab: MainTabSpec,
        in app: XCUIApplication,
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: timeout), file: file, line: line)

        let tabButton = rootTabButton(tab, in: tabBar)
        XCTAssertTrue(tabButton.waitForExistence(timeout: timeout), file: file, line: line)
        tabButton.tap()

        XCTAssertTrue(app.otherElements[tab.screenIdentifier].waitForExistence(timeout: timeout), file: file, line: line)
        XCTAssertEqual(app.state, .runningForeground, file: file, line: line)
    }

    private func rootTabButton(_ tab: MainTabSpec, in tabBar: XCUIElement) -> XCUIElement {
        let identifiedButton = tabBar.buttons[tab.tabIdentifier]
        return identifiedButton.waitForExistence(timeout: 1)
            ? identifiedButton
            : tabBar.buttons[tab.tabLabel]
    }

    private func navigateBackIfPossible(in app: XCUIApplication) {
        let navigationBar = app.navigationBars.firstMatch
        guard navigationBar.waitForExistence(timeout: 3) else { return }

        let backButton = navigationBar.buttons.element(boundBy: 0)
        if backButton.exists && backButton.isHittable {
            backButton.tap()
        }
    }

    private func scrollToElement(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 6) {
        var remainingSwipes = maxSwipes
        while !element.exists && remainingSwipes > 0 {
            app.swipeUp()
            remainingSwipes -= 1
        }
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    func testAppLaunchesAndShowsTabBar() throws {
        let app = launchApp()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
    }

    @MainActor
    func testStartupSplashTransitionsToMainInterface() throws {
        let app = launchApp()
        let logo = app.images["startup.logo"]
        let tabBar = app.tabBars.firstMatch

        // XCTest can attach after the short production splash has already
        // completed. If it is still visible, verify that it transitions away;
        // the required startup contract is the appearance of the main UI.
        if logo.waitForExistence(timeout: 2) {
            attachScreenshot(named: "Startup Splash", from: app)
            XCTAssertTrue(
                logo.waitForNonExistence(timeout: 8),
                "Startup logo did not transition away"
            )
        }

        XCTAssertTrue(
            tabBar.waitForExistence(timeout: 10),
            "Main tab bar did not appear after startup"
        )
        XCTAssertEqual(app.state, .runningForeground)
        attachScreenshot(named: "Main Interface After Splash", from: app)
    }

    @MainActor
    func testTabBarShowsFinalTabOrderWithoutLegacyTabs() throws {
        let app = launchApp()
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))

        let expectedButtons = rootTabs.map { tab in
            (tab: tab, button: rootTabButton(tab, in: tabBar))
        }
        for expectedButton in expectedButtons {
            XCTAssertTrue(
                expectedButton.button.waitForExistence(timeout: 2),
                "Missing root tab: \(expectedButton.tab.tabIdentifier)"
            )
        }

        let visualOrder = expectedButtons
            .sorted { $0.button.frame.minX < $1.button.frame.minX }
            .map { $0.tab.tabIdentifier }
        XCTAssertEqual(visualOrder, rootTabs.map(\.tabIdentifier))

        XCTAssertFalse(tabBar.buttons["Neuigkeiten"].exists)
        XCTAssertFalse(tabBar.buttons["Community"].exists)
        XCTAssertFalse(tabBar.buttons["Marketplace"].exists)
    }

    @MainActor
    func testEachTabOpensExpectedRootScreen() throws {
        let app = launchApp()
        for tab in rootTabs {
            tapRootTab(tab, in: app)
        }

        app.terminate()

        let authenticatedApp = launchAuthenticatedApp()
        tapRootTab(rootTabs[3], in: authenticatedApp)
        XCTAssertTrue(authenticatedApp.otherElements["profile.account.hero"].waitForExistence(timeout: 10))
        XCTAssertFalse(authenticatedApp.otherElements["profile.guest.card"].exists)

        let recentViewsButton = authenticatedApp.buttons["profile.quick_action.recent_views"]
        scrollToElement(recentViewsButton, in: authenticatedApp)
        XCTAssertTrue(recentViewsButton.waitForExistence(timeout: 10))
        recentViewsButton.tap()
        XCTAssertTrue(authenticatedApp.otherElements["profile.recent_views.screen"].waitForExistence(timeout: 10))
        navigateBackIfPossible(in: authenticatedApp)

        let activityHistoryButton = authenticatedApp.buttons["profile.quick_action.activity_history"]
        scrollToElement(activityHistoryButton, in: authenticatedApp)
        XCTAssertTrue(activityHistoryButton.waitForExistence(timeout: 10))
        activityHistoryButton.tap()
        XCTAssertTrue(authenticatedApp.otherElements["profile.activity_history.screen"].waitForExistence(timeout: 10))
    }

    @MainActor
    // Navigation stability stress test. Run manually from Xcode or CI when UI
    // test execution is available; the local run was blocked by Xcode
    // cancellation, not by an XCTest failure.
    func testMainNavigationStressRemainsStable() throws {
        let app = launchApp()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))

        for _ in 0..<12 {
            for tab in rootTabs {
                tapRootTab(tab, in: app, timeout: 5)
            }
        }

        tapRootTab(rootTabs[1], in: app)
        let eventCard = app.buttons["event.card.event-1"]
        if eventCard.waitForExistence(timeout: 5) {
            eventCard.tap()
            XCTAssertTrue(app.buttons["event.register.event-1"].waitForExistence(timeout: 10))
            navigateBackIfPossible(in: app)
            XCTAssertTrue(app.otherElements["screen.events"].waitForExistence(timeout: 10))
        }

        tapRootTab(rootTabs[2], in: app)
        tapRootTab(rootTabs[3], in: app)
        tapRootTab(rootTabs[0], in: app)

        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
    }

    @MainActor
    func testPublicEventsScreenDoesNotExposeManagementControls() throws {
        let app = launchApp()
        assertRootScreen(screenIdentifier: "screen.events", tabLabel: "Veranstaltungen", in: app)

        XCTAssertFalse(app.navigationBars.buttons["Erstellen"].exists)
        XCTAssertFalse(app.navigationBars.buttons["Bearbeiten"].exists)
        XCTAssertFalse(app.navigationBars.buttons["Löschen"].exists)
    }

    @MainActor
    func testPublicOrganizationsScreenDoesNotExposeManagementControls() throws {
        let app = launchApp()
        assertRootScreen(screenIdentifier: "screen.organizations", tabLabel: "Organisationen", in: app)

        XCTAssertFalse(app.navigationBars.buttons["Erstellen"].exists)
        XCTAssertFalse(app.navigationBars.buttons["Bearbeiten"].exists)
        XCTAssertFalse(app.navigationBars.buttons["Löschen"].exists)
    }

    @MainActor
    func testProfileTabOpensProfileScreen() throws {
        let app = launchApp()
        assertRootScreen(screenIdentifier: "screen.profile", tabLabel: "Profil", in: app)
    }

    @MainActor
    func testGuestProfileShowsAuthEntryPoints() throws {
        let app = launchApp()
        assertRootScreen(screenIdentifier: "screen.profile", tabLabel: "Profil", in: app)

        let signInButton = app.buttons["Anmelden"].firstMatch
        XCTAssertTrue(signInButton.waitForExistence(timeout: 10))
        signInButton.tap()
        XCTAssertTrue(app.navigationBars["Anmelden"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testGuestProtectedEventActionsShowAuthRequiredAlert() throws {
        let app = launchApp()
        assertRootScreen(screenIdentifier: "screen.events", tabLabel: "Veranstaltungen", in: app)

        let eventCard = app.buttons["event.card.event-1"]
        XCTAssertTrue(eventCard.waitForExistence(timeout: 10))
        eventCard.tap()

        let registerButton = app.buttons["event.register.event-1"]
        XCTAssertTrue(registerButton.waitForExistence(timeout: 10))
        registerButton.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 10))
        app.alerts.firstMatch.buttons["Anmelden"].tap()
        XCTAssertTrue(app.buttons["auth.login.submit"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testGuestCreateAccountOpensRegistrationScreen() throws {
        let app = launchApp()
        assertRootScreen(screenIdentifier: "screen.profile", tabLabel: "Profil", in: app)

        let createAccountButton = app.buttons["Konto erstellen"].firstMatch
        XCTAssertTrue(createAccountButton.waitForExistence(timeout: 10))
        createAccountButton.tap()
        XCTAssertTrue(app.buttons["auth.register.submit"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testRegistrationShowsConsentControls() throws {
        let app = launchApp()
        assertRootScreen(screenIdentifier: "screen.profile", tabLabel: "Profil", in: app)

        app.buttons["Konto erstellen"].firstMatch.tap()
        XCTAssertTrue(app.buttons["auth.register.submit"].waitForExistence(timeout: 10))
        let termsSwitch = app.switches[AppStringsPlaceholder.acceptTermsDE]
        scrollToElement(termsSwitch, in: app)
        XCTAssertTrue(termsSwitch.exists)
    }

    @MainActor
    func testProfileSettingsContainsLegalRows() throws {
        let app = launchApp()
        assertRootScreen(screenIdentifier: "screen.profile", tabLabel: "Profil", in: app)

        let privacyLabel = app.staticTexts["Datenschutz"].firstMatch
        let termsLabel = app.staticTexts["Nutzungsbedingungen"].firstMatch
        scrollToElement(privacyLabel, in: app)
        scrollToElement(termsLabel, in: app)
        XCTAssertTrue(privacyLabel.exists)
        XCTAssertTrue(termsLabel.exists)
    }
}

private enum AppStringsPlaceholder {
    static let acceptTermsDE = "Ich akzeptiere die Nutzungsbedingungen"
    static let acceptPrivacyDE = "Ich akzeptiere die Datenschutzerklärung"
}

private struct MainTabSpec {
    let screenIdentifier: String
    let tabIdentifier: String
    let tabLabel: String
}
