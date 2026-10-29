import XCTest

/// Real signed-in production reads only. No decisions, messages, edits or account switches.
@MainActor final class PhysicalLoadingAuditUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
#if targetEnvironment(simulator)
        throw XCTSkip("Physical device required")
#else
        guard ProcessInfo.processInfo.environment["UACPhysicalLoadingAudit"] == "1" else {
            throw XCTSkip("Explicit read-only loading audit required")
        }
#endif
    }
    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.terminate(); app.launchArguments = []; app.launch()
        super.tearDown()
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<18 {
            if element.exists && element.isHittable && element.frame.midY > 105 && element.frame.midY < app.frame.height - 110 { return }
            if element.exists && element.frame.midY < 105 { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(element.exists && element.isHittable, "Could not reveal \(element.identifier)")
    }
    private func auditProfile(_ route: String, ready: [String], prefix: String) {
        let app = XCUIApplication(); app.launchArguments = []; app.launch()
        let profile = app.tabBars.buttons.matching(NSPredicate(format: "identifier == %@ OR label IN %@", "tab.profile", ["Профіль", "Profil", "Profile"])).firstMatch
        XCTAssertTrue(profile.waitForExistence(timeout: 20)); profile.tap()
        var timings: [Double] = []
        for visit in 1...2 {
            let entry = app.buttons[route].firstMatch; reveal(entry, in: app)
            let start = ProcessInfo.processInfo.systemUptime; entry.tap()
            let settled = NSPredicate { _, _ in
                ready.contains { app.descendants(matching: .any)[$0].firstMatch.exists } ||
                app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch.exists
            }
            let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: settled, object: nil)], timeout: 25)
            timings.append(ProcessInfo.processInfo.systemUptime - start)
            capture(app, "Loading-\(route)-visit-\(visit)")
            XCTAssertEqual(result, .completed, "Data/confirmed empty state did not arrive: \(app.debugDescription)")
            let customBack = app.buttons["navigation.back"].firstMatch
            if customBack.exists && customBack.isHittable { customBack.tap() }
            else {
                let back = app.buttons.matching(NSPredicate(format: "label IN %@", ["Назад", "Zurück", "Back"])).allElementsBoundByIndex.first {
                    $0.isHittable && $0.frame.minY < 200 && $0.frame.minX < 100
                }
                XCTAssertNotNil(back, "Expected the destination's visible back action"); back?.tap()
            }
        }
        let report = XCTAttachment(string: "\(route): visible result after first/repeated entry (seconds): \(timings)")
        report.name = "Loading-times-\(route)"; report.lifetime = .keepAlways; add(report)
    }
    func testOrganizationRequests() {
        auditProfile("profile.organizationRequests", ready: ["organization.requests.empty"], prefix: "organization.requests.open.")
    }
    func testFeedbackInbox() {
        auditProfile("profile.feedbackInbox", ready: ["feedbackInbox.empty"], prefix: "feedbackInbox.open.")
    }
    func testModeration() {
        auditProfile("profile.moderation", ready: ["content.moderation.empty"], prefix: "content.moderation.open.")
    }
    func testOrganizationManagement() {
        auditProfile("profile.organizationManagement", ready: ["organization.management.empty"], prefix: "organization.management.card.")
    }
    func testUserManagement() {
        auditProfile("profile.userManagement", ready: [], prefix: "userManagement.user.")
    }
    func testRegistrations() {
        auditProfile("profile.registrations", ready: ["registrations.empty"], prefix: "registrations.open.")
    }
    func testSavedContent() {
        auditProfile("profile.savedContent", ready: ["saved.empty"], prefix: "saved.open.")
    }
    func testSubscriptions() {
        auditProfile("profile.followedOrganizations", ready: ["subscriptions.empty"], prefix: "subscriptions.open.")
    }
    func testRecentlyViewed() {
        auditProfile("profile.recentViews", ready: ["recentViews.empty"], prefix: "recentViews.open.")
    }
    func testActivityHistory() {
        auditProfile("profile.activityHistory", ready: ["activityHistory.empty"], prefix: "activityHistory.open.")
    }
    func testDirectoryEditorAccess() {
        auditProfile("profile.directoryEditors", ready: ["directoryAccess.empty"], prefix: "directoryAccess.revoke.")
    }
    func testAnnouncementManagement() {
        auditProfile("profile.announcements", ready: ["announcements.empty"], prefix: "announcements.item.")
    }
    func testSystemJournalCurrentEmptyOrRecords() {
        auditProfile("profile.owner.systemLogs", ready: ["systemLogs.empty"], prefix: "systemLogs.log.")
    }
    func testBannerListAndReport() {
        let app = XCUIApplication(); app.launchArguments = []; app.launch()
        let profile = app.tabBars.buttons.matching(NSPredicate(format: "identifier == %@ OR label IN %@", "tab.profile", ["Профіль", "Profil", "Profile"])).firstMatch
        XCTAssertTrue(profile.waitForExistence(timeout: 20)); profile.tap()
        let entry = app.buttons["profile.featuredBanners"]; reveal(entry, in: app); entry.tap()
        let statistics = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "bannerManagement.statistics.")).firstMatch
        XCTAssertTrue(statistics.waitForExistence(timeout: 25)); reveal(statistics, in: app)
        capture(app, "Loading-banners-confirmed-list"); statistics.tap()
        XCTAssertTrue(app.descendants(matching: .any)["bannerReport.loaded"].firstMatch.waitForExistence(timeout: 25))
        let metric = app.descendants(matching: .any)["ownerAnalytics.metric.eye"].firstMatch
        reveal(metric, in: app)
        let ready = NSPredicate { _, _ in metric.exists && metric.value as? String != nil && metric.value as? String != "—" }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 25), .completed)
        capture(app, "Loading-banners-confirmed-report")
    }
    func testPublicFeedsAndDetails() {
        let app = XCUIApplication(); app.launchArguments = []; app.launch()
        let cases: [(String, [String], String, [String], String)] = [
            ("tab.home", ["Новини", "Nachrichten"], "home.card.news-", ["home.news.empty"], "news.like."),
            ("tab.events", ["Події", "Veranstaltungen"], "event.card.", ["events.feed.empty", "events.feed.filteredEmpty"], "event.detail.loaded."),
            ("tab.organizations", ["Організації", "Organisationen"], "organization.card.", ["organizations.feed.empty", "organizations.feed.filteredEmpty"], "organization.content.")
        ]
        for (tabID, labels, prefix, emptyIDs, detailPrefix) in cases {
            let tab = app.tabBars.buttons.matching(NSPredicate(format: "identifier == %@ OR label IN %@", tabID, labels)).firstMatch
            XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap(); app.swipeUp()
            let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
            let ready = NSPredicate { _, _ in rows.firstMatch.exists || emptyIDs.contains { app.descendants(matching: .any)[$0].firstMatch.exists } }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 25), .completed)
            capture(app, "Loading-public-" + tabID)
            guard rows.firstMatch.exists else { continue }
            reveal(rows.firstMatch, in: app); rows.firstMatch.tap()
            let detail = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", detailPrefix)).firstMatch
            XCTAssertTrue(detail.waitForExistence(timeout: 25)); capture(app, "Loading-public-detail-" + tabID)
            let back = app.buttons["navigation.back"].firstMatch
            if back.exists && back.isHittable { back.tap() }
            else {
                let fallback = app.buttons.matching(NSPredicate(format: "label IN %@", ["Назад", "Zurück", "Back"])).allElementsBoundByIndex.first { $0.isHittable && $0.frame.minY < 200 && $0.frame.minX < 100 }
                XCTAssertNotNil(fallback); fallback?.tap()
            }
            XCTAssertTrue(tab.waitForExistence(timeout: 10))
        }
    }
    func testDirectoryRecentAdditions() {
        let app = XCUIApplication(); app.launchArguments = []; app.launch()
        let directory = app.tabBars.buttons.matching(NSPredicate(format: "identifier == %@ OR label IN %@", "tab.directory", ["Довідник", "Ratgeber"])).firstMatch
        XCTAssertTrue(directory.waitForExistence(timeout: 20))
        let start = ProcessInfo.processInfo.systemUptime; directory.tap()
        let settled = NSPredicate { _, _ in
            app.staticTexts["directory.recent.empty"].exists ||
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier != %@ AND identifier != %@ AND identifier != %@", "directory.recent.", "directory.recent.retry", "directory.recent.showAll", "directory.recent.more")).firstMatch.exists
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: settled, object: nil)], timeout: 25), .completed)
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier != %@ AND identifier != %@ AND identifier != %@", "directory.recent.", "directory.recent.retry", "directory.recent.showAll", "directory.recent.more"))
        if rows.firstMatch.exists { reveal(rows.firstMatch, in: app) }
        capture(app, "Loading-directory-recent-confirmed")
        XCTAssertFalse(app.buttons["directory.recent.retry"].exists)
        let profile = app.tabBars.buttons.matching(NSPredicate(format: "identifier == %@ OR label IN %@", "tab.profile", ["Профіль", "Profil", "Profile"])).firstMatch
        profile.tap(); directory.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: settled, object: nil)], timeout: 10), .completed)
        XCTAssertFalse(app.descendants(matching: .any)["directory.recent.loading"].exists)
        capture(app, "Loading-directory-recent-return")
        let report = XCTAttachment(string: "Directory recent visible data: \(elapsed) seconds")
        report.name = "Loading-times-directory"; report.lifetime = .keepAlways; add(report)
    }
}
