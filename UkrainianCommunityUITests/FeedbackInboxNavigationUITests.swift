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


/// Owner journeys use isolated UI-test repositories. No live mutations.
final class OwnerProfileAuditUITests: XCTestCase {
    @MainActor
    func testOwnerEditorGermanDarkLargeTextKeepsEveryFieldReachable() {
        let app = launch(language: "de", darkLarge: true)
        app.buttons["profile.edit.open"].tap()
        for id in ["displayName", "fullName", "city", "telegram"] {
            let field = app.textFields["profile.edit.\(id)"]
            reveal(field, in: app)
            XCTAssertTrue(field.isHittable)
            capture(app, "owner-editor-de-large-" + id)
        }
        XCTAssertFalse(app.buttons["profile.edit.save"].isEnabled)
    }

    @MainActor
    func testOwnerReplyPersistsInTheConversationAndAnsweredList() {
        let app = launch()
        let entry = app.buttons["profile.feedbackInbox"]
        reveal(entry, in: app); entry.tap()
        let row = app.buttons["feedbackInbox.open.directory-feedback-fixture"]
        XCTAssertTrue(row.waitForExistence(timeout: 8)); row.tap()
        let reply = app.textViews["feedback.reply.text"]
        XCTAssertTrue(reply.waitForExistence(timeout: 8))
        reply.tap(); reply.typeText("Owner reply persistence audit")
        app.buttons["feedback.reply.send"].tap()
        XCTAssertTrue(app.staticTexts["Owner reply persistence audit"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["Готово"].firstMatch.tap()
        let answered = app.segmentedControls.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Відповіді надано")).firstMatch
        XCTAssertTrue(answered.waitForExistence(timeout: 5)); answered.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        XCTAssertTrue(app.staticTexts["Owner reply persistence audit"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertEqual(app.staticTexts.matching(identifier: "Owner reply persistence audit").count, 1)
        capture(app, "owner-feedback-reply-persisted")
    }
    @MainActor
    func testFeedbackGermanDarkLargeTextOpensAndReplyControlsRemainReachable() {
        let app = launch(language: "de", darkLarge: true)
        let entry = app.buttons["profile.feedbackInbox"]
        reveal(entry, in: app); entry.tap()
        let row = app.buttons["feedbackInbox.open.directory-feedback-fixture"]
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
        XCTAssertTrue(app.textViews["feedback.reply.text"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["feedback.reply.send"].isHittable)
        capture(app, "feedback-conversation-de-dark-large")
    }

    @MainActor
    func testComplaintOpensItsActualReportedArticle() {
        let app = launch(reportContext: true)
        let entry = app.buttons["profile.feedbackInbox"]
        reveal(entry, in: app); entry.tap()
        let row = app.buttons["feedbackInbox.open.directory-feedback-fixture"]
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
        let target = app.buttons["feedback.report.openTarget"]
        XCTAssertTrue(target.waitForExistence(timeout: 8)); target.tap()
        XCTAssertTrue(app.buttons["news.like.news-1"].waitForExistence(timeout: 10))
        capture(app, "feedback-opens-reported-news")
    }

    @MainActor
    func testOrganizationWorkspaceSearchAndContentListsInBothLanguages() {
        for language in ["uk", "de"] {
            let app = launch(language: language, darkLarge: language == "de")
            let entry = app.buttons["profile.organizationManagement"]
            reveal(entry, in: app); entry.tap()
            let search = app.textFields["organization.management.search"]
            XCTAssertTrue(search.waitForExistence(timeout: 10))
            search.tap(); search.typeText("zzzz-no-organization")
            XCTAssertTrue(app.buttons["organization.manage.org-1"].waitForNonExistence(timeout: 8))
            app.buttons["organization.management.search.clear"].tap()
            let manage = app.buttons["organization.manage.org-1"]
            reveal(manage, in: app); XCTAssertTrue(manage.waitForExistence(timeout: 10)); manage.tap()
            for (buttonID, label) in [("organization.management.createNews", "news"), ("organization.management.createEvent", "events")] {
                let button = app.buttons[buttonID]; reveal(button, in: app); button.tap()
                XCTAssertTrue(app.buttons["organization.content.status"].waitForExistence(timeout: 8))
                XCTAssertTrue(app.buttons["organization.content.create"].exists)
                capture(app, "organization-workspace-" + label + "-" + language)
                back(app)
            }
            app.terminate()
        }
    }

    @MainActor
    func testOrganizationWorkspaceGermanDarkStatusContrast() {
        let app = launch(language: "de", darkLarge: true)
        let entry = app.buttons["profile.organizationManagement"]
        reveal(entry, in: app); entry.tap()
        let manage = app.buttons["organization.manage.org-1"]
        reveal(manage, in: app); manage.tap()
        let news = app.buttons["organization.management.createNews"]
        reveal(news, in: app); news.tap()
        XCTAssertTrue(app.buttons["organization.content.status"].waitForExistence(timeout: 8))
        capture(app, "organization-workspace-dark-status-contrast")
    }

    @MainActor
    func testDonationEditorValidatesAndPersistsChanges() {
        let app = launch()
        let entry = app.buttons["profile.owner.donationSettings"]
        reveal(entry, in: app); entry.tap()
        let url = app.textFields["donation.edit.url"]
        reveal(url, in: app)
        url.tap(); url.typeText("http://unsafe.example.org")
        let save = app.buttons["donation.edit.save"]
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.12)).tap()
        reveal(save, in: app)
        XCTAssertFalse(save.isEnabled)
        // Return to the URL field without leaving the unsaved editor.
        for _ in 0..<12 {
            if url.exists && url.isHittable { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.3))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.8)))
        }
        replace(url, with: "https://example.org/support")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.12)).tap()
        reveal(save, in: app); XCTAssertTrue(save.isEnabled); save.tap()
        expectation(for: NSPredicate(format: "enabled == false"), evaluatedWith: save)
        waitForExpectations(timeout: 10)
        back(app)
        XCTAssertTrue(entry.waitForExistence(timeout: 5)); entry.tap()
        reveal(url, in: app)
        XCTAssertEqual(url.value as? String, "https://example.org/support")
        capture(app, "owner-donation-saved")
    }

    @MainActor
    func testLegalDraftCanBeSavedAndReopenedWithoutPublishing() {
        let app = launch()
        let entry = app.buttons["profile.owner.legalDocuments"]
        reveal(entry, in: app); entry.tap()
        let edit = app.buttons["legal.manage.edit.terms"]
        reveal(edit, in: app); edit.tap()
        let german = app.textFields["legal.edit.summary.de"]
        reveal(german, in: app); german.tap(); german.typeText("Lokaler Testentwurf")
        let ukrainian = app.textFields["legal.edit.summary.uk"]
        replace(ukrainian, with: "Локальний тестовий опис")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.12)).tap()
        let save = app.buttons["legal.edit.save"]
        reveal(save, in: app); save.tap()
        let saved = NSPredicate(format: "enabled == false")
        expectation(for: saved, evaluatedWith: save)
        waitForExpectations(timeout: 10)
        back(app)
        XCTAssertTrue(edit.waitForExistence(timeout: 5)); edit.tap()
        XCTAssertEqual(german.value as? String, "Lokaler Testentwurf")
        XCTAssertEqual(ukrainian.value as? String, "Локальний тестовий опис")
        capture(app, "owner-legal-draft-saved")
    }
    @MainActor
    private func replace(_ field: XCUIElement, with value: String) {
        let app = XCUIApplication()
        if app.keyboards.firstMatch.exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.12)).tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        }
        reveal(field, in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        // Keep the control above the keyboard and the pinned save action before focusing it.
        for _ in 0..<5 where field.frame.midY > app.frame.height * 0.45 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.7))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.55)), withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let existing = field.value as? String ?? ""
        if existing.isEmpty || existing == field.placeholderValue {
            field.typeText(value)
            XCTAssertEqual(field.value as? String, value)
            return
        }
        field.press(forDuration: 1.2)
        let selectAll = app.menuItems.matching(NSPredicate(format: "label IN %@", ["Select All", "Alles auswählen", "Вибрати все", "Вибрати всі"])).firstMatch
        XCTAssertTrue(selectAll.waitForExistence(timeout: 3), app.debugDescription)
        selectAll.tap()
        field.typeText(XCUIKeyboardKey.delete.rawValue + value)
        if !value.isEmpty { XCTAssertEqual(field.value as? String, value) }
    }

    @MainActor
    func testOwnerEditsSavesAndReopensProfileWithoutLosingAdministration() {
        let app = launch()
        app.buttons["profile.edit.open"].tap()
        let name = app.textFields["profile.edit.displayName"]
        replace(name, with: "Owner Audit Saved")
        replace(app.textFields["profile.edit.fullName"], with: "Owner Complete Name")
        let save = app.buttons["profile.edit.save"]
        XCTAssertTrue(save.isEnabled); save.tap()
        XCTAssertTrue(app.buttons["profile.edit.open"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Owner Audit Saved"].exists)
        XCTAssertTrue(app.buttons["profile.organizationRequests"].exists)
        app.buttons["profile.edit.open"].tap()
        XCTAssertEqual(name.value as? String, "Owner Audit Saved")
        XCTAssertEqual(app.textFields["profile.edit.fullName"].value as? String, "Owner Complete Name")
        XCTAssertFalse(save.isEnabled)
        capture(app, "owner-profile-saved-and-reopened")
    }

    @MainActor
    func testProfileValidationAndDiscardProtectExistingData() {
        let app = launch()
        app.buttons["profile.edit.open"].tap()
        let name = app.textFields["profile.edit.displayName"]
        let original = name.value as? String
        replace(app.textFields["profile.edit.fullName"], with: "")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.12)).tap()
        capture(app, "owner-empty-name-validation")
        XCTAssertFalse(app.buttons["profile.edit.save"].isEnabled, "Full name value: \(String(describing: app.textFields["profile.edit.fullName"].value))")
        reveal(app.staticTexts["Вкажіть повне ім’я."], in: app)
        XCTAssertTrue(app.staticTexts["Вкажіть повне ім’я."].exists)
        app.buttons["Скасувати"].firstMatch.tap()
        let discard = app.buttons["Відхилити зміни"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 5)); discard.tap()
        XCTAssertTrue(app.buttons["profile.edit.open"].waitForExistence(timeout: 5))
        app.buttons["profile.edit.open"].tap()
        XCTAssertEqual(name.value as? String, original)
        XCTAssertFalse((app.textFields["profile.edit.fullName"].value as? String ?? "").isEmpty)
    }

    @MainActor
    func testOrganizationRolesExposeOnlyTheirOwnManagementActions() {
        continueAfterFailure = false
        for role in ["org-owner", "org-admin", "org-moderator", "mixed"] {
            let app = XCUIApplication()
            app.launchArguments = ["-ui-testing"]
            app.launchEnvironment = ["UITestProfileRole": role, "UITestResetUserSettings": "1",
                "UITestAppLanguage": "uk", "UITestResetAppLock": "1", "UITestFeedbackInbox": "1"]
            app.launch()
            let tab = app.tabBars.buttons.element(boundBy: 4)
            XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
            let entry = app.buttons["profile.organizationManagement"].firstMatch
            reveal(entry, in: app); entry.tap()
            let manage = app.buttons["organization.manage.role-fixture"].firstMatch
            reveal(manage, in: app); manage.tap()
            let news = app.buttons["organization.management.createNews"].firstMatch
            reveal(news, in: app)
            XCTAssertTrue(news.exists)
            XCTAssertEqual(app.buttons["organization.management.editInfo"].exists, role != "org-moderator")
            XCTAssertTrue(app.buttons["organization.management.createEvent"].exists)
            capture(app, "organization-role-" + role)
            let team = app.buttons["organization.management.addTeamMember"].firstMatch
            if role == "org-owner" {
                reveal(team, in: app)
                XCTAssertTrue(team.isHittable)
            } else {
                XCTAssertFalse(team.exists)
            }
            app.terminate()
        }
    }

    @MainActor
    func testAdminProfileSeparatesOperationalAndOwnerPermissions() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launchEnvironment = ["UITestProfileRole": "admin", "UITestResetUserSettings": "1",
            "UITestAppLanguage": "uk", "UITestResetAppLock": "1", "UITestFeedbackInbox": "1"]
        app.launch()
        let tab = app.tabBars.buttons.element(boundBy: 4)
        XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        for id in ["profile.directoryEditors", "profile.featuredBanners", "profile.owner.analytics",
                   "profile.owner.legalDocuments", "profile.owner.donationSettings", "profile.contentPlanning"] {
            XCTAssertFalse(app.buttons[id].exists, "Owner-only entry exposed: \(id)")
        }
        for id in ["profile.userManagement", "profile.organizationManagement", "profile.savedContent",
                   "profile.settings.open"] {
            let entry = app.buttons[id].firstMatch
            reveal(entry, in: app); capture(app, "admin-" + id)
            entry.tap()
            XCTAssertFalse(app.otherElements["profile.accessDenied"].exists)
            back(app)
        }
        app.terminate()
    }

    @MainActor
    func testOrganizationReviewDecisionAndHistoryInBothLanguages() {
        for language in ["uk", "de"] {
            let app = XCUIApplication()
            app.launchArguments = ["-ui-testing"]
            app.launchEnvironment = ["UITestForceOwnerSession": "1", "UITestResetUserSettings": "1",
                "UITestResetAppLock": "1", "UITestAppLanguage": language, "UITestOrganizationReview": "1",
                "UITestAppAppearance": language == "de" ? "dark" : "light"]
            if language == "de" {
                app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]
            }
            app.launch()
            let profile = app.tabBars.buttons.element(boundBy: 4)
            XCTAssertTrue(profile.waitForExistence(timeout: 15)); profile.tap()
            let requests = app.buttons["profile.organizationRequests"]
            reveal(requests, in: app); requests.tap()
            let open = app.buttons["organization.requests.open.audit-review-0"]
            XCTAssertTrue(open.waitForExistence(timeout: 10))
            capture(app, "organization-queue-" + language)
            open.tap()
            let decision = app.buttons["organization.request.choice.requestRevision"]
            reveal(decision, in: app)
            for _ in 0..<5 {
                if decision.frame.maxY < app.frame.height * 0.75 { break }
                app.swipeUp()
            }
            XCTAssertFalse(app.buttons["organization.request.confirm"].isEnabled)
            capture(app, "organization-decision-" + language)
            decision.tap()
            let revise = language == "uk" ? "Повернути на доопрацювання" : "Zur Überarbeitung zurückgeben"
            let reason = app.textFields["organization.request.reason"]
            XCTAssertTrue(reason.waitForExistence(timeout: 5))
            reveal(reason, in: app); reason.tap(); reason.typeText("Please add contact details.")
            capture(app, "organization-reason-" + language)
            let confirm = app.buttons["organization.request.confirm"]
            XCTAssertTrue(confirm.isEnabled); confirm.tap()
            let execute = app.buttons.matching(identifier: "organization.request.execute")
                .matching(NSPredicate(format: "label == %@", revise)).firstMatch
            XCTAssertTrue(execute.waitForExistence(timeout: 5)); execute.tap()
            XCTAssertTrue(open.waitForNonExistence(timeout: 8))
            let history = app.segmentedControls.buttons[language == "uk" ? "Історія рішень" : "Entscheidungsverlauf"]
            XCTAssertTrue(history.waitForExistence(timeout: 5)); history.tap()
            XCTAssertTrue(app.staticTexts["Please add contact details."].waitForExistence(timeout: 8))
            capture(app, "organization-history-" + language)
            app.terminate()
        }
    }

    @MainActor
    func testContentModerationFullReviewAndHistoryBothLanguages() {
        for language in ["uk", "de"] {
            let app = launch(language: language, darkLarge: language == "de")
            let entry = app.buttons["profile.moderation"]
            reveal(entry, in: app); entry.tap()
            let first = app.buttons["content.moderation.open.moderation-news-0"]
            reveal(first, in: app); first.tap()
            let languagePicker = app.segmentedControls["content.review.language"]
            XCTAssertTrue(languagePicker.waitForExistence(timeout: 8))
            languagePicker.buttons["Deutsch"].tap()
            XCTAssertTrue(app.staticTexts["Nachricht der Gemeinschaft 0"].firstMatch.waitForExistence(timeout: 5))
            capture(app, "content-moderation-preview-" + language)
            let revise = app.buttons["content.review.choice.needsRevision"]
            reveal(revise, in: app); revise.tap()
            let reason = app.textFields["content.review.reason"]
            reveal(reason, in: app); reason.tap(); reason.typeText("Please verify the official source")
            let confirm = app.buttons["content.review.confirm"]
            XCTAssertTrue(confirm.isEnabled); confirm.tap()
            let execute = app.alerts.buttons["content.review.execute"].firstMatch
            XCTAssertTrue(execute.waitForExistence(timeout: 5), app.debugDescription)
            capture(app, "content-moderation-confirm-" + language)
            execute.tap()
            XCTAssertTrue(first.waitForNonExistence(timeout: 8))
            let mode = app.segmentedControls["content.moderation.mode"]
            mode.buttons.element(boundBy: 1).tap()
            XCTAssertTrue(app.staticTexts["Please verify the official source"].firstMatch.waitForExistence(timeout: 8))
            capture(app, "content-moderation-history-" + language)
            app.terminate()
        }
    }

    @MainActor
    func testContentModerationApproveAndRejectRequireConfirmation() {
        let app = launch()
        let entry = app.buttons["profile.moderation"]
        reveal(entry, in: app); entry.tap()
        for (index, status) in [(0, "approved"), (1, "rejected")] {
            let row = app.buttons["content.moderation.open.moderation-news-\(index)"]
            reveal(row, in: app); row.tap()
            let choice = app.buttons["content.review.choice.\(status)"]
            reveal(choice, in: app); choice.tap()
            let confirm = app.buttons["content.review.confirm"]
            if status == "rejected" {
                XCTAssertFalse(confirm.isEnabled)
                let reason = app.textFields["content.review.reason"]
                reveal(reason, in: app); reason.tap(); reason.typeText("Source does not support the claim")
            }
            XCTAssertTrue(confirm.isEnabled); confirm.tap()
            let execute = app.alerts.buttons["content.review.execute"].firstMatch
            XCTAssertTrue(execute.waitForExistence(timeout: 5))
            capture(app, "content-moderation-" + status)
            execute.tap()
            XCTAssertTrue(row.waitForNonExistence(timeout: 8))
        }
        app.segmentedControls["content.moderation.mode"].buttons.element(boundBy: 1).tap()
        XCTAssertTrue(app.staticTexts["Source does not support the claim"].firstMatch.waitForExistence(timeout: 8))
    }

    @MainActor
    private func launch(language: String = "uk", darkLarge: Bool = false, reportContext: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launchEnvironment = ["UITestForceOwnerSession": "1", "UITestResetUserSettings": "1",
                                 "UITestAppLanguage": language, "UITestResetAppLock": "1",
                                 "UITestFeedbackInbox": "1", "UITestLegalEvidence": "1", "UITestUserRefresh": "1"]
        app.launchEnvironment["UITestAppAppearance"] = darkLarge ? "dark" : "light"
        if reportContext { app.launchEnvironment["UITestFeedbackReportContext"] = "1" }
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
            let scrollBack = item.exists && item.frame.maxY < app.frame.height * 0.3
            let from: CGFloat = scrollBack ? 0.3 : 0.8
            let to: CGFloat = scrollBack ? 0.8 : 0.3
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: from))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: to)), withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        capture(app, "unreachable-control")
        XCTFail("Cannot reach \(item): \(app.debugDescription)")
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
            ("profile.directoryEditors", "Доступ до редагування довідника"),
            ("profile.contentPlanning", "Контроль публікацій"),
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
        for id in ["blockedOrganizations", "blockedUsers"] {
            let link = app.buttons["profile.settings.\(id)"]
            reveal(link, in: app); link.tap()
            XCTAssertTrue(app.otherElements["screen.profile.\(id)"].waitForExistence(timeout: 8))
            back(app)
        }
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

