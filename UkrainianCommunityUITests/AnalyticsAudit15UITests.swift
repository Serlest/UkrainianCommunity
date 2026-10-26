import XCTest

@MainActor
final class AnalyticsAudit15UITests: XCTestCase {
    private func stateApp(_ state: String, route: String = "overview", language: String = "uk") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launchEnvironment = ["UITestBannerReportAudit":"1", "UITestAnalytics15State":state, "UITestAnalytics15Route":route,
                                 "UITestForceOwnerSession":"1", "UITestAppLanguage":language,
                                 "UITestAppAppearance":language == "de" ? "dark":"light", "UITestResetUserSettings":"1"]
        app.launch(); return app
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<20 { if element.exists && element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
    func testFreshOverviewSelectsSevenAndThirtyDays() {
        let app = stateApp("full", language: "de")
        let seven = app.buttons["7 Tage"].firstMatch
        XCTAssertTrue(seven.waitForExistence(timeout: 10))
        seven.tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: seven)
        let firstSelected = XCTWaiter.wait(for: [selected], timeout: 3) == .completed
        capture(app, "A15-fresh-seven-day-selection")
        XCTAssertTrue(firstSelected)
        let thirty = app.buttons["30 Tage"].firstMatch
        thirty.tap()
        let selectedThirty = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: thirty)
        XCTAssertEqual(XCTWaiter.wait(for: [selectedThirty], timeout: 3), .completed)
        capture(app, "A15-fresh-thirty-day-selection")
        app.terminate()
    }
    func testRootLoadingEmptyErrorAndPartialPresentation() {
        for (state, text) in [("loading","Завантажуємо аналітику..."), ("empty","Даних аналітики ще немає"),
                              ("error","Не вдалося завантажити аналітику")] {
            let app = stateApp(state)
            let expected = app.staticTexts[text].firstMatch
            reveal(expected, app); XCTAssertTrue(expected.exists)
            capture(app, "A15-root-" + state)
            app.terminate()
        }
        let app = stateApp("partial")
        let partial = app.descendants(matching: .any)["ownerAnalytics.partialData"].firstMatch
        reveal(partial, app); XCTAssertTrue(partial.exists)
        capture(app, "A15-root-partial")
        app.terminate()
    }
    func testNewsEventAndOrganizationDetailAllSectionsAndEmptyErrorStates() {
        for route in ["news", "event", "organization"] {
            let app = stateApp("full", route: route, language: route == "organization" ? "de":"uk")
            let screenID = route == "organization" ? "screen.ownerAnalytics.organizationDetail":"screen.ownerAnalytics.contentDetail"
            XCTAssertTrue(app.descendants(matching: .any)[screenID].firstMatch.waitForExistence(timeout: 10))
            capture(app, "A15-" + route + "-top")
            for page in 0..<5 { app.swipeUp(); capture(app, "A15-" + route + "-page-\(page)") }
            app.terminate()
        }
        for state in ["empty", "error"] {
            let app = stateApp(state, route: "event")
            let text = state == "empty" ? "Детальної аналітики ще немає":"Не вдалося завантажити аналітику"
            reveal(app.staticTexts[text].firstMatch, app)
            capture(app, "A15-event-" + state)
            app.terminate()
        }
    }
    func testNonOwnerProfileRolesHideGlobalAnalyticsWithUsableProfile() {
        for role in ["admin", "org-owner", "org-admin", "org-moderator", "member", "warned"] {
            let app = XCUIApplication(); app.launchArguments = ["-ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
            app.launchEnvironment = ["UITestProfileRole":role, "UITestResetUserSettings":"1", "UITestAppLanguage":"uk", "UITestResetAppLock":"1", "UITestFeedbackInbox":"1"]
            app.launch()
            let profile = app.tabBars.buttons.element(boundBy: 4)
            XCTAssertTrue(profile.waitForExistence(timeout: 15)); profile.tap()
            XCTAssertTrue(app.buttons["profile.edit.open"].waitForExistence(timeout: 10))
            for _ in 0..<8 {
                XCTAssertFalse(app.buttons["profile.owner.analytics"].exists, "Role \(role) must not see global analytics")
                app.swipeUp()
            }
            capture(app, "A15-profile-role-" + role)
            app.terminate()
        }
    }
}
