import XCTest

@MainActor
final class PublicOrganizationsAuditUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testAllPublicTabsPaginationAndContentDestinations() {
        let app = launch("member"); open("role-fixture", app)
        select("contacts", app)
        XCTAssertTrue(app.staticTexts["audit@example.org"].firstMatch.waitForExistence(timeout: 8))
        capture(app, "organization-contacts")
        select("news", app)
        let first = app.buttons["organization.activity.organization-news-audit-org-news-0"].firstMatch
        reveal(first, app); capture(app, "organization-news-first-page"); first.tap()
        XCTAssertTrue(app.buttons["news.like.audit-org-news-0"].firstMatch.waitForExistence(timeout: 8))
        capture(app, "organization-news-destination")
        app.buttons["navigation.back"].firstMatch.tap()
        let more = app.buttons["organization.activity.loadMore"].firstMatch
        reveal(more, app); more.tap(); reveal(more, app); more.tap()
        let last = app.buttons["organization.activity.organization-news-audit-org-news-25"].firstMatch
        reveal(last, app); capture(app, "organization-news-last-page")
        select("events", app)
        let ongoing = app.buttons["organization.activity.organization-event-audit-org-event-ongoing"].firstMatch
        reveal(ongoing, app); capture(app, "organization-ongoing-event"); ongoing.tap()
        XCTAssertTrue(app.buttons["event.register.audit-org-event-ongoing"].firstMatch.waitForExistence(timeout: 8))
        app.buttons["navigation.back"].firstMatch.tap()
        select("photos", app)
        let photo = app.buttons["Audit photo"].firstMatch
        reveal(photo, app); capture(app, "organization-public-gallery"); photo.tap()
        XCTAssertTrue(app.buttons["Готово"].waitForExistence(timeout: 8)); capture(app, "organization-photo-viewer")
        app.buttons["Готово"].tap()
        select("team", app); capture(app, "organization-public-team")
        select("about", app); capture(app, "organization-about-return")
    }
    func testActivityErrorIsVisibleAndRetryLoadsNews() {
        let app = launch("member", failure: "news"); open("role-fixture", app); select("news", app)
        let error = app.descendants(matching: .any).matching(identifier: "organization.activity.error").firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 12)); capture(app, "organization-news-network-error")
        let retry = app.buttons["Спробувати ще раз"].firstMatch
        if retry.exists { reveal(retry, app); retry.tap() }
        else { let fallback = app.buttons["Повторити"].firstMatch; reveal(fallback, app); fallback.tap() }
        let first = app.buttons["organization.activity.organization-news-audit-org-news-0"].firstMatch
        reveal(first, app); capture(app, "organization-news-retry-success")
    }
    func testOwnAndForeignOrganizationMenusRespectAllRoles() {
        for role in ["owner", "admin", "org-owner", "org-admin", "org-moderator", "mixed", "member", "warned"] {
            for id in ["role-fixture", "audit-foreign-org"] {
                let app = launch(role); open(id, app)
                app.buttons["detail.header.more-actions"].firstMatch.tap()
                let canEdit = role == "owner" || (id == "role-fixture" && ["org-owner", "org-admin", "mixed"].contains(role))
                if canEdit { XCTAssertTrue(app.buttons["Редагувати"].waitForExistence(timeout: 5)) }
                XCTAssertEqual(app.buttons["Редагувати"].exists, canEdit, "\(role), \(id)")
                XCTAssertEqual(app.buttons["Видалити"].exists, role == "owner", "\(role), \(id)")
                capture(app, "organization-menu-\(role)-\(id)"); app.terminate()
            }
        }
    }
    func testBookmarkAndSubscriptionSurviveReturning() {
        let app = launch("member"); open("role-fixture", app)
        let save = app.buttons["detail.header.action.bookmark"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 8)); save.tap()
        let subscribe = app.buttons["organization.subscribe.role-fixture"].firstMatch
        reveal(subscribe, app); subscribe.tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "Відписатися"), evaluatedWith: subscribe)
        waitForExpectations(timeout: 8)
        capture(app, "organization-subscribed")
        app.buttons["navigation.back"].firstMatch.tap(); open("role-fixture", app)
        XCTAssertTrue(app.buttons["detail.header.action.bookmark.fill"].waitForExistence(timeout: 8))
        reveal(subscribe, app); XCTAssertTrue(subscribe.label.contains("Відписатися")); subscribe.tap()
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5)); capture(app, "organization-unsubscribe-confirm")
    }
    func testGuestAndBlockedAccountInteractions() {
        let app = launch("guest"); open("role-fixture", app)
        app.buttons["detail.header.action.bookmark"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5)); capture(app, "organization-guest-save")
        app.terminate()
        let blocked = launch("blocked"); open("role-fixture", blocked)
        XCTAssertFalse(blocked.buttons["detail.header.action.bookmark"].isEnabled)
        let subscribe = blocked.buttons["organization.subscribe.role-fixture"].firstMatch
        reveal(subscribe, blocked); XCTAssertFalse(subscribe.isEnabled)
        capture(blocked, "organization-blocked-actions")
    }
    func testGermanDarkLargeTextAcrossPublicTabs() {
        let app = launch("member", germanDark: true); open("role-fixture", app)
        for section in ["about", "contacts", "news", "events", "team", "photos"] {
            select(section, app); capture(app, "organization-de-dark-AX-\(section)")
            app.swipeUp(); capture(app, "organization-de-dark-AX-\(section)-body")
        }
    }
    func testAlternateLanguageAppearanceCombinations() {
        for (language, appearance) in [("de", "light"), ("uk", "dark")] {
            let app = launch("member", language: language, appearance: appearance)
            open("role-fixture", app)
            for section in ["about", "contacts", "news", "events", "team", "photos"] {
                select(section, app)
                capture(app, "organization-\(language)-\(appearance)-\(section)")
            }
            app.terminate()
        }
    }
    private func launch(_ role: String, germanDark: Bool = false, failure: String? = nil, language: String? = nil, appearance: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        let appLanguage = language ?? (germanDark ? "de" : "uk")
        let appAppearance = appearance ?? (germanDark ? "dark" : "light")
        app.launchArguments = ["-ui-testing", "-UIPreferredContentSizeCategoryName", germanDark ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launchEnvironment = ["UITestResetUserSettings":"1", "UITestResetAppLock":"1", "UITestResetContentDrafts":"1",
            "UITestAppLanguage":appLanguage, "UITestAppAppearance":appAppearance,
            "UITestPublicOrganizationsAudit":"1", "UITestGallery":"1"]
        if let failure { app.launchEnvironment["UITestOrganizationActivityFailure"] = failure }
        if role == "owner" { app.launchEnvironment["UITestForceOwnerSession"] = "1" }
        else if role == "guest" { app.launchEnvironment["UITestForceGuestSession"] = "1" }
        else { app.launchEnvironment["UITestProfileRole"] = role }
        app.launch()
        let tab = app.tabBars.buttons[appLanguage == "de" ? "Organisation":"Організації"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap(); return app
    }
    private func open(_ id: String, _ app: XCUIApplication) {
        let card = app.descendants(matching: .any).matching(identifier: "organization.card." + id).firstMatch
        reveal(card, app); card.tap()
        XCTAssertTrue(app.buttons["navigation.back"].waitForExistence(timeout: 8))
    }
    private func select(_ section: String, _ app: XCUIApplication) {
        let chip = app.buttons["organization.section." + section].firstMatch
        let row = app.descendants(matching: .any).matching(identifier: "organization.sections").firstMatch
        _ = row.waitForExistence(timeout: 8)
        for _ in 0..<24 {
            if row.exists && row.frame.midY > 140 && row.frame.midY < app.frame.height - 160 { break }
            let down = row.exists && row.frame.midY < 140
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.35 : 0.70)).press(forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.55 : 0.50)))
        }
        for _ in 0..<8 {
            if chip.exists && chip.frame.midX > 20 && chip.frame.midX < app.frame.width - 20 && chip.isHittable {
                chip.tap()
                let content = app.descendants(matching: .any).matching(identifier: "organization.content." + section).firstMatch
                XCTAssertTrue(content.waitForExistence(timeout: 8))
                return
            }
            let y = max(0.15, min(0.8, row.frame.midY / app.frame.height))
            let goRight = chip.exists && chip.frame.midX < app.frame.width / 2
            app.coordinate(withNormalizedOffset: CGVector(dx: goRight ? 0.15 : 0.85, dy: y)).press(forDuration: 0.1,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: goRight ? 0.85 : 0.15, dy: y)))
        }
        XCTAssertTrue(chip.isHittable); chip.tap()
    }
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        _ = element.waitForExistence(timeout: 8)
        for _ in 0..<20 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
