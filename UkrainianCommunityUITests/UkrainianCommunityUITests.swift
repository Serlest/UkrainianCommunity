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

    private func launchApp(appLockScenario: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launchEnvironment["UITestResetUserSettings"] = "1"
        app.launchEnvironment["UITestAppLanguage"] = "de"
        app.launchEnvironment["UITestForceGuestSession"] = "1"
        app.launchEnvironment["UITestAppLockScenario"] = appLockScenario
        app.launch()
        return app
    }

    private func launchGuestApp(language: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launchEnvironment["UITestResetUserSettings"] = "1"
        app.launchEnvironment["UITestAppLanguage"] = language
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

    private func launchNotificationDetailsApp(largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launchEnvironment["UITestResetUserSettings"] = "1"
        app.launchEnvironment["UITestAppLanguage"] = largeText ? "uk" : "de"
        app.launchEnvironment["UITestForceAuthenticatedSession"] = "1"
        app.launchEnvironment["UITestNotificationDetails"] = "1"
        if largeText {
            app.launchEnvironment["UITestAppAppearance"] = "dark"
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        return app
    }

    @MainActor
    func testQuickCreationUsesExistingEditorsAndBellIsSharedAcrossTabs() throws {
        let app = launchOwnerApp()
        for (index, kind) in [(0, "news"), (1, "event")] {
            tapRootTab(rootTabs[index], in: app, timeout: 20)
            let create = app.buttons["quickCreate.\(kind)"]
            XCTAssertTrue(create.waitForExistence(timeout: 20))
            XCTAssertTrue(create.isHittable)
            attachScreenshot(named: "quick-create-\(kind)", from: app)
            create.tap()
            let editor = element("editor.\(kind)", in: app)
            XCTAssertTrue(editor.waitForExistence(timeout: 15))
            // The draft-preservation scenario deliberately leaves a local draft.
            // Handle the real recovery prompt before testing the editor close path.
            let newDraft = app.buttons["Neu erstellen"]
            if newDraft.waitForExistence(timeout: 2) { newDraft.tap() }
            attachScreenshot(named: "existing-editor-\(kind)", from: app)
            app.buttons["Abbrechen"].firstMatch.tap()
            let discardDraft = app.buttons["Verwerfen"].firstMatch
            if discardDraft.waitForExistence(timeout: 2) { discardDraft.tap() }
            XCTAssertTrue(editor.waitForNonExistence(timeout: 10))
            XCTAssertTrue(app.buttons["quickCreate.\(kind)"].waitForExistence(timeout: 10))
        }
        for tab in rootTabs {
            tapRootTab(tab, in: app, timeout: 20)
            let bell = app.buttons["notificationInbox.bell"].firstMatch
            XCTAssertTrue(bell.waitForExistence(timeout: 10))
            XCTAssertTrue(bell.isHittable)
            attachScreenshot(named: "shared-bell-\(tab.tabIdentifier)", from: app)
            bell.tap()
            let back = app.buttons["navigation.back"].firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 10))
            back.tap()
            XCTAssertTrue(element(tab.screenIdentifier, in: app).waitForExistence(timeout: 10))
        }
        app.terminate()
        let guest = launchApp()
        XCTAssertTrue(guest.tabBars.firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(guest.buttons["quickCreate.news"].exists)
        XCTAssertFalse(guest.buttons["notificationInbox.bell"].exists)
        tapRootTab(rootTabs[1], in: guest, timeout: 10)
        XCTAssertFalse(guest.buttons["quickCreate.event"].exists)
    }

    @MainActor
    func testContentEditorV2ReachesRealNewsPreview() throws {
        let app = launchOwnerApp(language: "uk", resetContentDrafts: true)

        tapRootTab(rootTabs[0], in: app, timeout: 20)
        app.buttons["quickCreate.news"].tap()
        let newNewsDraft = app.buttons["Створити нову"]
        if newNewsDraft.waitForExistence(timeout: 2) { newNewsDraft.tap() }
        let organizer = element("editor.news.organizer", in: app)
        XCTAssertTrue(organizer.waitForExistence(timeout: 10))
        organizer.tap()
        let organizationOption = element("editor.news.organizer.org-1", in: app)
        XCTAssertTrue(organizationOption.waitForExistence(timeout: 10))
        organizationOption.tap()

        let newsTitle = element("editor.news.title", in: app)
        newsTitle.tap()
        newsTitle.typeText("Тестова новина")
        let newsSummary = element("editor.news.summary", in: app)
        newsSummary.tap()
        newsSummary.typeText("Короткий опис для перевірки картки")
        let newsNext = element("editor.news.next", in: app)
        scrollToElement(newsNext, in: app, maxSwipes: 10)
        newsNext.tap()

        let newsBody = element("editor.news.body", in: app)
        scrollToElement(newsBody, in: app, maxSwipes: 12)
        newsBody.tap()
        newsBody.typeText("Повний текст тестової новини для попереднього перегляду.")
        scrollToElement(newsNext, in: app, maxSwipes: 12)
        newsNext.tap()
        XCTAssertTrue(app.staticTexts["Як виглядатиме новина"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Тестова новина"].waitForExistence(timeout: 10))
        let closeButton = app.buttons["Скасувати"].firstMatch
        XCTAssertTrue(closeButton.isHittable)
        XCTAssertGreaterThanOrEqual(closeButton.frame.minX, app.frame.minX + 8)
        XCTAssertLessThanOrEqual(closeButton.frame.maxX, app.frame.maxX - 8)
        attachScreenshot(named: "content-v2-news-real-preview", from: app)
    }

    @MainActor
    func testContentEditorV2ReachesRealEventPreview() throws {
        let app = launchOwnerApp(language: "uk", resetContentDrafts: true)

        tapRootTab(rootTabs[1], in: app, timeout: 20)
        app.buttons["quickCreate.event"].tap()
        let newEventDraft = app.buttons["Створити нову"]
        if newEventDraft.waitForExistence(timeout: 2) { newEventDraft.tap() }
        let eventOrganizerPicker = element("editor.event.organizerPicker", in: app)
        if !eventOrganizerPicker.waitForExistence(timeout: 5) {
            let eventOrganizer = element("editor.event.organizer", in: app)
            XCTAssertTrue(eventOrganizer.waitForExistence(timeout: 10))
            eventOrganizer.tap()
        }
        XCTAssertTrue(eventOrganizerPicker.waitForExistence(timeout: 10))
        let eventOrganizationOption = element("editor.event.organizer.org-1", in: app)
        if eventOrganizationOption.waitForExistence(timeout: 3) {
            eventOrganizationOption.tap()
        } else {
            let organizationNames = app.staticTexts.matching(
                NSPredicate(format: "label == %@", "Ukrainian Community")
            )
            let organizationName = organizationNames.element(boundBy: max(0, organizationNames.count - 1))
            XCTAssertTrue(organizationName.waitForExistence(timeout: 10))
            organizationName.tap()
        }
        let eventTitle = app.textFields["editor.event.title"].firstMatch
        XCTAssertTrue(eventTitle.waitForExistence(timeout: 10))
        eventTitle.tap()
        eventTitle.typeText("Тестова подія")
        XCTAssertEqual(eventTitle.value as? String, "Тестова подія")
        let eventSummary = app.textViews["editor.event.summary"].firstMatch
        eventSummary.tap()
        eventSummary.typeText("Короткий опис події")
        XCTAssertEqual(eventSummary.value as? String, "Короткий опис події")
        let eventDetails = app.textViews["editor.event.details"].firstMatch
        eventDetails.tap()
        eventDetails.typeText("Повний опис події для попереднього перегляду.")
        XCTAssertEqual(eventDetails.value as? String, "Повний опис події для попереднього перегляду.")
        XCTAssertEqual(eventTitle.value as? String, "Тестова подія")
        let eventNext = element("editor.event.next", in: app)
        scrollToElement(eventNext, in: app, maxSwipes: 12)
        XCTAssertTrue(eventNext.isEnabled)
        eventNext.tap()

        let eventAddress = element("editor.event.address", in: app)
        scrollToElement(eventAddress, in: app, maxSwipes: 12)
        eventAddress.tap()
        eventAddress.typeText("Museumstrasse 1")
        let eventCity = element("editor.event.city", in: app)
        eventCity.tap()
        eventCity.typeText("Innsbruck")
        scrollToElement(eventNext, in: app, maxSwipes: 12)
        eventNext.tap()
        scrollToElement(eventNext, in: app, maxSwipes: 12)
        eventNext.tap()
        XCTAssertTrue(app.staticTexts["Так виглядатиме подія"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Тестова подія"].waitForExistence(timeout: 10))
        attachScreenshot(named: "content-v2-event-real-preview", from: app)
    }

    @MainActor
    private func launchAppLockTestApp(scenario: String = "success", language: String = "de", largeText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launchEnvironment["UITestForceOwnerSession"] = "1"
        app.launchEnvironment["UITestResetUserSettings"] = "1"
        app.launchEnvironment["UITestAppLanguage"] = language
        app.launchEnvironment["UITestAppLockScenario"] = scenario
        app.launchEnvironment["UITestResetAppLock"] = "1"
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            app.launchEnvironment["UITestAppAppearance"] = "dark"
        }
        app.launch()
        return app
    }

    @MainActor
    private func enableAppLock(in app: XCUIApplication) {
        tapRootTab(rootTabs[3], in: app, timeout: 20)
        let settings = app.buttons["profile.settings.open"].firstMatch
        scrollToElement(settings, in: app, maxSwipes: 24)
        settings.tap()
        let toggle = app.switches["profile.settings.appLock"].firstMatch
        scrollToElement(toggle, in: app, maxSwipes: 10)
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.tap()
        let enabled = NSPredicate(format: "value == '1'")
        expectation(for: enabled, evaluatedWith: toggle)
        waitForExpectations(timeout: 8)
    }

    @MainActor
    func testAppLockCoversPresentedInboxAndRejectsFailedUnlock() throws {
        // Scripted LocalAuthentication verifies app behavior, not real Face ID hardware.
        let app = launchAppLockTestApp(scenario: "failureThenSuccess")
        enableAppLock(in: app)
        app.buttons["navigation.back"].firstMatch.tap()
        tapRootTab(rootTabs[0], in: app, timeout: 10)
        app.buttons["notificationInbox.bell"].firstMatch.tap()
        XCTAssertTrue(app.buttons["navigation.back"].firstMatch.waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        app.activate()
        let unlock = app.buttons["appLock.unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["navigation.back"].firstMatch.isHittable)
        attachScreenshot(named: "app-lock-covers-inbox", from: app)
        unlock.tap()
        XCTAssertTrue(app.staticTexts["Der Zugriff konnte nicht bestätigt werden. Versuchen Sie es erneut oder melden Sie sich mit Ihrem Passwort an."].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["navigation.back"].firstMatch.isHittable)
        unlock.tap()
        XCTAssertTrue(unlock.waitForNonExistence(timeout: 8))
        XCTAssertTrue(app.buttons["navigation.back"].firstMatch.isHittable)
        app.buttons["navigation.back"].firstMatch.tap()
        XCTAssertTrue(app.tabBars.firstMatch.isHittable)
    }

    @MainActor
    func testUkrainianLargeTextLockPreservesNewsEditorDraft() throws {
        let app = launchAppLockTestApp(language: "uk", largeText: true)
        enableAppLock(in: app)
        attachScreenshot(named: "app-lock-settings-uk-accessibility", from: app)
        app.buttons["navigation.back"].firstMatch.tap()
        tapRootTab(rootTabs[0], in: app, timeout: 10)
        let create = app.buttons["quickCreate.news"]
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        attachScreenshot(named: "quick-create-uk-accessibility", from: app)
        create.tap()
        let newDraft = app.buttons["Створити нову"]
        if newDraft.waitForExistence(timeout: 2) { newDraft.tap() }
        let title = app.textFields.firstMatch
        scrollToElement(title, in: app, maxSwipes: 12)
        XCTAssertTrue(title.isHittable)
        title.tap()
        title.typeText("Draft kept")
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        app.activate()
        let unlock = app.buttons["appLock.unlock"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 10))
        scrollToElement(unlock, in: app, maxSwipes: 12)
        attachScreenshot(named: "app-lock-uk-accessibility", from: app)
        unlock.tap()
        XCTAssertTrue(unlock.waitForNonExistence(timeout: 8))
        XCTAssertEqual(title.value as? String, "Draft kept")
    }

    @MainActor
    func testAppLockRestoresLockedAndOffersExistingPasswordLogin() throws {
        let app = launchAppLockTestApp()
        enableAppLock(in: app)
        app.terminate()
        app.launchEnvironment["UITestResetAppLock"] = nil
        app.launch()
        let password = app.buttons["appLock.passwordSignIn"]
        XCTAssertTrue(password.waitForExistence(timeout: 20))
        XCTAssertFalse(app.tabBars.firstMatch.isHittable)
        password.tap()
        XCTAssertTrue(app.buttons["auth.login.submit"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["appLock.unlock"].exists)
    }

    @MainActor
    func testNotificationDetailsReadCloseDeleteAndNavigate() throws {
        let app = launchNotificationDetailsApp()
        tapRootTab(rootTabs[3], in: app, timeout: 20)
        let bell = app.buttons["notificationInbox.bell"].firstMatch
        XCTAssertTrue(bell.waitForExistence(timeout: 20))
        bell.tap()
        let info = element("notificationInbox.open.detail-info", in: app)
        XCTAssertTrue(info.waitForExistence(timeout: 10))
        app.segmentedControls.buttons["Ungelesen"].tap()
        info.tap()
        let body = app.staticTexts["notificationDetail.body"]
        XCTAssertTrue(body.waitForExistence(timeout: 10))
        XCTAssertGreaterThan(body.label.count, 400)
        XCTAssertFalse(app.buttons["notificationDetail.openDestination"].exists)
        attachScreenshot(named: "notification-details-german-full-text", from: app)
        app.buttons["notificationDetail.close"].tap()
        XCTAssertTrue(body.waitForNonExistence(timeout: 5))
        XCTAssertFalse(info.exists, "Read notification must leave the unread filter")
        app.segmentedControls.buttons["Alle"].tap()
        XCTAssertTrue(info.waitForExistence(timeout: 5), "Closing must retain the notification")
        info.tap()
        let delete = app.buttons["notificationDetail.delete"]
        scrollToElement(delete, in: app, maxSwipes: 12)
        XCTAssertTrue(delete.isHittable)
        delete.tap()
        app.buttons["Abbrechen"].tap()
        XCTAssertTrue(body.exists)
        delete.tap()
        let confirmation = app.alerts.buttons["notificationDetail.confirmDelete"].firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        attachScreenshot(named: "notification-details-delete-confirmation", from: app)
        confirmation.tap()
        XCTAssertTrue(body.waitForNonExistence(timeout: 5))
        XCTAssertFalse(info.exists)
        let event = element("notificationInbox.open.detail-event", in: app)
        XCTAssertTrue(event.waitForExistence(timeout: 5))
        event.tap()
        let open = app.buttons["notificationDetail.openDestination"].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        attachScreenshot(named: "notification-details-event-action", from: app)
        open.tap()
        XCTAssertTrue(open.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label IN %@", ["Ukrainischer Gemeinschaftsabend", "Український вечір спільноти"])).firstMatch.waitForExistence(timeout: 10))
        attachScreenshot(named: "notification-details-event-destination", from: app)
    }

    @MainActor
    func testNotificationDetailsFromProfileSupportUkrainianDarkLargeText() throws {
        let app = launchNotificationDetailsApp(largeText: true)
        tapRootTab(rootTabs[3], in: app, timeout: 20)
        let bell = app.buttons["notificationInbox.bell"].firstMatch
        XCTAssertTrue(bell.waitForExistence(timeout: 10))
        bell.tap()
        let info = element("notificationInbox.open.detail-info", in: app)
        scrollToElement(info, in: app)
        XCTAssertTrue(info.waitForExistence(timeout: 10))
        info.tap()
        let close = app.buttons["notificationDetail.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10) && close.isHittable)
        XCTAssertEqual(close.label, "Закрити")
        attachScreenshot(named: "notification-details-ukrainian-dark-AX-top", from: app)
        let delete = app.buttons["notificationDetail.delete"]
        scrollToElement(delete, in: app, maxSwipes: 30)
        XCTAssertTrue(delete.isHittable)
        XCTAssertTrue(close.isHittable, "Close must remain accessible after scrolling")
        attachScreenshot(named: "notification-details-ukrainian-dark-AX-bottom", from: app)
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testUserDetailPullRefreshUpdatesPresenceAndKeepsNavigation() throws {
        let app = launchUserRefreshApp(failing: false)
        openRefreshTestUser(in: app)
        XCTAssertTrue(element("user.presence.online", in: app).waitForExistence(timeout: 8))
        pullToRefresh(in: app)
        XCTAssertTrue(element("user.presence.lastSeen", in: app).waitForExistence(timeout: 10))
        XCTAssertFalse(element("user.detail.refreshError", in: app).exists)
        XCTAssertTrue(app.staticTexts["Olena (updated)"].firstMatch.waitForExistence(timeout: 5))
        attachScreenshot(named: "user-pull-refresh-offline", from: app)
        // A second native gesture must work, and the same destination must stay mounted.
        pullToRefresh(in: app)
        XCTAssertTrue(element("user.presence.lastSeen", in: app).waitForExistence(timeout: 5))
        app.buttons["Zurück"].firstMatch.tap()
        XCTAssertTrue(element("userManagement.user.user-1", in: app).waitForExistence(timeout: 5))
        element("userManagement.user.user-1", in: app).tap()
        XCTAssertTrue(element("user.presence.lastSeen", in: app).waitForExistence(timeout: 5))
    }

    @MainActor
    func testUserDetailFailedPullKeepsScreenAndRetryWorks() throws {
        let app = launchUserRefreshApp(failing: true)
        openRefreshTestUser(in: app)
        XCTAssertTrue(element("user.presence.online", in: app).waitForExistence(timeout: 8))
        pullToRefresh(in: app)
        XCTAssertTrue(element("user.detail.refreshError", in: app).waitForExistence(timeout: 10))
        attachScreenshot(named: "user-pull-refresh-error", from: app)
        pullToRefresh(in: app)
        XCTAssertTrue(element("user.detail.refreshError", in: app).waitForNonExistence(timeout: 10))
        XCTAssertTrue(element("user.presence.lastSeen", in: app).waitForExistence(timeout: 10))
        app.buttons["Zurück"].firstMatch.tap()
        XCTAssertTrue(element("userManagement.user.user-1", in: app).waitForExistence(timeout: 5))
    }

    @MainActor
    func testOwnerContentPlanningExposesFourStableSections() throws {
        let app = launchOwnerApp()
        tapRootTab(rootTabs[3], in: app, timeout: 20)
        let planning = element("profile.contentPlanning", in: app)
        scrollToElement(planning, in: app, maxSwipes: 14)
        XCTAssertTrue(planning.waitForExistence(timeout: 8))
        planning.tap()

        XCTAssertTrue(element("screen.contentPlanning", in: app).waitForExistence(timeout: 10))
        for section in ["drafts", "scheduled", "attention", "history"] {
            let control = app.buttons["contentPlanning.section.\(section)"]
            XCTAssertTrue(control.waitForExistence(timeout: 5), "Missing planning section: \(section)")
            XCTAssertTrue(control.isHittable)
            control.tap()
        }
        attachScreenshot(named: "owner-content-planning-four-sections", from: app)
    }

    @MainActor
    func testMainFeedPullRefreshKeepsNavigationResponsive() throws {
        let app = launchAuthenticatedApp()
        for (index, filterID, cardPrefix) in [
            (0, "home.filter.type", "home.card."),
            (1, "events.filter.period", "event.card."),
            (2, "organizations.filter.category", "organization.card.")
        ] {
            tapRootTab(rootTabs[index], in: app, timeout: 15)
            XCTAssertTrue(element(filterID, in: app).waitForExistence(timeout: 8))
            pullToRefresh(in: app)
            XCTAssertTrue(element(filterID, in: app).exists)
            let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", cardPrefix)).firstMatch
            scrollToElement(card, in: app, maxSwipes: 5)
            XCTAssertTrue(card.waitForExistence(timeout: 5))
            card.tap()
            let back = app.buttons["navigation.back"].firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            pullToRefresh(in: app)
            XCTAssertTrue(back.isHittable)
            back.tap()
            XCTAssertTrue(element(filterID, in: app).waitForExistence(timeout: 5))
        }
    }

    private func launchUserRefreshApp(failing: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launchEnvironment["UITestResetUserSettings"] = "1"
        app.launchEnvironment["UITestAppLanguage"] = "de"
        app.launchEnvironment["UITestForceOwnerSession"] = "1"
        app.launchEnvironment["UITestUserRefresh"] = "1"
        if failing { app.launchEnvironment["UITestUserRefreshFailure"] = "1" }
        app.launch()
        return app
    }

    private func openRefreshTestUser(in app: XCUIApplication) {
        tapRootTab(rootTabs[3], in: app, timeout: 20)
        let users = element("profile.userManagement", in: app)
        scrollToElement(users, in: app, maxSwipes: 12)
        XCTAssertTrue(users.waitForExistence(timeout: 5))
        users.tap()
        let member = element("userManagement.user.user-1", in: app)
        XCTAssertTrue(member.waitForExistence(timeout: 8))
        member.tap()
    }

    private func pullToRefresh(in app: XCUIApplication) {
        let scroll = app.scrollViews.firstMatch
        let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    private func launchOwnerApp(
        language: String = "de",
        appearance: String? = nil,
        contentSizeCategory: String? = nil,
        resetContentDrafts: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-ui-testing")
        app.launchEnvironment["UITestResetUserSettings"] = "1"
        app.launchEnvironment["UITestAppLanguage"] = language
        app.launchEnvironment["UITestForceOwnerSession"] = "1"
        if resetContentDrafts {
            app.launchEnvironment["UITestResetContentDrafts"] = "1"
        }
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

    @MainActor
    func testAppStoreScreenshotSet() throws {
        for language in ["de", "uk"] {
            let app = launchGuestApp(language: language)
            XCTAssertTrue(app.otherElements["screen.home"].waitForExistence(timeout: 20))
            for (index, suffix) in [(0, "home"), (1, "events"), (2, "organizations"), (3, "profile")] {
                let tab = rootTabs[index]
                if app.tabBars.firstMatch.exists {
                    tapRootTab(tab, in: app, timeout: 20)
                } else {
                    let adaptiveTab = app.buttons[tab.tabIdentifier].firstMatch
                    XCTAssertTrue(adaptiveTab.waitForExistence(timeout: 20))
                    adaptiveTab.tap()
                    XCTAssertTrue(app.otherElements[tab.screenIdentifier].waitForExistence(timeout: 20))
                }
                attachScreenshot(named: "appstore-\(language)-0\(index + 1)-\(suffix)", from: app)
            }
            app.terminate()
        }
    }

    /// Captures the public production-backed guest experience used for App Store assets.
    /// This stays opt-in so the regular UI suite never depends on live Firebase content.
    @MainActor
    func testLiveAppStoreScreenshotSet() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["CAPTURE_APPSTORE_SCREENSHOTS"] == "1",
            "Set CAPTURE_APPSTORE_SCREENSHOTS=1 to capture live App Store screenshots."
        )

        let language = ProcessInfo.processInfo.environment["APPSTORE_SCREENSHOT_LANGUAGE"] ?? "uk"
        let app = XCUIApplication()
        app.launchEnvironment["UITestResetUserSettings"] = "1"
        app.launchEnvironment["UITestAppLanguage"] = language
        app.launchEnvironment["UITestForceGuestSession"] = "1"
        app.launch()

        XCTAssertTrue(app.otherElements["screen.home"].waitForExistence(timeout: 30))
        sleep(5)
        attachScreenshot(named: "appstore-live-\(language)-01-home", from: app)

        openRootTab(rootTabs[1], in: app, timeout: 30)
        sleep(5)
        attachScreenshot(named: "appstore-live-\(language)-02-events", from: app)

        let firstEvent = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "event.card."))
            .firstMatch
        if firstEvent.waitForExistence(timeout: 20) {
            firstEvent.tap()
            sleep(4)
            attachScreenshot(named: "appstore-live-\(language)-03-event-detail", from: app)
            let back = app.buttons["navigation.back"].firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 10))
            back.tap()
        }

        openRootTab(rootTabs[2], in: app, timeout: 30)
        sleep(5)
        attachScreenshot(named: "appstore-live-\(language)-04-organizations", from: app)

        let firstOrganization = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "organization.card."))
            .element(boundBy: 2)
        if firstOrganization.waitForExistence(timeout: 20) {
            firstOrganization.tap()
            sleep(4)
            attachScreenshot(named: "appstore-live-\(language)-05-organization-detail", from: app)
            let back = app.buttons["navigation.back"].firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 10))
            back.tap()
        }

        openRootTab(rootTabs[3], in: app, timeout: 30)
        sleep(3)
        attachScreenshot(named: "appstore-live-\(language)-06-profile", from: app)
        app.terminate()
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

    private func openRootTab(
        _ tab: MainTabSpec,
        in app: XCUIApplication,
        timeout: TimeInterval
    ) {
        if app.tabBars.firstMatch.waitForExistence(timeout: 2) {
            tapRootTab(tab, in: app, timeout: timeout)
            return
        }

        let adaptiveTab = app.buttons[tab.tabIdentifier].firstMatch
        XCTAssertTrue(adaptiveTab.waitForExistence(timeout: timeout))
        adaptiveTab.tap()
        XCTAssertTrue(app.otherElements[tab.screenIdentifier].waitForExistence(timeout: timeout))
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
    func testDiscoveryFiltersPinRegionAndPromoteActiveFiltersAcrossTabs() throws {
        let app = launchAuthenticatedApp()
        let configurations: [(tab: MainTabSpec, namespace: String, order: [String])] = [
            (rootTabs[0], "home", ["type", "region", "subscribed", "saved"]),
            (rootTabs[1], "events", ["period", "region", "category", "audience", "age", "registered", "saved"]),
            (rootTabs[2], "organizations", ["category", "region", "subscribed", "bookmarked"])
        ]
        for configuration in configurations {
            tapRootTab(configuration.tab, in: app)
            let namespace = configuration.namespace
            let row = app.scrollViews["\(namespace).filters"]
            scrollToElement(row, in: app)
            XCTAssertTrue(row.exists)
            func chip(_ name: String) -> XCUIElement { app.buttons["\(namespace).filter.\(name)"] }
            func expectOrder(_ names: [String]) {
                let actual = row.buttons.allElementsBoundByIndex.map(\.identifier)
                    .filter { $0.hasPrefix("\(namespace).filter.") }
                XCTAssertEqual(actual, names.map { "\(namespace).filter.\($0)" })
            }
            func reveal(_ button: XCUIElement) {
                for _ in 0..<12 {
                    if button.isHittable { break }
                    let rowFrame = row.frame
                    let buttonFrame = button.frame
                    let startX = buttonFrame.maxX <= rowFrame.minX ? 0.3 : 0.7
                    let endX = buttonFrame.maxX <= rowFrame.minX ? 0.7 : 0.3
                    row.coordinate(withNormalizedOffset: CGVector(dx: startX, dy: 0.5))
                        .press(
                            forDuration: 0.05,
                            thenDragTo: row.coordinate(
                                withNormalizedOffset: CGVector(dx: endX, dy: 0.5)
                            )
                        )
                }
                XCTAssertTrue(button.isHittable, button.debugDescription)
            }
            if namespace == "events" {
                let initialReset = chip("reset")
                if initialReset.exists {
                    reveal(initialReset)
                    initialReset.tap()
                    XCTAssertTrue(
                        initialReset.waitForNonExistence(timeout: 5),
                        "Reset chip should clear the persisted event region"
                    )
                }
            }
            expectOrder(configuration.order)
            let first = chip(configuration.order[0])
            let region = chip("region")
            XCTAssertTrue(first.isHittable)
            XCTAssertTrue(region.isHittable)
            XCTAssertLessThan(first.frame.minX, region.frame.minX)

            let savedName = configuration.order.last!
            let saved = chip(savedName)
            reveal(saved)
            saved.tap()
            let promoted: [String]
            if namespace == "events" {
                promoted = Array(configuration.order.prefix(2))
                    + ["reset", savedName]
                    + configuration.order.dropFirst(2).dropLast()
            } else {
                promoted = Array(configuration.order.prefix(2))
                    + [savedName]
                    + configuration.order.dropFirst(2).dropLast()
            }
            expectOrder(promoted)
            XCTAssertTrue(first.isHittable, "Row should return to its leading controls after reordering")
            XCTAssertTrue(region.isHittable)
            attachScreenshot(named: "\(namespace)-active-filter-order", from: app)

            if namespace == "events" {
                let audience = chip("audience")
                reveal(audience)
                audience.tap()
                app.buttons["Für Familien"].tap()
                expectOrder(["period", "region", "reset", "audience", "saved", "category", "age", "registered"])
                XCTAssertTrue(first.isHittable)
                attachScreenshot(named: "events-audience-active-before-reveal", from: app)
                reveal(audience)
                audience.tap()
                app.buttons["Für alle"].tap()
                expectOrder(promoted)

                let reset = chip("reset")
                reveal(reset)
                XCTAssertTrue(reset.isHittable)
                reset.tap()
                XCTAssertTrue(
                    reset.waitForNonExistence(timeout: 5),
                    "Reset chip should disappear after all event filters are cleared"
                )
            } else {
                reveal(saved)
                saved.tap()
            }
            expectOrder(configuration.order)
            XCTAssertTrue(first.isHittable)
            XCTAssertTrue(region.isHittable)
        }
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
    func testOrganizationLogoPickerDoesNotOverlapTheNameField() throws {
        defer { XCUIDevice.shared.orientation = .portrait }
        for (language, largeText) in [("uk", false), ("de", true)] {
            let app = XCUIApplication()
            app.launchArguments = ["-ui-testing"]
            app.launchEnvironment["UITestResetUserSettings"] = "1"
            app.launchEnvironment["UITestAppLanguage"] = language
            app.launchEnvironment["UITestForceAuthenticatedSession"] = "1"
            if largeText {
                app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            }
            app.launch()
            tapRootTab(rootTabs[2], in: app)
            let add = app.buttons["organizations.add"]
            XCTAssertTrue(add.waitForExistence(timeout: 10))
            add.tap()
            // A prior test launch may have saved its local draft. Dismiss the
            // recovery dialog before measuring the visible editor, not views behind it.
            let newDraft = app.buttons[language == "uk" ? "Створити нову" : "Neu erstellen"]
            if newDraft.waitForExistence(timeout: 2) { newDraft.tap() }
            let logo = app.buttons["organization.editor.logo"]
            let input = app.textFields["organization.editor.name"]
            let editorScroll = app.scrollViews.containing(.textField, identifier: "organization.editor.name").firstMatch
            XCTAssertTrue(editorScroll.waitForExistence(timeout: 5))
            for _ in 0..<25 {
                if input.exists && input.isHittable { break }
                editorScroll.swipeUp()
            }
            attachScreenshot(named: "organization-logo-visible-editor-\(language)", from: app)
            XCTAssertTrue(input.waitForExistence(timeout: 10))
            XCTAssertTrue(input.isHittable, "The name field must remain reachable in the visible editor")
            XCTAssertTrue(logo.exists)
            let title = app.staticTexts[language == "uk" ? "Назва *" : "Name *"].firstMatch
            XCTAssertTrue(title.exists)
            XCTAssertGreaterThanOrEqual(title.frame.minY, logo.frame.maxY + 4,
                                        "Upload instructions overlap the name title")
            XCTAssertGreaterThanOrEqual(input.frame.minY, logo.frame.maxY + 4)
            attachScreenshot(named: "organization-logo-editor-\(language)-\(largeText ? "AX" : "standard")", from: app)
            if !largeText {
                input.tap()
                input.typeText("MikaItalia")
                XCUIDevice.shared.orientation = .landscapeLeft
                scrollToElement(input, in: app, maxSwipes: 10)
                XCTAssertGreaterThanOrEqual(title.frame.minY, logo.frame.maxY + 4)
                XCTAssertTrue(input.isHittable)
                // iPhone supports portrait only; rotating must preserve the form.
                attachScreenshot(named: "organization-logo-editor-after-rotation", from: app)
                XCUIDevice.shared.orientation = .portrait
            }
            app.terminate()
        }
    }

    @MainActor
    private func openComments(_ kind: String, in app: XCUIApplication) {
        let cardID: String
        switch kind {
        case "events":
            assertRootScreen(screenIdentifier: "screen.events", tabLabel: "Veranstaltungen", in: app)
            cardID = "event.card.event-1"
        case "organizations":
            assertRootScreen(screenIdentifier: "screen.organizations", tabLabel: "Organisationen", in: app)
            cardID = "organization.card.org-1"
        default:
            assertRootScreen(screenIdentifier: "screen.home", tabLabel: "Start", in: app)
            cardID = "home.card.news-news-1"
        }
        var card = app.descendants(matching: .any).matching(identifier: cardID).firstMatch
        if kind == "news", !card.waitForExistence(timeout: 2) {
            // The owner fixture can have a different regional home feed than
            // the regular-user fixture. Open the first visible news card
            // instead of coupling this shared-detail test to one region.
            card = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", "home.card.news-"))
                .firstMatch
            if !card.waitForExistence(timeout: 2) {
                let regionFilter = app.buttons["home.filter.region"].firstMatch
                XCTAssertTrue(regionFilter.waitForExistence(timeout: 5))
                regionFilter.tap()
                let allAustria = app.buttons["Ganz Österreich"].firstMatch
                XCTAssertTrue(allAustria.waitForExistence(timeout: 5))
                allAustria.tap()
            }
        } else if kind == "events", !card.waitForExistence(timeout: 2) {
            card = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", "event.card."))
                .firstMatch
            if !card.waitForExistence(timeout: 2) {
                let regionFilter = app.buttons["events.filter.region"].firstMatch
                XCTAssertTrue(regionFilter.waitForExistence(timeout: 5))
                regionFilter.tap()
                let allAustria = app.buttons["Ganz Österreich"].firstMatch
                XCTAssertTrue(allAustria.waitForExistence(timeout: 5))
                allAustria.tap()
            }
        } else if kind == "organizations", !card.waitForExistence(timeout: 2) {
            card = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH %@", "organization.card."))
                .firstMatch
            if !card.waitForExistence(timeout: 2) {
                let regionFilter = app.buttons["organizations.filter.region"].firstMatch
                XCTAssertTrue(regionFilter.waitForExistence(timeout: 5))
                regionFilter.tap()
                let allAustria = app.buttons["Ganz Österreich"].firstMatch
                XCTAssertTrue(allAustria.waitForExistence(timeout: 5))
                allAustria.tap()
            }
        }
        scrollToElement(card, in: app, maxSwipes: 10)
        XCTAssertTrue(card.waitForExistence(timeout: 15), "Missing \(kind) card")
        card.tap()
    }

    @MainActor
    func testCommentSubmissionOnNewsEventsAndOrganizations() throws {
        for kind in ["news", "events", "organizations"] {
            let app = launchAuthenticatedApp()
            openComments(kind, in: app)
            let input = app.descendants(matching: .any).matching(identifier: "comments.input").firstMatch
            scrollToElement(input, in: app, maxSwipes: 20)
            XCTAssertTrue(input.waitForExistence(timeout: 10) && input.isHittable, "Missing composer: \(kind)")
            let message = "Comment check \(kind)"
            input.tap()
            input.typeText(message)
            let send = app.buttons["comments.send"]
            XCTAssertTrue(send.isEnabled)
            send.tap()
            let posted = app.staticTexts[message].firstMatch
            scrollToElement(posted, in: app, maxSwipes: 8)
            XCTAssertTrue(posted.waitForExistence(timeout: 10), "Comment was not posted: \(kind)")
            XCTAssertFalse(app.staticTexts["comments.sendError"].exists)
            attachScreenshot(named: "comments-posted-\(kind)", from: app)
            app.terminate()
        }
    }

    @MainActor
    func testGuestCommentEntryRequiresAuthenticationOnAllScreens() throws {
        for kind in ["news", "events", "organizations"] {
            let app = launchApp()
            openComments(kind, in: app)
            let signIn = app.buttons["comments.signIn"]
            scrollToElement(signIn, in: app, maxSwipes: 20)
            XCTAssertTrue(signIn.waitForExistence(timeout: 10) && signIn.isHittable)
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "comments.input").firstMatch.exists)
            signIn.tap()
            XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
            app.terminate()
        }
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
    func testOrganizationDetailShowsPersistedProfileAndContacts() throws {
        let app = launchApp()
        assertRootScreen(screenIdentifier: "screen.organizations", tabLabel: "Organisationen", in: app)
        let card = app.descendants(matching: .any).matching(identifier: "organization.card.org-1").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        let contacts = app.buttons["organization.section.contacts"]
        XCTAssertTrue(contacts.waitForExistence(timeout: 10))

        func reveal(_ text: String) {
            let element = app.staticTexts[text].firstMatch
            for _ in 0..<10 {
                if element.exists && element.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(element.exists && element.isHittable, "Field is not visible: \(text)")
        }
        reveal("Kostenlose Erstberatung ohne Angebotstitel")
        attachScreenshot(named: "organization-offer-without-title", from: app)
        reveal("09:00-18:00")
        reveal("Termine nach Vereinbarung")
        reveal("Sprachberatung")
        reveal("Kulturveranstaltungen")
        reveal("Tirol / Österreich")
        attachScreenshot(named: "organization-hours-and-services", from: app)

        for _ in 0..<12 {
            if contacts.isHittable { break }
            app.swipeDown()
        }
        XCTAssertTrue(contacts.isHittable)
        contacts.tap()
        reveal("Community Team")
        reveal("example.org/ukrainian-house-tirol")
        reveal("t.me/ukrainian_house")
        attachScreenshot(named: "organization-website-and-contacts", from: app)
        reveal("instagram.com/ukrainian_house")
        reveal("facebook.com/ukrainian_house")
        reveal("wa.me/43512123456")
        reveal("youtube.com/@ukrainian_house")
        reveal("linkedin.com/company/ukrainian-house")
        reveal("hello@example.org")
        reveal("+43 512 123456")
        reveal("Museumstraße 1, Innsbruck")
        attachScreenshot(named: "organization-all-contact-fields", from: app)
    }

    @MainActor
    func testOrganizationHeaderPrioritizesSaveShareAndMoreActions() throws {
        let app = launchAuthenticatedApp()
        assertRootScreen(screenIdentifier: "screen.organizations", tabLabel: "Organisationen", in: app)

        let card = app.descendants(matching: .any).matching(identifier: "organization.card.org-1").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()

        let moreActions = app.buttons.matching(identifier: "detail.header.more-actions").firstMatch
        XCTAssertTrue(moreActions.waitForExistence(timeout: 10))
        XCTAssertTrue(moreActions.isHittable)
        attachScreenshot(named: "organization-header-primary-actions", from: app)

        moreActions.tap()
        XCTAssertTrue(app.buttons["Melden"].waitForExistence(timeout: 5))
        attachScreenshot(named: "organization-header-safety-menu", from: app)
    }

    @MainActor
    func testOwnerManagementActionsUseTheSharedDetailMenu() throws {
        for kind in ["news", "events", "organizations"] {
            let app = launchOwnerApp()
            openComments(kind, in: app)

            let moreActions = app.buttons.matching(identifier: "detail.header.more-actions").firstMatch
            XCTAssertTrue(moreActions.waitForExistence(timeout: 10), "Missing More menu for \(kind)")
            moreActions.tap()

            XCTAssertTrue(app.buttons["Bearbeiten"].waitForExistence(timeout: 5), "Missing Edit for \(kind)")
            let destructiveAction = app.buttons["Löschen"].firstMatch
            let cancelEventAction = app.buttons["Veranstaltung absagen"].firstMatch
            XCTAssertTrue(
                destructiveAction.waitForExistence(timeout: 2) || cancelEventAction.waitForExistence(timeout: 2),
                "Missing destructive action for \(kind)"
            )
            attachScreenshot(named: "owner-detail-menu-\(kind)", from: app)
            app.terminate()
        }
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
        let submit = app.buttons["auth.register.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 10))
        let region = app.buttons["auth.register.federalState"]
        scrollToElement(region, in: app)
        XCTAssertTrue(region.exists)
        XCTAssertTrue(region.label.contains("Bundesland wählen"), region.debugDescription)
        XCTAssertFalse(submit.isEnabled)
        attachScreenshot(named: "registration-empty-region", from: app)

        region.tap()
        app.buttons["Wien"].tap()
        XCTAssertTrue(region.label.contains("Wien"), region.debugDescription)
        region.tap()
        app.buttons["Bundesland wählen"].tap()
        XCTAssertTrue(region.label.contains("Bundesland wählen"), region.debugDescription)
    }

    @MainActor
    func testRegistrationShowsConsentControls() throws {
        let app = launchApp(appLockScenario: "success")
        assertRootScreen(screenIdentifier: "screen.profile", tabLabel: "Profil", in: app)

        app.buttons["Konto erstellen"].firstMatch.tap()
        XCTAssertTrue(app.buttons["auth.register.submit"].waitForExistence(timeout: 10))
        let termsSwitch = app.switches[AppStringsPlaceholder.acceptTermsDE]
        scrollToElement(termsSwitch, in: app)
        XCTAssertTrue(termsSwitch.exists)
        XCTAssertEqual(termsSwitch.value as? String, "0")
        let analytics = app.switches["auth.register.analyticsConsent"]
        scrollToElement(analytics, in: app)
        XCTAssertTrue(analytics.isHittable)
        XCTAssertEqual(analytics.value as? String, "0", "Optional analytics must never be preselected")
        attachScreenshot(named: "registration-optional-analytics-off-de", from: app)
        analytics.tap()
        XCTAssertEqual(analytics.value as? String, "1")
        XCTAssertEqual(termsSwitch.value as? String, "0", "Analytics must not accept mandatory agreements")
        analytics.tap()
        XCTAssertEqual(analytics.value as? String, "0")
        let appLock = app.switches["auth.register.appLock"]
        scrollToElement(appLock, in: app)
        XCTAssertTrue(appLock.isHittable)
        XCTAssertEqual(appLock.value as? String, "0")
        attachScreenshot(named: "registration-faceid-optional-de", from: app)
        appLock.tap()
        expectation(for: NSPredicate(format: "value == '1'"), evaluatedWith: appLock)
        waitForExpectations(timeout: 8)
        XCTAssertEqual(analytics.value as? String, "0")
        XCTAssertEqual(termsSwitch.value as? String, "0")
        appLock.tap()
        XCTAssertEqual(appLock.value as? String, "0")
        scrollToElement(termsSwitch, in: app)
        termsSwitch.tap()
        XCTAssertEqual(analytics.value as? String, "0", "Terms acceptance must not opt in to analytics")
    }

    @MainActor
    func testRegistrationAnalyticsSupportsUkrainianLargeText() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launchEnvironment["UITestResetUserSettings"] = "1"
        app.launchEnvironment["UITestAppLanguage"] = "uk"
        app.launchEnvironment["UITestForceGuestSession"] = "1"
        app.launchEnvironment["UITestAppAppearance"] = "dark"
        app.launchEnvironment["UITestAppLockScenario"] = "success"
        app.launch()
        tapRootTab(rootTabs[3], in: app, timeout: 20)
        let create = app.buttons["Створити обліковий запис"].firstMatch
        scrollToElement(create, in: app, maxSwipes: 12)
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        create.tap()
        let analytics = app.switches["auth.register.analyticsConsent"]
        scrollToElement(analytics, in: app, maxSwipes: 35)
        XCTAssertTrue(analytics.isHittable)
        XCTAssertEqual(analytics.value as? String, "0")
        attachScreenshot(named: "registration-optional-analytics-uk-dark-AX", from: app)
        analytics.tap()
        XCTAssertEqual(analytics.value as? String, "1")
        let appLock = app.switches["auth.register.appLock"]
        scrollToElement(appLock, in: app, maxSwipes: 20)
        XCTAssertTrue(appLock.isHittable)
        XCTAssertEqual(appLock.value as? String, "0")
        attachScreenshot(named: "registration-faceid-uk-dark-AX", from: app)
        appLock.tap()
        expectation(for: NSPredicate(format: "value == '1'"), evaluatedWith: appLock)
        waitForExpectations(timeout: 8)
        let submit = app.buttons["auth.register.submit"]
        scrollToElement(submit, in: app, maxSwipes: 30)
        XCTAssertTrue(submit.isHittable)
        XCTAssertFalse(submit.isEnabled, "Optional consent must not bypass registration validation")
    }

    @MainActor
    func testRegistrationExplainsUnavailableBiometrics() throws {
        let app = launchApp(appLockScenario: "unavailable")
        tapRootTab(rootTabs[3], in: app, timeout: 20)
        app.buttons["Konto erstellen"].firstMatch.tap()
        let appLock = app.switches["auth.register.appLock"]
        scrollToElement(appLock, in: app, maxSwipes: 15)
        XCTAssertTrue(appLock.exists)
        XCTAssertFalse(appLock.isEnabled)
        XCTAssertEqual(appLock.value as? String, "0")
        attachScreenshot(named: "registration-faceid-unavailable-de", from: app)
    }

    @MainActor
    func testProfileSettingsContainsLegalRows() throws {
        for kind in ["terms", "privacy"] {
            let app = launchApp()
            assertRootScreen(screenIdentifier: "screen.profile", tabLabel: "Profil", in: app)
            let settings = app.buttons["profile.settings.open"].firstMatch
            scrollToElement(settings, in: app)
            XCTAssertTrue(settings.isHittable)
            settings.tap()

            let link = app.buttons["profile.legal.\(kind)"].firstMatch
            scrollToElement(link, in: app)
            XCTAssertTrue(link.isHittable)
            link.tap()
            XCTAssertTrue(element("legal.\(kind).screen", in: app).waitForExistence(timeout: 10))
            attachScreenshot(named: "guest-legal-\(kind)-de", from: app)
            app.terminate()
        }
    }

    @MainActor
    func testLanguageChangeKeepsSettingsNavigationAndUpdatesVisibleText() throws {
        let app = launchApp()
        assertRootScreen(screenIdentifier: "screen.profile", tabLabel: "Profil", in: app)
        let settings = app.buttons["profile.settings.open"].firstMatch
        scrollToElement(settings, in: app)
        XCTAssertTrue(settings.isHittable)
        settings.tap()

        let preferencesScreen = element("screen.profile.preferences", in: app)
        XCTAssertTrue(preferencesScreen.waitForExistence(timeout: 10))
        let languagePicker = element("profile.settings.language", in: app)
        XCTAssertTrue(languagePicker.waitForExistence(timeout: 10))
        XCTAssertTrue(languagePicker.isHittable)
        languagePicker.tap()

        let ukrainian = element("profile.settings.language.uk", in: app)
        XCTAssertTrue(ukrainian.waitForExistence(timeout: 5))
        ukrainian.tap()

        XCTAssertTrue(preferencesScreen.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Налаштування"].waitForExistence(timeout: 10))
        XCTAssertTrue(element("profile.settings.language", in: app).exists)
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
    func testProfileNotificationRowOpensInbox() throws {
        let app = launchAuthenticatedApp()
        assertRootScreen(screenIdentifier: "screen.profile", tabLabel: "Profil", in: app)

        let inbox = element("profile.notifications.open", in: app)
        scrollToElement(inbox, in: app, maxSwipes: 14)
        XCTAssertTrue(inbox.isHittable)
        inbox.tap()

        XCTAssertTrue(element("screen.notificationInbox", in: app).waitForExistence(timeout: 10))
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
