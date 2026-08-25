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

    private func launchOwnerApp(
        language: String = "de",
        appearance: String? = nil,
        contentSizeCategory: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launchEnvironment["UITestResetUserSettings"] = "1"
        app.launchEnvironment["UITestAppLanguage"] = language
        app.launchEnvironment["UITestForceOwnerSession"] = "1"
        if let appearance {
            app.launchEnvironment["UITestAppAppearance"] = appearance
        }
        if let contentSizeCategory {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSizeCategory]
        }
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
        if tabButton.isHittable {
            tabButton.tap()
        } else if let tabIndex = rootTabs.firstIndex(of: tab) {
            // On iOS 26 the Liquid Glass tab button can briefly report an
            // invalid XCTest hit point even though its visible TabBar frame is
            // already stable. Tapping the corresponding TabBar segment keeps
            // the test deterministic without adding product-only UI hooks.
            let horizontalOffset = (CGFloat(tabIndex) + 0.5) / CGFloat(rootTabs.count)
            tabBar.coordinate(
                withNormalizedOffset: CGVector(dx: horizontalOffset, dy: 0.5)
            ).tap()
        } else {
            XCTFail("Unknown root tab index: \(tab.tabIdentifier)", file: file, line: line)
            return
        }

        XCTAssertTrue(app.otherElements[tab.screenIdentifier].waitForExistence(timeout: timeout), file: file, line: line)
        XCTAssertEqual(app.state, .runningForeground, file: file, line: line)
    }

    private func rootTabButton(_ tab: MainTabSpec, in tabBar: XCUIElement) -> XCUIElement {
        let identifiedButton = tabBar.buttons[tab.tabIdentifier]
        if identifiedButton.waitForExistence(timeout: 1) {
            return identifiedButton
        }

        // Some iOS 26 accessibility-size tab layouts omit the Label's custom
        // identifier. The tab order is a product contract and is verified by
        // a dedicated UI test, so its stable index is a language-neutral
        // fallback (unlike a hard-coded localized label).
        guard let tabIndex = rootTabs.firstIndex(of: tab) else {
            return tabBar.buttons[tab.tabLabel]
        }
        return tabBar.buttons.element(boundBy: tabIndex)
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
        while (!element.exists || !element.isHittable) && remainingSwipes > 0 {
            app.swipeUp()
            remainingSwipes -= 1
        }
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func openOwnerAnalytics(in app: XCUIApplication) {
        tapRootTab(rootTabs[3], in: app)

        let analyticsLink = element("profile.owner.analytics", in: app)
        scrollToElement(analyticsLink, in: app, maxSwipes: 14)
        XCTAssertTrue(analyticsLink.exists)
        XCTAssertTrue(analyticsLink.isHittable)
        analyticsLink.tap()

        let analyticsScreen = element("screen.ownerAnalytics", in: app)
        if !analyticsScreen.waitForExistence(timeout: 10), analyticsLink.isHittable {
            // After a long profile scroll, iOS 26 can occasionally consume the
            // first tap while the scroll view is still settling. Retry only
            // when navigation demonstrably did not happen.
            analyticsLink.tap()
        }
        XCTAssertTrue(
            analyticsScreen.waitForExistence(timeout: 10),
            "Owner analytics did not open after tapping its profile link"
        )
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
        XCTAssertTrue(
            eventCard.waitForExistence(timeout: 20),
            "The deterministic mock event did not finish loading"
        )
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

        let privacyLink = app.buttons["profile.legal.privacy"].firstMatch
        let termsLink = app.buttons["profile.legal.terms"].firstMatch
        scrollToElement(termsLink, in: app)
        scrollToElement(privacyLink, in: app)
        XCTAssertTrue(termsLink.exists)
        XCTAssertTrue(privacyLink.exists)
    }

    @MainActor
    func testProfileLogoutRowRespondsAcrossItsFullWidth() throws {
        let app = launchAuthenticatedApp()
        assertRootScreen(screenIdentifier: "screen.profile", tabLabel: "Profil", in: app)

        let logoutButton = element("profile.logout.button", in: app)
        scrollToElement(logoutButton, in: app, maxSwipes: 14)
        XCTAssertTrue(logoutButton.exists)
        XCTAssertTrue(logoutButton.isHittable)

        logoutButton.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        app.alerts.firstMatch.buttons["Abbrechen"].tap()

        logoutButton.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testOwnerAnalyticsSearchPeriodAndDetailJourney() throws {
        let app = launchOwnerApp()
        openOwnerAnalytics(in: app)

        XCTAssertTrue(element("ownerAnalytics.updatedAt", in: app).waitForExistence(timeout: 10))

        let searchField = element("ownerAnalytics.search", in: app)
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("zzzz-no-match")
        XCTAssertTrue(element("ownerAnalytics.search.empty", in: app).waitForExistence(timeout: 5))

        let clearSearchButton = app.buttons["Suche löschen"].firstMatch
        XCTAssertTrue(clearSearchButton.waitForExistence(timeout: 5))
        clearSearchButton.tap()
        XCTAssertFalse(element("ownerAnalytics.search.empty", in: app).exists)

        let sevenDayButton = app.buttons["7 Tage"].firstMatch
        XCTAssertTrue(sevenDayButton.waitForExistence(timeout: 5))
        sevenDayButton.tap()

        let trendChart = element("ownerAnalytics.trendChart", in: app)
        scrollToElement(trendChart, in: app, maxSwipes: 10)
        XCTAssertTrue(trendChart.exists)

        let contentLink = element("ownerAnalytics.content.news.news-language-courses-update", in: app)
        scrollToElement(contentLink, in: app, maxSwipes: 14)
        XCTAssertTrue(contentLink.exists)
        XCTAssertTrue(contentLink.isHittable)
        contentLink.tap()

        XCTAssertTrue(element("screen.ownerAnalytics.contentDetail", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(element("ownerAnalytics.detail.periodPicker", in: app).waitForExistence(timeout: 5))
        attachScreenshot(named: "Owner Analytics Detail", from: app)
    }

    @MainActor
    func testOwnerAnalyticsSupportsDarkUkrainianAccessibilityText() throws {
        let app = launchOwnerApp(
            language: "uk",
            appearance: "dark",
            contentSizeCategory: "UICTContentSizeCategoryAccessibilityXXXL"
        )
        openOwnerAnalytics(in: app)

        XCTAssertTrue(element("ownerAnalytics.periodPicker", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(element("ownerAnalytics.updatedAt", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(element("ownerAnalytics.search", in: app).waitForExistence(timeout: 10))
        XCTAssertEqual(app.state, .runningForeground)
        attachScreenshot(named: "Owner Analytics Ukrainian Dark AX", from: app)
    }
}

private enum AppStringsPlaceholder {
    static let acceptTermsDE = "Ich akzeptiere die Nutzungsbedingungen"
    static let acceptPrivacyDE = "Ich akzeptiere die Datenschutzerklärung"
}

private struct MainTabSpec: Equatable {
    let screenIdentifier: String
    let tabIdentifier: String
    let tabLabel: String
}