extension OwnerProfileAuditUITests {
    @MainActor func testLegalCloseCanDiscardUnsavedChanges() {
        let app = launch()
        let entry = app.buttons["profile.owner.legalDocuments"]
        reveal(entry, in: app); entry.tap()
        let edit = app.buttons["legal.manage.edit.terms"]
        reveal(edit, in: app); edit.tap()
        let german = app.textFields["legal.edit.summary.de"]
        reveal(german, in: app); german.tap(); german.typeText("Unsaved draft")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.12)).tap()
        back(app)
        let discard = app.buttons["Вийти без збереження"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5)); discard.tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 5)); edit.tap()
        XCTAssertNotEqual(german.value as? String, "Unsaved draft")
        capture(app, "legal-close-discard")
    }
    @MainActor func testLegalPrivacyGermanDarkLargeTextAndHistory() {
        let app = launch(language: "de", darkLarge: true)
        let entry = app.buttons["profile.owner.legalDocuments"]
        reveal(entry, in: app); entry.tap()
        let history = app.buttons["legal.manage.history.privacy"]
        reveal(history, in: app); history.tap()
        XCTAssertTrue(app.staticTexts["Versionsverlauf"].waitForExistence(timeout: 5))
        back(app)
        let edit = app.buttons["legal.manage.edit.privacy"]
        reveal(edit, in: app); edit.tap()
        let save = app.buttons["legal.edit.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        let translation = app.buttons["translation.legal"]
        reveal(translation, in: app)
        XCTAssertTrue(translation.isEnabled)
        capture(app, "legal-privacy-de-dark-large")
    }
}

