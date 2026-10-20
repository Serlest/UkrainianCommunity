import XCTest

final class FeedbackInboxNavigationUITests: XCTestCase {
    @MainActor
    func testOwnerOpensFeedbackAndReturnsToInbox() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launchEnvironment["UITestResetUserSettings"] = "1"
        app.launchEnvironment["UITestAppLanguage"] = "uk"
        app.launchEnvironment["UITestForceOwnerSession"] = "1"
        app.launchEnvironment["UITestFeedbackInbox"] = "1"
        app.launchEnvironment["UITestLegalReverification"] = "success"
        app.launch()
        let profile = app.tabBars.buttons.element(boundBy: 4)
        XCTAssertTrue(profile.waitForExistence(timeout: 15)); profile.tap()
        let inbox = app.buttons["profile.feedbackInbox"]
        reveal(inbox, app); inbox.tap()
        let row = app.buttons["feedbackInbox.open.directory-feedback-fixture"]
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).tap()
        XCTAssertTrue(app.buttons["Готово"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Feedback navigation fixture"].firstMatch.exists)
        app.buttons["Готово"].firstMatch.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        app.activate()
        let verifying = app.otherElements["startup.access.verifying"].firstMatch
        XCTAssertTrue(verifying.waitForExistence(timeout: 5))
        XCTAssertTrue(verifying.waitForNonExistence(timeout: 15))
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.buttons["Готово"].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testUserOpensOwnRequestAndNotificationsFromProfileAndBell() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launchEnvironment["UITestResetUserSettings"] = "1"
        app.launchEnvironment["UITestAppLanguage"] = "uk"
        app.launchEnvironment["UITestForceAuthenticatedSession"] = "1"
        app.launchEnvironment["UITestFeedbackInbox"] = "1"
        app.launchEnvironment["UITestNotificationDetails"] = "1"
        app.launch()
        let profile = app.tabBars.buttons.element(boundBy: 4)
        XCTAssertTrue(profile.waitForExistence(timeout: 15)); profile.tap()
        let mine = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Мої звернення")).firstMatch
        reveal(mine, app); mine.tap()
        let request = app.buttons["feedback.mine.open.directory-feedback-fixture"]
        XCTAssertTrue(request.waitForExistence(timeout: 8)); request.tap()
        let done = app.buttons["Готово"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5)); done.tap()
        XCTAssertTrue(request.waitForExistence(timeout: 5))
        app.buttons["Назад"].firstMatch.tap()
        let inbox = app.buttons["profile.notifications.open"]
        reveal(inbox, app); inbox.tap()
        openAndCloseNotification(app)
        app.buttons["Назад"].firstMatch.tap()
        let bell = app.buttons["notificationInbox.bell"]
        reveal(bell, app); bell.tap()
        openAndCloseNotification(app)
        app.buttons["Назад"].firstMatch.tap()
        XCTAssertTrue(bell.waitForExistence(timeout: 5))
        XCTAssertTrue(profile.isSelected)
    }

    @MainActor
    private func openAndCloseNotification(_ app: XCUIApplication) {
        let row = app.buttons["notificationInbox.open.detail-info"]
        XCTAssertTrue(row.waitForExistence(timeout: 8)); row.tap()
        let close = app.buttons["notificationDetail.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5)); close.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
    }

    @MainActor
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<14 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists)
    }
}


/// Read-only navigation checks. These never submit, publish, revoke access or delete data.
final class OwnerProfileAuditUITests: XCTestCase {
    @MainActor
    private func launch(language: String = "uk", darkLarge: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launchEnvironment = ["UITestForceOwnerSession": "1", "UITestResetUserSettings": "1",
                                 "UITestAppLanguage": language, "UITestResetAppLock": "1",
                                 "UITestFeedbackInbox": "1", "UITestLegalEvidence": "1", "UITestUserRefresh": "1"]
        app.launchEnvironment["UITestAppAppearance"] = darkLarge ? "dark" : "light"
        if darkLarge { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"] }
        app.launch()
        let profile = app.tabBars.buttons.element(boundBy: 4)
        XCTAssertTrue(profile.waitForExistence(timeout: 20)); profile.tap()
        return app
    }

    @MainActor
    private func reveal(_ item: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<30 {
            if item.exists && item.isHittable { return }
            app.swipeUp()
        }
        XCTFail("Cannot reach \(item)")
    }

    @MainActor
    private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }

    @MainActor
    private func back(_ app: XCUIApplication) {
        let custom = app.buttons["navigation.back"].firstMatch
        if custom.exists { custom.tap(); return }
        // Some screen containers propagate their accessibility identifier onto
        // the shared back button. Its localized accessibility label remains stable.
        for label in ["Назад", "Zurück", "Back"] {
            let button = app.buttons[label].firstMatch
            if button.exists { button.tap(); return }
        }
        let native = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(native.exists); native.tap()
    }

    @MainActor
    func testEveryOwnerProfileDestinationOpensAndReturns() {
        let app = launch()
        XCTAssertFalse(app.otherElements["profile.supportSection"].exists)
        XCTAssertFalse(app.buttons["profile.announcementHistory"].exists)
        let routes: [(String, String)] = [
            ("profile.organizationRequests", "Заявки на організації"),
            ("profile.moderation", "Інструменти модерації"),
            ("profile.feedbackInbox", "Відгуки та скарги"),
            ("profile.organizationManagement", "Керування організаціями"),
            ("profile.userManagement", "Керування користувачами"),
            ("profile.directoryEditors", "Редактори довідника"),
            ("profile.contentPlanning", "Планування контенту"),
            ("profile.featuredBanners", "Рекомендований контент"),
            ("profile.announcements", "Оповіщення користувачів"),
            ("profile.owner.analytics", "Аналітика"),
            ("profile.owner.systemLogs", "Журнал системи"),
            ("profile.owner.legalDocuments", "Правові документи"),
            ("profile.owner.legalEvidence", "Згоди та юридичні підтвердження"),
            ("profile.owner.donationSettings", "Налаштування підтримки проєкту"),
            ("profile.registrations", "Мої реєстрації на події"),
            ("profile.savedContent", "Збережене"),
            ("profile.followedOrganizations", "Підписки"),
            ("profile.recentViews", "Нещодавно переглянуте"),
            ("profile.activityHistory", "Історія активності"),
            ("profile.notifications.open", "Сповіщення"),
            ("profile.settings.open", "Налаштування")
        ]
        for (id, title) in routes {
            let link = app.buttons[id].firstMatch
            reveal(link, in: app)
            capture(app, "root-" + id)
            link.tap()
            let heading = app.staticTexts[title].firstMatch
            XCTAssertTrue(heading.waitForExistence(timeout: 10) || app.navigationBars[title].exists, "Wrong destination for " + id)
            capture(app, "destination-" + id)
            back(app)
            XCTAssertTrue(app.buttons[id].firstMatch.waitForExistence(timeout: 8), "Did not return from " + id)
        }
    }

    @MainActor
    func testOwnerSettingsNestedRoutesAndDeletionRestriction() {
        let app = launch()
        let settings = app.buttons["profile.settings.open"]
        reveal(settings, in: app); settings.tap()
        let security = app.buttons["profile.settings.accountSecurity"]
        reveal(security, in: app); security.tap()
        XCTAssertTrue(app.otherElements["screen.accountSecurity"].waitForExistence(timeout: 10))
        capture(app, "owner-account-security"); back(app)
        for (id, screen) in [("profile.legal.terms", "legal.terms.screen"), ("profile.legal.privacy", "legal.privacy.screen")] {
            let link = app.buttons[id]; reveal(link, in: app); link.tap()
            XCTAssertTrue(app.otherElements[screen].waitForExistence(timeout: 10))
            back(app)
        }
        let restriction = app.staticTexts["profile.owner.deletionRestriction"]
        reveal(restriction, in: app)
        XCTAssertTrue(restriction.exists)
        XCTAssertFalse(app.buttons["profile.delete_account.button"].exists)
        capture(app, "owner-deletion-restriction")
    }

    @MainActor
    func testOwnerProfileUkrainianLightAndGermanDarkLargeTextLayout() {
        for (language, large) in [("uk", false), ("de", true)] {
            let app = launch(language: language, darkLarge: large)
            XCTAssertFalse(app.otherElements["profile.supportSection"].exists)
            capture(app, "owner-" + language + "-top")
            for id in ["profile.organizationManagement", "profile.contentPlanning", "profile.owner.analytics",
                       "profile.owner.legalDocuments", "profile.registrations", "profile.settings.open", "profile.logout.button"] {
                let link = app.buttons[id]; reveal(link, in: app)
                XCTAssertTrue(link.isHittable)
                capture(app, "owner-" + language + "-" + id.replacingOccurrences(of: ".", with: "-"))
            }
            app.terminate()
        }
    }
}
