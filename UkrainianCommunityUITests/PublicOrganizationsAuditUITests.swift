import XCTest

@MainActor
final class PublicOrganizationsAuditUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testEmptyPublicSectionsInBothThemesAndLanguages() {
        for large in [false, true] {
            let app = launch("member", germanDark: large, sectionState: "empty")
            open("role-fixture", app)
            for section in ["news", "events", "team", "photos"] {
                select(section, app)
                let id = section == "team" ? "organization.community.empty" : section == "photos" ? "organization.gallery.empty" : "organization.content." + section
                let state = ["team", "photos"].contains(section) ? app.staticTexts[id].firstMatch : app.descendants(matching: .any)[id].firstMatch
                reveal(state, app); XCTAssertTrue(state.exists)
                alignTop(state, app)
                capture(app, "organization-empty-" + section + (large ? "-de-dark-AX" : "-uk-light"))
                if large { app.swipeUp(); capture(app, "organization-empty-continuation-" + section + "-de-dark-AX") }
            }
            app.terminate()
        }
    }

    func testPublicCommunityAndGalleryMetadataErrorsRecover() {
        let app = launch("member", sectionState: "error"); open("role-fixture", app)
        for (section, id) in [("team", "organization.community.retry"), ("photos", "organization.gallery.retry")] {
            select(section, app)
            let loadingID = section == "team" ? "organization.community.loading" : "organization.gallery.loading"
            let loading = app.descendants(matching: .any)[loadingID].firstMatch
            if loading.exists { capture(app, "organization-metadata-loading-" + section) }
            let retry = app.buttons[id].firstMatch
            reveal(retry, app); XCTAssertTrue(retry.isEnabled); capture(app, "organization-metadata-error-" + section)
            retry.tap(); XCTAssertTrue(retry.waitForNonExistence(timeout: 10))
            capture(app, "organization-metadata-recovered-" + section)
        }
        app.terminate()
    }

    func testGalleryDownloadFailureOffersRetryAndKeepsViewer() async throws {
        guard ProcessInfo.processInfo.environment["UACGalleryHTTPFixture"] == "1" else { throw XCTSkip("Start isolated scripts/serve-audit-photo-fixture.py") }
        _ = try await galleryFixture("reset", method: "POST")
        let app = launch("member", galleryFailure: true); open("role-fixture", app); select("photos", app)
        let photo = app.buttons["organization.photo.open.photo-fixture"].firstMatch
        reveal(photo, app); photo.tap()
        let retry = app.buttons["remoteImage.retry"].firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout: 15)); capture(app, "organization-gallery-download-failure")
        _ = try await galleryFixture("enable", method: "POST")
        retry.tap()
        XCTAssertTrue(app.descendants(matching: .any)["organization.photo.image.loaded.photo-fixture"].firstMatch.waitForExistence(timeout: 15))
        let status = try await galleryFixture("status", method: "GET")
        XCTAssertGreaterThanOrEqual(status["failed"] as? Int ?? 0, 1)
        XCTAssertGreaterThanOrEqual(status["succeeded"] as? Int ?? 0, 1)
        XCTAssertTrue(app.buttons["Готово"].exists); capture(app, "organization-gallery-retry-recovered")
        app.buttons["Готово"].tap(); XCTAssertTrue(photo.waitForExistence(timeout: 8))
    }

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
    private func alignTop(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<24 {
            let bottom = app.tabBars.firstMatch.frame.minY - 12
            // A tall accessibility state can span several viewports. Keep its
            // top readable and capture the continuation separately.
            if element.frame.minY >= 90 && element.frame.minY < bottom - 44 { return }
            let towardTop = element.frame.minY < 90
            app.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: towardTop ? 0.4 : 0.55))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: towardTop ? 0.55 : 0.4)))
        }
        XCTFail("Cannot align empty-state content")
    }

    private func galleryFixture(_ path: String, method: String) async throws -> [String: Any] {
        guard ["reset", "enable", "status"].contains(path) else { throw NSError(domain: "AuditFixture", code: 1) }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:29555/" + path)!)
        request.httpMethod = method
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func launch(_ role: String, germanDark: Bool = false, failure: String? = nil, language: String? = nil, appearance: String? = nil, galleryFailure: Bool = false, sectionState: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        let appLanguage = language ?? (germanDark ? "de" : "uk")
        let appAppearance = appearance ?? (germanDark ? "dark" : "light")
        app.launchArguments = ["-ui-testing", "-UIPreferredContentSizeCategoryName", germanDark ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launchEnvironment = ["UITestResetUserSettings":"1", "UITestResetAppLock":"1", "UITestResetContentDrafts":"1",
            "UITestAppLanguage":appLanguage, "UITestAppAppearance":appAppearance,
            "UITestPublicOrganizationsAudit":"1", "UITestGallery":"1"]
        if galleryFailure { app.launchEnvironment["UITestGalleryDeterministicFailure"] = "1" }
        if let sectionState {
            app.launchEnvironment["UITestGalleryState"] = sectionState
            if sectionState == "empty" { app.launchEnvironment["UITestPublicOrganizationEmptySections"] = "1" }
            if sectionState == "error" { app.launchEnvironment["UITestOrganizationTeamFailure"] = "1" }
        }
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
        let selector = app.buttons["organization.sections"].firstMatch
        if selector.exists {
            selector.tap()
            XCTAssertTrue(chip.waitForExistence(timeout: 5)); chip.tap()
            XCTAssertTrue(app.descendants(matching: .any)["organization.content." + section].firstMatch.waitForExistence(timeout: 8))
            return
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