extension OwnerProfileAuditUITests {
    @MainActor func testLegalSavedDraftCanBeExplicitlyDiscarded() {
        let app = launch()
        let entry = app.buttons["profile.owner.legalDocuments"]
        reveal(entry, in: app); entry.tap()
        let edit = app.buttons["legal.manage.edit.terms"]
        reveal(edit, in: app); edit.tap()
        let german = app.textFields["legal.edit.summary.de"]
        reveal(german, in: app); german.tap(); german.typeText("Discard saved fixture")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.12)).tap()
        let save = app.buttons["legal.edit.save"]
        save.tap()
        expectation(for: NSPredicate(format: "enabled == false"), evaluatedWith: save)
        waitForExpectations(timeout: 10)
        back(app)
        XCTAssertTrue(edit.waitForExistence(timeout: 5)); edit.tap()
        XCTAssertTrue(german.waitForExistence(timeout: 5))
        XCTAssertEqual(german.value as? String, "Discard saved fixture")
        app.buttons["legal.edit.actions"].tap()
        let discard = app.buttons["Відхилити чернетку"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 5)); discard.tap()
        let confirm = app.buttons["legal.edit.confirmDiscard"].exists
            ? app.buttons["legal.edit.confirmDiscard"].firstMatch : app.buttons["Відхилити чернетку"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 5)); edit.tap()
        XCTAssertNotEqual(german.value as? String, "Discard saved fixture")
        app.buttons["legal.edit.actions"].tap()
        XCTAssertFalse(app.buttons["Відхилити чернетку"].exists)
        capture(app, "legal-saved-draft-discarded")
    }
}
