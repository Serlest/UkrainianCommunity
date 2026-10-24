import XCTest

@MainActor
final class PersonalSectionsAuditUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testAllUsableRolesReachEachPersonalSection() {
        for role in ["owner", "admin", "org-owner", "org-admin", "org-moderator", "mixed", "member", "warned"] {
            let german = ["admin", "org-admin", "mixed"].contains(role)
            let app = launch(role: role, language: german ? "de" : "uk", dark: ["admin", "org-owner", "org-moderator"].contains(role))
            let tabs = app.tabBars.buttons
            XCTAssertTrue(tabs.element(boundBy: 4).waitForExistence(timeout: 20)); tabs.element(boundBy: 4).tap()
            for (route, field) in [("savedContent", "saved.search"), ("followedOrganizations", "subscriptions.search"),
                                   ("registrations", "registrations.filters"), ("recentViews", "recentViews.search"),
                                   ("activityHistory", "activityHistory.search")] {
                let entry = app.buttons["profile." + route]
                reveal(entry, app); entry.tap()
                let control = route == "registrations" ? app.scrollViews.otherElements[field].firstMatch : app.textFields[field]
                if route == "registrations" {
                    XCTAssertTrue(app.buttons["registrations.filter.upcoming"].waitForExistence(timeout: 8))
                } else { XCTAssertTrue(control.waitForExistence(timeout: 8)) }
                capture(app, "personal-" + role + "-" + route)
                let back = app.buttons["navigation.back"].firstMatch
                XCTAssertTrue(back.waitForExistence(timeout: 5)); back.tap()
            }
            app.terminate()
        }
    }

    func testSavedSearchExplainsNoMatchesAndSubscriptionsTrimQuery() {
        for (language, dark) in [("uk", true), ("de", false)] {
            let app = launch(role: "owner", language: language, dark: dark)
            let profile = app.tabBars.buttons.element(boundBy: 4)
            XCTAssertTrue(profile.waitForExistence(timeout: 20)); profile.tap()
            let saved = app.buttons["profile.savedContent"]
            reveal(saved, app); saved.tap()
            let search = app.textFields["saved.search"]
            XCTAssertTrue(search.waitForExistence(timeout: 8)); search.tap(); search.typeText("zz-no-match\n")
            XCTAssertTrue(app.staticTexts[language == "uk" ? "Нічого не знайдено" : "Nichts gefunden"].firstMatch.waitForExistence(timeout: 5))
            capture(app, "personal-saved-no-results-" + language)
            app.buttons["navigation.back"].firstMatch.tap()
            let subscriptions = app.buttons["profile.followedOrganizations"]
            reveal(subscriptions, app); subscriptions.tap()
            let row = app.buttons["subscriptions.open.org-1"]
            XCTAssertTrue(row.waitForExistence(timeout: 8))
            let field = app.textFields["subscriptions.search"]
            field.tap(); field.typeText(language == "uk" ? "  Тіроль  \n" : "  Tirol  \n")
            XCTAssertTrue(row.exists, "Search must ignore surrounding whitespace")
            capture(app, "personal-subscriptions-trimmed-" + language)
            app.terminate()
        }
    }

    func testUnavailableContentCanBeRemovedWithoutDeletingLiveContent() {
        let app = launch(role: "owner", language: "uk", dark: false, unavailable: true)
        let profile = app.tabBars.buttons.element(boundBy: 4)
        XCTAssertTrue(profile.waitForExistence(timeout: 20)); profile.tap()
        let saved = app.buttons["profile.savedContent"]
        reveal(saved, app); saved.tap()
        let remove = app.buttons["saved.removeUnavailable.news-unavailable-news"]
        reveal(remove, app); capture(app, "personal-unavailable-saved"); remove.tap()
        XCTAssertTrue(remove.waitForNonExistence(timeout: 8))
        XCTAssertTrue(app.buttons["saved.open.news-news-1"].exists)
        app.buttons["navigation.back"].firstMatch.tap()
        let subscriptions = app.buttons["profile.followedOrganizations"]
        reveal(subscriptions, app); subscriptions.tap()
        let unsubscribe = app.buttons["subscriptions.removeUnavailable.unavailable-organization"]
        reveal(unsubscribe, app); unsubscribe.tap()
        let confirm = app.buttons["subscriptions.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); capture(app, "personal-unavailable-unsubscribe-dialog")
        app.buttons["Скасувати"].firstMatch.tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 5))
        XCTAssertTrue(unsubscribe.exists)
        unsubscribe.tap(); XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(unsubscribe.waitForNonExistence(timeout: 8))
        XCTAssertTrue(app.buttons["subscriptions.open.org-1"].exists)
        app.buttons["navigation.back"].firstMatch.tap()
        reveal(subscriptions, app); subscriptions.tap()
        XCTAssertFalse(unsubscribe.exists, "Removal must survive a new read")
    }

    func testEverySectionShowsLoadingFailureAndRecoversWithRetry() {
        let app = launch(role: "owner", language: "uk", dark: true, state: "retry")
        let profile = app.tabBars.buttons.element(boundBy: 4)
        XCTAssertTrue(profile.waitForExistence(timeout: 20)); profile.tap()
        for (route, prefix, row) in [("savedContent", "saved", "saved.open.news-news-1"),
            ("followedOrganizations", "subscriptions", "subscriptions.open.org-1"),
            ("registrations", "registrations", "registrations.open.registration-00"),
            ("recentViews", "recentViews", "recentViews.open.news_news-1"),
            ("activityHistory", "activityHistory", "activityHistory.open.activity-news")] {
            let entry = app.buttons["profile." + route]
            reveal(entry, app); entry.tap()
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: prefix + ".loading").firstMatch.waitForExistence(timeout: 5))
            capture(app, "personal-loading-" + prefix)
            let retry = app.buttons[prefix == "registrations" ? "registrations.retry" : "Спробувати ще раз"].firstMatch
            reveal(retry, app)
            XCTAssertTrue(retry.waitForExistence(timeout: 8)); capture(app, "personal-error-" + prefix); retry.tap()
            XCTAssertTrue(app.buttons[row].waitForExistence(timeout: 8))
            capture(app, "personal-recovered-" + prefix)
            app.buttons["navigation.back"].firstMatch.tap()
        }
    }

    func testEverySectionHasAnHonestEmptyState() {
        let app = launch(role: "owner", language: "de", dark: false, state: "empty")
        let profile = app.tabBars.buttons.element(boundBy: 4)
        XCTAssertTrue(profile.waitForExistence(timeout: 20)); profile.tap()
        for (route, field) in [("savedContent", "saved.search"), ("followedOrganizations", "subscriptions.search"),
            ("registrations", "registrations.filters"), ("recentViews", "recentViews.search"),
            ("activityHistory", "activityHistory.search")] {
            let entry = app.buttons["profile." + route]
            reveal(entry, app); entry.tap()
            if route == "registrations" { XCTAssertTrue(app.buttons["registrations.filter.upcoming"].waitForExistence(timeout: 8)) }
            else { XCTAssertTrue(app.textFields[field].waitForExistence(timeout: 8)) }
            XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", route == "savedContent" ? "saved.open." : route == "followedOrganizations" ? "subscriptions.open." : route + ".open.")).firstMatch.exists)
            capture(app, "personal-empty-" + route)
            app.buttons["navigation.back"].firstMatch.tap()
        }
    }

    func testGuestAndBlockedAccountDoNotExposePersonalRoutes() {
        for role in ["guest", "blocked"] {
            let app = launch(role: role, language: "uk", dark: false)
            let profile = app.tabBars.buttons.element(boundBy: 4)
            XCTAssertTrue(profile.waitForExistence(timeout: 20)); profile.tap()
            if role == "guest" {
                XCTAssertTrue(app.buttons["profile.guest.signIn"].waitForExistence(timeout: 8))
                XCTAssertTrue(app.buttons["profile.guest.register"].exists)
                XCTAssertFalse(app.otherElements["profile.loading"].exists)
            }
            // Traverse the complete profile, rather than checking only its first screen.
            for _ in 0..<7 {
                for route in ["registrations", "savedContent", "followedOrganizations", "recentViews", "activityHistory"] {
                    XCTAssertFalse(app.buttons["profile." + route].exists)
                }
                app.swipeUp()
            }
            capture(app, "personal-denied-" + role)
            if role == "guest" {
                let signIn = app.buttons["profile.guest.signIn"]
                reveal(signIn, app); signIn.tap()
                XCTAssertTrue(app.textFields["auth.login.email"].waitForExistence(timeout: 8))
                app.buttons["Скасувати"].firstMatch.tap()
                XCTAssertTrue(app.buttons["profile.guest.register"].waitForExistence(timeout: 8))
                app.buttons["profile.guest.register"].tap()
                XCTAssertTrue(app.buttons["auth.register.emailMethod"].waitForExistence(timeout: 8))
                app.buttons["Скасувати"].firstMatch.tap()
                XCTAssertTrue(app.buttons["profile.guest.signIn"].waitForExistence(timeout: 8))
            }
            app.terminate()
        }
    }

    func testGuestProfileInGermanDarkLargeText() {
        let app = launch(role: "guest", language: "de", dark: true, large: true)
        let profile = app.tabBars.buttons.element(boundBy: 4)
        XCTAssertTrue(profile.waitForExistence(timeout: 20)); profile.tap()
        let signIn = app.buttons["profile.guest.signIn"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 8)); reveal(signIn, app)
        XCTAssertTrue(signIn.isHittable)
        let register = app.buttons["profile.guest.register"]
        reveal(register, app); XCTAssertTrue(register.isHittable)
        capture(app, "personal-guest-de-dark-large")
    }

    private func launch(role: String, language: String, dark: Bool, unavailable: Bool = false, state: String? = nil, large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityM" : "UICTContentSizeCategoryL"]
        app.launchEnvironment = ["UITestResetUserSettings": "1", "UITestAppLanguage": language,
            "UITestAppAppearance": dark ? "dark" : "light", "UITestResetAppLock": "1", "UITestLegalEvidence": "1",
            "UITestRecentViews": "1", "UITestActivityHistory": "1", "UITestSavedContent": "1", "UITestSubscriptions": "1", "UITestMyRegistrations": "1"]
        if role == "owner" { app.launchEnvironment["UITestForceOwnerSession"] = "1" }
        else if role == "guest" { app.launchEnvironment["UITestForceGuestSession"] = "1" }
        else { app.launchEnvironment["UITestProfileRole"] = role }
        if let state { app.launchEnvironment["UITestPersonalState"] = state }
        if unavailable { app.launchEnvironment["UITestUnavailablePersonalContent"] = "1" }
        app.launch()
        return app
    }
    private func reveal(_ item: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<25 {
            if item.exists && item.isHittable { return }
            let up = !item.exists || item.frame.midY > app.frame.midY
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: up ? 0.8 : 0.3))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: up ? 0.3 : 0.8)))
        }
        XCTFail("Cannot reach \(item)")
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
