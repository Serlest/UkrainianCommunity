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

    private func launch(language: String, owner: Bool = true, maximum: Bool = false, mode: String = "") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-UIPreferredContentSizeCategoryName", maximum ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launchEnvironment = ["UITestResetUserSettings": "1", "UITestResetAppLock": "1", "UITestAppLanguage": language,
            "UITestAppAppearance": language == "de" ? "dark" : "light", "UITestFeedbackInbox": "1", "UITestFeedbackAudit": "1", "UITestFeedbackMode": mode,
            owner ? "UITestForceOwnerSession" : "UITestForceAuthenticatedSession": "1", "UITestLegalReverification": "success"]
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
