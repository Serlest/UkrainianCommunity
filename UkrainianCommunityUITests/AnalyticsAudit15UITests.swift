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
    func testChartMetricMenuAndDaySelection() {
        let app = stateApp("full", language: "de")
        app.buttons["7 Tage"].firstMatch.tap()
        let picker = app.descendants(matching: .any)["ownerAnalytics.trendMetricPicker"].firstMatch
        reveal(picker, app)
        picker.tap()
        let news = app.buttons["Nachrichtenaufrufe"].firstMatch
        XCTAssertTrue(news.waitForExistence(timeout: 5)); news.tap()
        let chart = app.descendants(matching: .any)["ownerAnalytics.trendChart"].firstMatch
        reveal(chart, app)
        XCTAssertTrue((chart.value as? String ?? "").contains("Nachrichtenaufrufe"))
        // A chart must fit below the real header, not merely be hittable.
        let headerBottom = app.staticTexts["Analytik"].firstMatch.frame.maxY + 50
        for _ in 0..<8 {
            let frame = chart.frame
            if frame.minY > headerBottom && frame.maxY < app.frame.maxY - 40 { break }
            let delta = max(-160.0, min(160.0, (headerBottom + app.frame.maxY - 40) / 2 - frame.midY))
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let from = origin.withOffset(CGVector(dx: app.frame.midX, dy: app.frame.height * 0.6))
            let to = origin.withOffset(CGVector(dx: app.frame.midX, dy: app.frame.height * 0.6 + delta))
            from.press(forDuration: 0.01, thenDragTo: to)
        }
        XCTAssertGreaterThan(chart.frame.minY, headerBottom)
        XCTAssertLessThan(chart.frame.maxY, app.frame.maxY - 40)
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)).tap()
        let selected = app.descendants(matching: .any)["ownerAnalytics.trendSelection"].firstMatch
        XCTAssertTrue(selected.waitForExistence(timeout: 5))
        capture(app, "A15-chart-news-and-selected-day")
        app.terminate()
    }
    func testRetryRecoveryAndRefreshFailureKeepsGoodData() {
        let retryApp = stateApp("retry")
        let retry = retryApp.buttons["Спробувати ще раз"].firstMatch
        reveal(retry, retryApp); retry.tap()
        let overview = retryApp.staticTexts["Огляд"].firstMatch
        XCTAssertTrue(overview.waitForExistence(timeout: 8))
        capture(retryApp, "A15-retry-recovers-real-button")
        retryApp.terminate()

        let app = stateApp("stale")
        XCTAssertTrue(app.staticTexts["Огляд"].firstMatch.waitForExistence(timeout: 8))
        let scroll = app.scrollViews.firstMatch
        let pullStart = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.3))
        let pullEnd = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.9))
        pullStart.press(forDuration: 0.05, thenDragTo: pullEnd)
        let stale = app.descendants(matching: .any)["ownerAnalytics.staleData"].firstMatch
        let didShowStale = stale.waitForExistence(timeout: 8)
        XCTAssertTrue(didShowStale)
        capture(app, "A15-after-native-pull")
        guard didShowStale else { app.terminate(); return }
        XCTAssertTrue(app.staticTexts["Огляд"].firstMatch.exists)
        capture(app, "A15-refresh-failure-preserves-report")
        let staleRetry = app.buttons["Спробувати ще раз"].firstMatch
        reveal(staleRetry, app); staleRetry.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: stale)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 8), .completed)
        capture(app, "A15-stale-retry-recovers")
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
    func testOrganizationChildrenPreservePeriodAndReturn() {
        for (type, id) in [("news", "news-language-courses-update"), ("event", "event-vienna-language-night")] {
            let app = stateApp("full", route: "organization", language: "de")
            let thirty = app.buttons["30 Tage"].firstMatch
            XCTAssertTrue(thirty.waitForExistence(timeout: 8)); thirty.tap()
            let child = app.descendants(matching: .any)["ownerAnalytics.detail.content.\(type).\(id)"].firstMatch
            reveal(child, app); child.tap()
            XCTAssertTrue(app.descendants(matching: .any)["screen.ownerAnalytics.contentDetail"].firstMatch.waitForExistence(timeout: 8))
            XCTAssertTrue(app.buttons["30 Tage"].firstMatch.isSelected)
            if type == "news" {
                XCTAssertTrue(app.descendants(matching: .any)["ownerAnalytics.metric.eye"].firstMatch.waitForExistence(timeout: 8))
            }
            capture(app, "A15-organization-child-" + type)
            app.buttons["Zurück"].firstMatch.tap()
            XCTAssertTrue(app.descendants(matching: .any)["screen.ownerAnalytics.organizationDetail"].firstMatch.waitForExistence(timeout: 8))
            XCTAssertTrue(app.buttons["30 Tage"].firstMatch.isSelected)
            capture(app, "A15-organization-return-" + type)
            app.terminate()
        }
    }
    func testUserRegionExpansionAndBannerDailyDisclosure() {
        let app = stateApp("full")
        let hiddenActivity = app.descendants(matching: .any)["ownerAnalytics.region.federalState:burgenland"].firstMatch
        XCTAssertFalse(hiddenActivity.exists)
        let activityMore = app.buttons["Показати більше"].firstMatch
        reveal(activityMore, app); activityMore.tap()
        XCTAssertTrue(hiddenActivity.waitForExistence(timeout: 5))
        capture(app, "A15-content-regions-expanded")
        let activityLess = app.buttons["Показати менше"].firstMatch
        reveal(activityLess, app); activityLess.tap()
        XCTAssertFalse(hiddenActivity.exists)

        let hiddenRegion = app.descendants(matching: .any)["ownerAnalytics.userRegion.steiermark"].firstMatch
        XCTAssertFalse(hiddenRegion.exists)
        let more = app.buttons.matching(NSPredicate(format: "label == %@", "Показати більше")).allElementsBoundByIndex.last!
        reveal(more, app); more.tap()
        XCTAssertTrue(hiddenRegion.waitForExistence(timeout: 5))
        capture(app, "A15-user-regions-expanded")
        let less = app.buttons["Показати менше"].firstMatch
        reveal(less, app); less.tap()
        XCTAssertFalse(hiddenRegion.exists)
        let disclosure = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Деталі за днями · UTC")).firstMatch
        let utcDay = String(ISO8601DateFormatter().string(from: Date()).prefix(10))
        let dayRow = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", utcDay, "показів")).firstMatch
        reveal(disclosure, app)
        XCTAssertFalse(dayRow.exists)
        disclosure.tap()
        XCTAssertTrue(dayRow.waitForExistence(timeout: 5))
        capture(app, "A15-banner-days-expanded")
        disclosure.tap()
        XCTAssertFalse(dayRow.exists)
        capture(app, "A15-banner-days-collapsed")
        app.terminate()
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
