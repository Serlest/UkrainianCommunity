//
//  UkrainianCommunityUITests.swift
//  UkrainianCommunityUITests
//
//  Created by Philipp Timofeev on 28.04.26.
//

import XCTest

final class UkrainianCommunityUITests: XCTestCase {
    private let expectedTabs = ["Start", "Veranstaltungen", "Organisationen", "Guide", "Profil"]
    private let stressTabs: [MainTabSpec] = [
        MainTabSpec(screenIdentifier: "screen.home", tabIdentifier: "tab.home", tabLabel: "Start"),
        MainTabSpec(screenIdentifier: "screen.events", tabIdentifier: "tab.events", tabLabel: "Veranstaltungen"),
        MainTabSpec(screenIdentifier: "screen.organizations", tabIdentifier: "tab.organizations", tabLabel: "Organisationen"),
        MainTabSpec(screenIdentifier: "screen.guide", tabIdentifier: "tab.guide", tabLabel: "Guide"),
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
        let tabBar = app.tabBars.firstMatch
        let tabButton = tabBar.buttons[tabLabel]
        XCTAssertTrue(tabButton.waitForExistence(timeout: 10), file: file, line: line)
        tabButton.tap()
        XCTAssertTrue(app.otherElements[screenIdentifier].waitForExistence(timeout: 10), file: file, line: line)
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

        let identifierButton = tabBar.buttons[tab.tabIdentifier]
        let tabButton = identifierButton.exists ? identifierButton : tabBar.buttons[tab.tabLabel]
        XCTAssertTrue(tabButton.waitForExistence(timeout: timeout), file: file, line: line)
        tabButton.tap()

        XCTAssertTrue(app.otherElements[tab.screenIdentifier].waitForExistence(timeout: timeout), file: file, line: line)
        XCTAssertEqual(app.state, .runningForeground, file: file, line: line)
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
    func testTabBarShowsFinalTabOrderWithoutLegacyTabs() throws {
        let app = launchApp()
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10))

        let visibleButtons = tabBar.buttons.allElementsBoundByIndex
        XCTAssertEqual(visibleButtons.count, expectedTabs.count)

        for (index, expectedTitle) in expectedTabs.enumerated() {
            XCTAssertEqual(visibleButtons[index].label, expectedTitle)
        }

        XCTAssertFalse(tabBar.buttons["Neuigkeiten"].exists)
        XCTAssertFalse(tabBar.buttons["Community"].exists)
        XCTAssertFalse(tabBar.buttons["Marketplace"].exists)
    }

    @MainActor
    func testEachTabOpensExpectedRootScreen() throws {
        let app = launchApp()
        assertRootScreen(screenIdentifier: "screen.home", tabLabel: "Start", in: app)
        assertRootScreen(screenIdentifier: "screen.events", tabLabel: "Veranstaltungen", in: app)
        assertRootScreen(screenIdentifier: "screen.organizations", tabLabel: "Organisationen", in: app)
        assertRootScreen(screenIdentifier: "screen.guide", tabLabel: "Guide", in: app)
        assertRootScreen(screenIdentifier: "screen.profile", tabLabel: "Profil", in: app)
    }

    @MainActor
    // Navigation stability stress test. Run manually from Xcode or CI when UI
    // test execution is available; the local run was blocked by Xcode
    // cancellation, not by an XCTest failure.
    func testMainNavigationStressRemainsStable() throws {
        let app = launchApp()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))

        for _ in 0..<12 {
            for tab in stressTabs {
                tapRootTab(tab, in: app, timeout: 5)
            }
        }

        tapRootTab(stressTabs[1], in: app)
        let eventCard = app.buttons["event.card.event-1"]
        if eventCard.waitForExistence(timeout: 5) {
            eventCard.tap()
            XCTAssertTrue(app.buttons["event.register.event-1"].waitForExistence(timeout: 10))
            navigateBackIfPossible(in: app)
            XCTAssertTrue(app.otherElements["screen.events"].waitForExistence(timeout: 10))
        }

        tapRootTab(stressTabs[3], in: app)
        tapRootTab(stressTabs[4], in: app)
        tapRootTab(stressTabs[0], in: app)

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
        XCTAssertTrue(app.buttons["auth.login.submit"].waitForExistence(timeout: 10))
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
