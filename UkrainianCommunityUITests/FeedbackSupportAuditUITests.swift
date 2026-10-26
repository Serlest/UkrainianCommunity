import XCTest

@MainActor final class FeedbackSupportAuditUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testOwnerInboxConversationBothLanguages() {
        for language in ["uk", "de"] {
            let app = launch(language: language)
            openInbox(app)
            let search = app.textFields["feedbackInbox.search"]
            reveal(search, app); search.tap(); search.typeText("feedback-audit-ordinary")
            let row = app.buttons["feedbackInbox.open.feedback-audit-ordinary"]
            XCTAssertTrue(row.waitForExistence(timeout: 8))
            dismissKeyboard(app); capture(app, "feedback-inbox-search-" + language)
            reveal(row, app); row.tap()
            let reply = app.textViews["feedback.reply.text"]
            XCTAssertTrue(reply.waitForExistence(timeout: 8))
            capture(app, "feedback-conversation-" + language)
            reveal(reply, app); reply.tap(); reply.typeText("Verified support response")
            dismissKeyboard(app)
            let send = app.buttons["feedback.reply.send"]
            reveal(send, app); send.tap()
            XCTAssertTrue(app.staticTexts["Verified support response"].firstMatch.waitForExistence(timeout: 8))
            capture(app, "feedback-reply-confirmed-" + language)
            app.buttons[language == "uk" ? "Готово" : "Fertig"].firstMatch.tap()
            XCTAssertTrue(search.waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    func testDecisionAndAppealReviewAtMaximumGermanText() {
        let app = launch(language: "de", maximum: true)
        openInbox(app)
        openCase("feedback-audit-dsa", app)
        let decision = app.buttons["feedback.conversation.close"]
        reveal(decision, app); capture(app, "feedback-dsa-context-de-dark-maximum"); decision.tap()
        let submit = app.buttons["feedback.dsa.decision.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 6)); XCTAssertFalse(submit.isEnabled)
        capture(app, "feedback-dsa-decision-de-dark-maximum")
        let facts = app.textFields["feedback.dsa.field.facts"]
        reveal(facts, app); facts.tap(); facts.typeText("Verified facts from the disposable audit fixture")
        dismissKeyboard(app)
        let legal = app.textFields["feedback.dsa.field.legal"]
        reveal(legal, app); legal.tap(); legal.typeText("Fixture terms basis")
        dismissKeyboard(app)
        let review = app.buttons["feedback.dsa.decision.humanReview"]
        reveal(review, app); review.tap()
        XCTAssertTrue(submit.isEnabled)
        capture(app, "feedback-dsa-valid-de-dark-maximum")
        let cancel = app.buttons["Abbrechen"].firstMatch
        XCTAssertTrue(cancel.exists); cancel.tap()
        XCTAssertTrue(decision.waitForExistence(timeout: 5))
        app.buttons["Fertig"].firstMatch.tap()
        let search = app.textFields["feedbackInbox.search"]
        reveal(search, app)
        let clear = app.buttons["feedbackInbox.search.clear"].firstMatch
        XCTAssertTrue(clear.waitForExistence(timeout: 5)); clear.tap()
        search.tap(); search.typeText("feedback-audit-review\n")
        XCTAssertEqual(search.value as? String, "feedback-audit-review")
        dismissKeyboard(app)
        let row = app.buttons["feedbackInbox.open.feedback-audit-review"]
        XCTAssertTrue(row.waitForExistence(timeout: 8)); reveal(row, app); row.tap()
        reveal(decision, app); decision.tap()
        let appeal = app.buttons["feedback.dsa.appeal.submit"]
        XCTAssertTrue(appeal.waitForExistence(timeout: 6)); XCTAssertFalse(appeal.isEnabled)
        capture(app, "feedback-appeal-review-de-dark-maximum")
        let reason = app.descendants(matching: .any)["feedback.dsa.appeal.reason"].firstMatch
        reveal(reason, app); reason.tap(); reason.typeText("The original decision was reviewed against the fixture")
        dismissKeyboard(app)
        let reviewed = app.buttons["feedback.dsa.appeal.humanReview"]
        reveal(reviewed, app); reviewed.tap()
        XCTAssertTrue(appeal.isEnabled)
        capture(app, "feedback-appeal-valid-de-dark-maximum")
        app.buttons["Abbrechen"].firstMatch.tap()
    }

    func testPersonalSearchIncludesSubjectAndConversationReopens() {
        let app = launch(language: "uk", owner: false)
        let tab = app.tabBars.buttons.element(boundBy: 4)
        XCTAssertTrue(tab.waitForExistence(timeout: 15)); tab.tap()
        let mine = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Мої звернення")).firstMatch
        reveal(mine, app); mine.tap()
        let search = app.textFields["feedback.mine.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 8)); search.tap(); search.typeText("Wohnsitzanmeldung")
        dismissKeyboard(app)
        let row = app.buttons["feedback.mine.open.feedback-audit-ordinary"]
        XCTAssertTrue(row.waitForExistence(timeout: 8)); capture(app, "feedback-personal-subject-search-uk")
        reveal(row, app); row.tap()
        XCTAssertTrue(app.textViews["feedback.reply.text"].waitForExistence(timeout: 5))
        app.buttons["Готово"].firstMatch.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
    }

    func testMissingAndFailedDetailNeverOfferActionsBeforeVerification() {
        for mode in ["deleted", "detail-error"] {
            let app = launch(language: "uk", mode: mode)
            openInbox(app); openCase("feedback-audit-ordinary", app)
            XCTAssertFalse(app.textViews["feedback.reply.text"].exists)
            XCTAssertFalse(app.buttons["feedback.conversation.close"].exists)
            if mode == "deleted" {
                XCTAssertTrue(app.otherElements["feedback.detail.unavailable"].firstMatch.waitForExistence(timeout: 8)
                    || app.staticTexts.matching(NSPredicate(format: "identifier == %@", "feedback.detail.unavailable")).firstMatch.exists)
                capture(app, "feedback-deleted-no-actions")
            } else {
                let retry = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Спробувати")).firstMatch
                XCTAssertTrue(retry.waitForExistence(timeout: 8)); capture(app, "feedback-detail-failed-no-actions"); retry.tap()
                XCTAssertTrue(app.textViews["feedback.reply.text"].waitForExistence(timeout: 8))
                capture(app, "feedback-detail-retry-confirmed")
            }
            app.terminate()
        }
    }

    func testOrdinaryStatusAndDeletionRequireSeparateConfirmation() {
        let app = launch(language: "uk")
        openInbox(app)
        let search = app.textFields["feedbackInbox.search"]
        search.tap(); search.typeText("feedback-audit-ordinary"); dismissKeyboard(app)
        let status = app.buttons["feedbackInbox.status.feedback-audit-ordinary"]
        XCTAssertTrue(status.waitForExistence(timeout: 8)); reveal(status, app); status.tap()
        capture(app, "feedback-status-menu")
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "переглянут")).firstMatch.tap()
        let trash = app.buttons["feedbackInbox.delete.feedback-audit-ordinary"]
        reveal(trash, app)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: trash)], timeout: 8), .completed)
        trash.tap()
        capture(app, "feedback-after-delete-tap")
        let cancel = app.buttons["Скасувати"].firstMatch
        XCTAssertTrue(app.popovers.firstMatch.waitForExistence(timeout: 5) || cancel.exists)
        capture(app, "feedback-delete-confirmation")
        if cancel.exists { cancel.tap() }
        else { app.coordinate(withNormalizedOffset: .init(dx: 0.03, dy: 0.35)).tap() }
        XCTAssertTrue(app.buttons["feedbackInbox.open.feedback-audit-ordinary"].exists)
        reveal(trash, app); trash.tap()
        let confirm = app.popovers.buttons["Видалити звернення"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(app.buttons["feedbackInbox.open.feedback-audit-ordinary"].waitForNonExistence(timeout: 8))
        capture(app, "feedback-delete-confirmed")
    }

    func testAppAdministratorCanChangeStatusButCannotDeleteInbox() {
        let app = launch(language: "uk", role: "admin")
        openInbox(app)
        let search = app.textFields["feedbackInbox.search"]
        search.tap(); search.typeText("feedback-audit-ordinary"); dismissKeyboard(app)
        let status = app.buttons["feedbackInbox.status.feedback-audit-ordinary"]
        XCTAssertTrue(status.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["feedbackInbox.delete.feedback-audit-ordinary"].exists)
        capture(app, "feedback-admin-status-no-delete")
        reveal(status, app); status.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "переглянут")).firstMatch.waitForExistence(timeout: 5))
    }

    func testSubmissionErrorRetainsEditableDraftAndRetrySucceeds() {
        let app = launch(language: "uk", owner: false, mode: "submit-error")
        let tab = app.tabBars.buttons.element(boundBy: 4)
        XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let compose = app.buttons["profile.feedback.compose"]
        reveal(compose, app); compose.tap()
        let text = app.textViews["feedback.compose.text"]
        XCTAssertTrue(text.waitForExistence(timeout: 8)); text.tap(); text.typeText("Retry the complete request")
        dismissKeyboard(app)
        let submit = app.buttons["feedback.compose.submit"]
        reveal(submit, app); submit.tap()
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: text)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 8), .completed)
        XCTAssertEqual(text.value as? String, "Retry the complete request")
        capture(app, "feedback-compose-failed-draft-retained")
        reveal(submit, app); submit.tap()
        let cleared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", "Retry the complete request"), object: text)
        XCTAssertEqual(XCTWaiter.wait(for: [cleared], timeout: 8), .completed)
        capture(app, "feedback-compose-retry-confirmed")
    }

    func testPersonalInitialFailureRetriesOwnHistory() {
        let app = launch(language: "uk", owner: false, mode: "mine-error")
        let tab = app.tabBars.buttons.element(boundBy: 4)
        XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let mine = app.buttons["profile.feedback.history"]
        reveal(mine, app); mine.tap()
        let retry = app.buttons["feedback.mine.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 8)); capture(app, "feedback-personal-error"); retry.tap()
        XCTAssertTrue(app.buttons["feedback.mine.open.feedback-audit-ordinary"].waitForExistence(timeout: 8))
        capture(app, "feedback-personal-retry-confirmed")
    }

    func testSlowSubmissionFreezesPayloadAtMaximumGermanText() {
        let app = launch(language: "de", owner: false, maximum: true, mode: "slow-submit")
        let tab = app.tabBars.buttons.element(boundBy: 4)
        XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let compose = app.buttons["profile.feedback.compose"]
        reveal(compose, app); compose.tap()
        let text = app.textViews["feedback.compose.text"]
        XCTAssertTrue(text.waitForExistence(timeout: 8)); reveal(text, app); text.tap(); text.typeText("A complete request with slow transport")
        dismissKeyboard(app)
        let submit = app.buttons["feedback.compose.submit"]
        reveal(submit, app); submit.tap()
        XCTAssertFalse(text.isEnabled); XCTAssertFalse(submit.isEnabled)
        capture(app, "feedback-compose-slow-frozen-de-maximum")
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: text)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 12), .completed)
        XCTAssertNotEqual(text.value as? String, "A complete request with slow transport")
        capture(app, "feedback-compose-slow-completed-de-maximum")
    }

    func testPersonalEmptyHistoryIsConfirmedWithoutError() {
        let app = launch(language: "uk", owner: false, mode: "empty")
        let tab = app.tabBars.buttons.element(boundBy: 4)
        XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let mine = app.buttons["profile.feedback.history"]
        reveal(mine, app); mine.tap()
        XCTAssertTrue(app.staticTexts["У вас поки немає звернень."].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["feedback.mine.retry"].exists)
        capture(app, "feedback-personal-confirmed-empty")
    }

    func testClearInboxConfirmationRetainsProtectedCases() {
        let app = launch(language: "uk")
        openInbox(app)
        let clear = app.buttons["feedbackInbox.clearAll"]
        XCTAssertTrue(clear.waitForExistence(timeout: 8)); clear.tap()
        let confirm = app.popovers.buttons["Видалити всі відгуки та скарги"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        capture(app, "feedback-clear-confirmation")
        app.coordinate(withNormalizedOffset: .init(dx: 0.03, dy: 0.35)).tap()
        XCTAssertTrue(app.buttons["feedbackInbox.open.feedback-audit-ordinary"].exists)
        clear.tap(); XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(app.buttons["feedbackInbox.open.feedback-audit-ordinary"].waitForNonExistence(timeout: 8))
        XCTAssertTrue(app.buttons["feedbackInbox.open.feedback-audit-dsa"].waitForExistence(timeout: 8))
        capture(app, "feedback-clear-retained-protected-case")
    }

    func testInboxFailureAndFailedNextPageRetry() {
        for mode in ["inbox-error", "page-error"] {
            let app = launch(language: "uk", mode: mode)
            openInbox(app)
            if mode == "page-error" {
                let more = app.buttons["feedbackInbox.more"]
                reveal(more, app); more.tap()
            }
            let retry = app.buttons["feedbackInbox.retry"]
            XCTAssertTrue(retry.waitForExistence(timeout: 8)); reveal(retry, app)
            capture(app, "feedback-" + mode + "-retry-visible")
            retry.tap()
            XCTAssertTrue(retry.waitForNonExistence(timeout: 8))
            let expected = app.buttons["feedbackInbox.open." + (mode == "inbox-error" ? "feedback-audit-ordinary" : "feedback-audit-76")]
            reveal(expected, app); XCTAssertTrue(expected.exists)
            capture(app, "feedback-" + mode + "-retry-confirmed")
            app.terminate()
        }
    }

    func testMessageFailureAndSendRetryPreserveDraft() {
        for mode in ["messages-error", "send-error"] {
            let app = launch(language: "uk", mode: mode)
            openInbox(app); openCase("feedback-audit-ordinary", app)
            if mode == "messages-error" {
                let retry = app.buttons["feedback.messages.retry"]
                XCTAssertTrue(retry.waitForExistence(timeout: 8)); reveal(retry, app)
                capture(app, "feedback-messages-error"); retry.tap()
                XCTAssertTrue(retry.waitForNonExistence(timeout: 8))
            } else {
                let field = app.textViews["feedback.reply.text"]
                XCTAssertTrue(field.waitForExistence(timeout: 8)); reveal(field, app); field.tap(); field.typeText("Preserved response after failure")
                dismissKeyboard(app)
                let send = app.buttons["feedback.reply.send"]
                reveal(send, app); send.tap()
                let editable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: field)
                XCTAssertEqual(XCTWaiter.wait(for: [editable], timeout: 8), .completed)
                XCTAssertEqual(field.value as? String, "Preserved response after failure")
                capture(app, "feedback-send-error-keeps-draft")
                reveal(send, app); send.tap()
                XCTAssertTrue(app.staticTexts["Preserved response after failure"].firstMatch.waitForExistence(timeout: 8))
            }
            app.terminate()
        }
    }

    private func launch(language: String, owner: Bool = true, maximum: Bool = false, mode: String = "", role: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-UIPreferredContentSizeCategoryName", maximum ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launchEnvironment = ["UITestResetUserSettings": "1", "UITestResetAppLock": "1", "UITestAppLanguage": language,
            "UITestAppAppearance": language == "de" ? "dark" : "light", "UITestFeedbackInbox": "1", "UITestFeedbackAudit": "1", "UITestFeedbackMode": mode,
            owner ? "UITestForceOwnerSession" : "UITestForceAuthenticatedSession": "1", "UITestLegalReverification": "success"]
        if let role { app.launchEnvironment["UITestProfileRole"] = role }
        app.launch(); return app
    }
    private func openInbox(_ app: XCUIApplication) {
        let tab = app.tabBars.buttons.element(boundBy: 4)
        XCTAssertTrue(tab.waitForExistence(timeout: 20)); tab.tap()
        let inbox = app.buttons["profile.feedbackInbox"]
        reveal(inbox, app); inbox.tap()
        XCTAssertTrue(app.textFields["feedbackInbox.search"].waitForExistence(timeout: 8))
    }
    private func openCase(_ id: String, _ app: XCUIApplication) {
        let search = app.textFields["feedbackInbox.search"]
        reveal(search, app); search.tap(); search.typeText(id); dismissKeyboard(app)
        let row = app.buttons["feedbackInbox.open." + id]
        XCTAssertTrue(row.waitForExistence(timeout: 8)); reveal(row, app); row.tap()
    }
    private func dismissKeyboard(_ app: XCUIApplication) {
        if app.keyboards.firstMatch.exists { app.swipeDown() }
    }
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<16 {
            if element.exists && element.isHittable { return }
            app.coordinate(withNormalizedOffset: .init(dx: 0.95, dy: 0.78)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: .init(dx: 0.95, dy: 0.32)))
        }
        XCTAssertTrue(element.exists)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        Thread.sleep(forTimeInterval: 0.4)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
