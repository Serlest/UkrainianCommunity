import XCTest

final class NotificationsAuditUITests: XCTestCase {
    @MainActor func testAnnouncementFeedbackIsAvailableToRecipientsButNotTheAppOwner() {
        continueAfterFailure = false
        for role in ["owner", "admin", "member"] {
            let app = XCUIApplication()
            app.launchArguments = ["-ui-testing"]
            app.launchEnvironment = ["UITestResetUserSettings":"1", "UITestAppLanguage":"uk", "UITestAnnouncements":"1",
                "UITestAnnouncementFeedback":"1", "UITestResetAppLock":"1"]
            if role == "owner" { app.launchEnvironment["UITestForceOwnerSession"] = "1" }
            else { app.launchEnvironment["UITestProfileRole"] = role }
            app.launch()
            let acknowledge = app.buttons["announcements.acknowledge"].firstMatch
            XCTAssertTrue(acknowledge.waitForExistence(timeout: 20))
            let feedback = app.buttons["announcements.writeFeedback"].firstMatch
            XCTAssertEqual(feedback.exists, role != "owner")
            capture("AnnouncementRecipientFeedback-" + role, app)
            acknowledge.tap(); app.terminate()
        }
    }
    @MainActor func testSavedVersionConflictKeepsEditsUntilExplicitReload() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launchEnvironment = ["UITestForceOwnerSession":"1", "UITestResetUserSettings":"1", "UITestAppLanguage":"uk", "UITestResetAppLock":"1", "UITestAnnouncementConflict":"1"]
        app.launch()
        let profile = app.tabBars.buttons.element(boundBy: 4)
        XCTAssertTrue(profile.waitForExistence(timeout: 20)); profile.tap()
        let entry = app.buttons["profile.announcements"]
        reveal(entry, app); entry.tap()
        let row = app.buttons.containing(.staticText, identifier: "Перевірка 0").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8)); row.tap()
        let title = app.textFields["announcements.headline"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText(" — локальна зміна")
        let expected = title.value as? String
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.12)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        let save = app.buttons["announcements.save"]
        capture("AnnouncementBeforeSave", app); hierarchy("AnnouncementBeforeSave", app)
        reveal(save, app); save.tap()
        let reload = app.buttons["announcements.reloadSaved"]
        reveal(reload, app); XCTAssertEqual(title.value as? String, expected)
        capture("AnnouncementConflictingSavePreservesForm", app); reload.tap()
        let confirm = app.buttons["announcements.confirmReload"].firstMatch
        reveal(confirm, app)
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        capture("AnnouncementReloadConfirmation", app); confirm.tap()
        reveal(title, app)
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Збережено на сервері"), object: title)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 8), .completed)
        capture("AnnouncementReloadedSavedVersion", app)
    }

    @MainActor func testClearAllCancelAndCommitInBothThemes() {
        continueAfterFailure = false
        for language in ["uk", "de"] {
            let app = XCUIApplication()
            app.launchArguments = ["-ui-testing", "-UIPreferredContentSizeCategoryName", language == "de" ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
            app.launchEnvironment = ["UITestResetUserSettings":"1", "UITestAppLanguage":language,
                "UITestForceAuthenticatedSession":"1", "UITestNotificationDetails":"1", "UITestResetAppLock":"1",
                "UITestAppAppearance":language == "de" ? "dark" : "light"]
            app.launch()
            let profile = app.tabBars.buttons.element(boundBy: 4)
            XCTAssertTrue(profile.waitForExistence(timeout: 20)); profile.tap()
            let inbox = app.buttons["profile.notifications.open"]
            reveal(inbox, app); inbox.tap()
            let row = app.buttons["notificationInbox.open.detail-info"]
            XCTAssertTrue(row.waitForExistence(timeout: 8))
            // The screen identifier is inherited by header controls; locate
            // this visible control by its localized accessibility label.
            let clear = app.buttons[language == "uk" ? "Видалити всі сповіщення" : "Alle Mitteilungen löschen"].firstMatch
            capture("NotificationBeforeClear-" + language, app); hierarchy("NotificationBeforeClear-" + language, app)
            reveal(clear, app); clear.tap()
            let cancel = app.buttons["notificationInbox.cancelClear"].firstMatch
            let confirm = app.buttons["notificationInbox.confirmClear"].firstMatch
            capture("NotificationClearWarningTop-" + language, app)
            reveal(cancel, app)
            XCTAssertTrue(confirm.waitForExistence(timeout: 5))
            capture("NotificationClearConfirmation-" + language, app)
            XCTAssertTrue(cancel.exists && cancel.isHittable); cancel.tap()
            XCTAssertTrue(confirm.waitForNonExistence(timeout: 5))
            XCTAssertTrue(row.exists); clear.tap()
            reveal(confirm, app)
            XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
            XCTAssertTrue(row.waitForNonExistence(timeout: 8)); XCTAssertFalse(clear.exists)
            capture("NotificationCleared-" + language, app)
            app.terminate()
        }
    }
    @MainActor func testOwnerFailedPageRetryAndRefreshRetainTheLoadedRange() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launchEnvironment = ["UITestForceOwnerSession":"1", "UITestResetUserSettings":"1", "UITestAppLanguage":"uk", "UITestResetAppLock":"1", "UITestAnnouncementPages":"1"]
        app.launch()
        let profile = app.tabBars.buttons.element(boundBy: 4)
        XCTAssertTrue(profile.waitForExistence(timeout: 20)); profile.tap()
        let entry = app.buttons["profile.announcements"]
        reveal(entry, app); entry.tap()
        let first = app.buttons.containing(.staticText, identifier: "Перевірка 0").firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        let more = app.buttons["announcements.loadMore"]
        reveal(more, app); more.tap()
        let retry = app.buttons["announcements.listRetry"]
        reveal(retry, app); capture("AnnouncementListFailedPage", app); retry.tap()
        let last = app.buttons.containing(.staticText, identifier: "Перевірка 2").firstMatch
        reveal(last, app); XCTAssertTrue(last.exists); XCTAssertFalse(more.exists)
        reveal(first, app)
        for _ in 0..<4 { app.swipeDown() }
        app.scrollViews.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
            .press(forDuration: 0.1, thenDragTo: app.scrollViews.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        reveal(last, app); XCTAssertTrue(last.exists); XCTAssertFalse(more.exists)
        capture("AnnouncementListRefreshRetainedRange", app)
    }
    @MainActor func testCriticalPopupLongMessageClosesAndDoesNotRepeat() {
        continueAfterFailure = false
        for language in ["uk", "de"] {
            let app = XCUIApplication()
            app.launchArguments = ["-ui-testing", "-UIPreferredContentSizeCategoryName", language == "de" ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
            app.launchEnvironment = ["UITestResetUserSettings":"1", "UITestAppLanguage":language,
                "UITestForceAuthenticatedSession":"1", "UITestNotificationDetails":"1", "UITestCriticalNotification":"1",
                "UITestAppAppearance":language == "de" ? "dark" : "light", "UITestResetAppLock":"1"]
            app.launch()
            let body = app.staticTexts["notificationPopup.body"]
            XCTAssertTrue(body.waitForExistence(timeout: 20))
            capture("CriticalPopupTop-" + language, app)
            let close = app.buttons["notificationPopup.close"]
            reveal(close, app); capture("CriticalPopupBottom-" + language, app); close.tap()
            XCTAssertTrue(close.waitForNonExistence(timeout: 5))
            XCUIDevice.shared.press(.home); app.activate()
            XCTAssertFalse(close.waitForExistence(timeout: 3))
            app.terminate()
        }
    }
    @MainActor func testFreshDetailFailureMissingAndReceiptRecovery() {
        continueAfterFailure = false
        for mode in ["missing", "networkOnce", "receiptOnce"] {
            let app = launch(mode: mode)
            let row = app.buttons["notificationInbox.open.detail-info"]
            XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
            let close = app.buttons["notificationDetail.close"]
            XCTAssertTrue(close.waitForExistence(timeout: 5))
            if mode == "missing" {
                XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "notificationDetail.unavailable").firstMatch.waitForExistence(timeout: 5))
                XCTAssertFalse(app.buttons["notificationDetail.delete"].exists)
                XCTAssertFalse(app.buttons["notificationDetail.openDestination"].exists)
                capture("NotificationMissing", app)
            } else if mode == "networkOnce" {
                let retry = app.buttons["notificationDetail.retry"]
                reveal(retry, app)
                XCTAssertTrue(app.staticTexts["notificationDetail.body"].exists)
                XCTAssertFalse(app.buttons["notificationDetail.delete"].isEnabled)
                capture("NotificationNetworkRetry", app)
                retry.tap()
                let delete = app.buttons["notificationDetail.delete"]
                reveal(delete, app)
                let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: delete)
                XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 8), .completed)
                XCTAssertFalse(retry.exists)
                capture("NotificationNetworkRecovered", app)
            } else {
                let error = app.descendants(matching: .any).matching(identifier: "notificationDetail.error").firstMatch
                reveal(error, app)
                XCTAssertTrue(app.staticTexts["notificationDetail.body"].exists)
                capture("NotificationReceiptFailureReadable", app)
                close.tap(); XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
                reveal(app.buttons["notificationDetail.delete"], app)
                XCTAssertFalse(error.exists)
            }
            close.tap(); app.terminate()
        }
    }

    @MainActor func testAllRolesHaveOwnInboxAndOnlyOwnerHasCampaignControls() {
        continueAfterFailure = false
        for role in ["owner", "admin", "org-owner", "org-admin", "org-moderator", "user"] {
            let app = XCUIApplication()
            app.launchArguments = ["-ui-testing"]
            app.launchEnvironment = ["UITestResetUserSettings":"1", "UITestAppLanguage":"uk", "UITestNotificationDetails":"1", "UITestResetAppLock":"1"]
            switch role {
            case "owner": app.launchEnvironment["UITestForceOwnerSession"] = "1"
            case "user": app.launchEnvironment["UITestForceAuthenticatedSession"] = "1"
            default:
                app.launchEnvironment["UITestProfileRole"] = role
            }
            app.launch()
            let profile = app.tabBars.buttons.element(boundBy: 4)
            XCTAssertTrue(profile.waitForExistence(timeout: 20)); profile.tap()
            let inbox = app.buttons["profile.notifications.open"]
            reveal(inbox, app); inbox.tap()
            XCTAssertTrue(app.buttons["notificationInbox.open.detail-info"].waitForExistence(timeout: 8))
            capture("NotificationRole-" + role, app)
            app.buttons["Назад"].firstMatch.tap()
            let campaign = app.buttons["profile.announcements"]
            if role == "owner" { reveal(campaign, app); XCTAssertTrue(campaign.exists) }
            else { XCTAssertFalse(campaign.exists) }
            app.terminate()
        }
    }

    @MainActor private func launch(mode: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launchEnvironment = ["UITestResetUserSettings":"1", "UITestAppLanguage":"uk", "UITestForceAuthenticatedSession":"1", "UITestNotificationDetails":"1", "UITestNotificationFailure":mode, "UITestResetAppLock":"1"]
        app.launch()
        let profile = app.tabBars.buttons.element(boundBy: 4)
        XCTAssertTrue(profile.waitForExistence(timeout: 20)); profile.tap()
        let inbox = app.buttons["profile.notifications.open"]
        reveal(inbox, app); inbox.tap()
        return app
    }
    @MainActor private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<24 {
            if element.exists && element.isHittable { return }
            let up = !element.exists || element.frame.midY > app.frame.midY
            if up { app.swipeUp() } else { app.swipeDown() }
        }
        capture("UnreachableElement", app); hierarchy("UnreachableElement", app)
        XCTAssertTrue(element.exists && element.isHittable)
    }
    @MainActor private func hierarchy(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name + "-hierarchy"; attachment.lifetime = .keepAlways; add(attachment)
    }
    @MainActor private func capture(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
