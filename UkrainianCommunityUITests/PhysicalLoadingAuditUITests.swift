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
            let back = app.buttons["navigation.back"].firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 5)); back.tap()
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
        let report = XCTAttachment(string: "Directory recent visible data: \(elapsed) seconds")
        report.name = "Loading-times-directory"; report.lifetime = .keepAlways; add(report)
    }
}
