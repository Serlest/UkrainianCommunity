import XCTest

@MainActor
final class NewsAuditUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testEditorStepsAndTranslationAtGermanDarkAccessibilitySize() {
        let app = launch(role: "owner", language: "de", dark: true, large: true)
        open("audit-own", app); app.buttons["detail.header.more-actions"].tap(); app.buttons["Bearbeiten"].tap()
        let next = app.buttons["editor.news.next"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 8)); capture(app, "news-editor-basics-de-dark-AX")
        reveal(next, app); next.tap()
        let translate = app.buttons["translation.news"].firstMatch
        reveal(translate, app, fullyVisible: true); capture(app, "news-editor-translation-de-dark-AX")
        let fields = app.descendants(matching: .any)["editor.news.germanFields"].firstMatch
        reveal(fields, app); fields.tap()
        let germanTitle = app.textFields["editor.news.germanTitle"].firstMatch
        reveal(germanTitle, app, fullyVisible: true); XCTAssertTrue(germanTitle.exists); capture(app, "news-editor-german-fields-de-dark-AX")
        reveal(next, app); next.tap()
        let preview = app.descendants(matching: .any)["editor.news.preview"].firstMatch
        reveal(preview, app); alignTop(preview, app); capture(app, "news-editor-preview-de-dark-AX")
        let notice = app.staticTexts["editor.news.publicationNotice"].firstMatch
        reveal(notice, app); alignTop(notice, app); capture(app, "news-editor-notice-de-dark-AX")
        app.buttons["editor.close"].firstMatch.tap()
        XCTAssertTrue(app.buttons["news.like.audit-own"].firstMatch.waitForExistence(timeout: 8))
    }

    func testOwnAndForeignNewsMenusRespectEveryUsableRole() {
        for role in ["owner", "admin", "org-owner", "org-admin", "org-moderator", "mixed", "member", "warned"] {
            let app = launch(role: role)
            for id in ["audit-own", "audit-foreign"] {
                open(id, app)
                let more = app.buttons["detail.header.more-actions"].firstMatch
                XCTAssertTrue(more.waitForExistence(timeout: 8)); more.tap()
                let authorized = role == "owner" || (id == "audit-own" && ["org-owner", "org-admin", "org-moderator", "mixed"].contains(role))
                if authorized { XCTAssertTrue(app.buttons["Редагувати"].waitForExistence(timeout: 5)) }
                XCTAssertEqual(app.buttons["Редагувати"].exists, authorized, "Edit: \(role), \(id)")
                let canDelete = role == "owner" || (id == "audit-own" && ["org-owner"].contains(role))
                XCTAssertEqual(app.buttons["Видалити"].exists, canDelete, "Delete: \(role), \(id)")
                capture(app, "news-role-\(role)-\(id)")
                // Relaunch isolates the next menu without relying on a tap through a popup.
                app.terminate(); app.launch()
            }
            app.terminate()
        }
    }

    func testOwnerEditsSavesAndReopensExactNews() {
        let app = launch(role: "owner")
        open("audit-own", app)
        app.buttons["detail.header.more-actions"].tap()
        app.buttons["Редагувати"].tap()
        let title = app.textFields["editor.news.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 8)); title.tap(); title.typeText(" Updated")
        dismissKeyboard(app)
        let next = app.buttons["editor.news.next"].firstMatch
        reveal(next, app); next.tap()
        let body = app.textViews["editor.news.body"]
        reveal(body, app); XCTAssertTrue(body.exists)
        capture(app, "news-edit-content")
        reveal(next, app); next.tap()
        let submit = app.buttons["editor.news.submit"].firstMatch
        reveal(submit, app); capture(app, "news-edit-preview")
        XCTAssertTrue(submit.isEnabled); submit.tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Audit Own News Updated"].firstMatch.waitForExistence(timeout: 10))
        capture(app, "news-edit-saved-detail")
        app.buttons["navigation.back"].firstMatch.tap()
        let card = app.buttons["home.card.news-audit-own"].firstMatch
        reveal(card, app); XCTAssertTrue(card.label.contains("Updated")); card.tap()
        XCTAssertTrue(app.staticTexts["Audit Own News Updated"].firstMatch.waitForExistence(timeout: 8))
    }

    func testSavedScopeUpdatesAfterRemovingBookmarkAndReturning() {
        let app = launch(role: "member")
        open("audit-own", app)
        let save = app.buttons["detail.header.action.bookmark"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 8)); save.tap()
        XCTAssertTrue(app.buttons["detail.header.action.bookmark.fill"].waitForExistence(timeout: 5))
        app.buttons["navigation.back"].firstMatch.tap()
        let saved = app.buttons["home.filter.saved"].firstMatch
        reveal(saved, app, up: false); saved.tap()
        open("audit-own", app)
        app.buttons["detail.header.action.bookmark.fill"].tap()
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        app.buttons["navigation.back"].firstMatch.tap()
        XCTAssertTrue(app.buttons["home.card.news-audit-own"].waitForNonExistence(timeout: 5))
        capture(app, "news-saved-scope-after-unsave")
    }

    func testDetailAndDialogsAtGermanDarkAccessibilitySize() {
        let app = launch(role: "owner", language: "de", dark: true, large: true)
        open("audit-own", app)
        capture(app, "news-de-dark-AX-header")
        let comments = app.descendants(matching: .any).matching(identifier: "comments.input").firstMatch
        reveal(comments, app)
        XCTAssertTrue(comments.exists); comments.tap(); comments.typeText("Audit comment")
        capture(app, "news-de-dark-AX-keyboard")
        let done = app.buttons["comments.dismissKeyboard"]
        reveal(done, app); done.tap()
        let send = app.buttons["comments.send"]
        reveal(send, app); send.tap()
        let posted = app.staticTexts["Audit comment"].firstMatch
        reveal(posted, app)
        XCTAssertTrue(posted.waitForExistence(timeout: 8))
        capture(app, "news-de-dark-AX-posted")
        let more = app.buttons["detail.header.more-actions"].firstMatch
        reveal(more, app, up: false); more.tap()
        app.buttons["Löschen"].firstMatch.tap()
        let dialog = app.alerts.firstMatch
        XCTAssertTrue(dialog.waitForExistence(timeout: 5)); capture(app, "news-de-dark-AX-delete-dialog")
        dialog.buttons["Abbrechen"].firstMatch.tap()
        XCTAssertTrue(dialog.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["navigation.back"].exists)
    }


    func testEditCancelKeepsChangesUntilExplicitDiscard() {
        let app = launch(role: "owner")
        open("audit-own", app)
        app.buttons["detail.header.more-actions"].tap(); app.buttons["Редагувати"].tap()
        let title = app.textFields["editor.news.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 8)); title.tap(); title.typeText(" Unsaved")
        dismissKeyboard(app)
        app.buttons["Скасувати"].firstMatch.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5)); capture(app, "news-edit-unsaved-confirmation")
        app.alerts.buttons["Продовжити редагування"].firstMatch.tap()
        XCTAssertTrue((title.value as? String)?.contains("Unsaved") == true)
        app.buttons["Скасувати"].firstMatch.tap()
        app.alerts.buttons["Відхилити зміни"].firstMatch.tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Audit Own News"].firstMatch.exists)
    }

    func testGuestCanReadButSaveAndCommentsRequireAccount() {
        let app = launch(role: "guest", language: "de")
        open("audit-own", app)
        app.buttons["detail.header.action.bookmark"].firstMatch.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5)); capture(app, "news-guest-save-gate")
        app.alerts.buttons.element(boundBy: app.alerts.buttons.count - 1).tap()
        let signIn = app.buttons["comments.signIn"]
        reveal(signIn, app); XCTAssertFalse(app.textFields["comments.input"].exists)
        signIn.tap(); XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        capture(app, "news-guest-comment-gate")
    }

    func testFeedLoadingFailureRetryAndEmptyState() {
        for state in ["retry", "empty"] {
            let app = XCUIApplication()
            app.launchArguments = ["-ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
            app.launchEnvironment = ["UITestForceGuestSession": "1", "UITestNewsAudit": "1", "UITestNewsPageState": state,
                "UITestResetUserSettings": "1", "UITestAppLanguage": "uk", "UITestAppAppearance": "dark"]
            app.launch()
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
            if state == "retry" {
                XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "home.news.loading").firstMatch.waitForExistence(timeout: 3))
                XCTAssertFalse(app.staticTexts["home.news.empty"].exists); capture(app, "news-loading-without-false-empty")
                let retry = app.buttons["Спробувати ще раз"].firstMatch
                XCTAssertTrue(retry.waitForExistence(timeout: 8)); capture(app, "news-load-error")
                retry.tap(); XCTAssertTrue(app.buttons["home.card.news-audit-own"].firstMatch.waitForExistence(timeout: 8))
                capture(app, "news-after-retry")
            } else {
                XCTAssertTrue(app.staticTexts["home.news.empty"].waitForExistence(timeout: 8))
                XCTAssertFalse(app.buttons["home.card.news-audit-own"].exists); capture(app, "news-confirmed-empty")
            }
            app.terminate()
        }
    }

    func testOwnerChangesRegionAndReadsItBack() {
        let app = launch(role: "owner")
        open("audit-own", app)
        app.buttons["detail.header.more-actions"].tap(); app.buttons["Редагувати"].tap()
        let next = app.buttons["editor.news.next"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 8)); reveal(next, app); next.tap(); reveal(next, app); next.tap()
        let region = app.buttons["editor.news.region"].firstMatch
        reveal(region, app); region.tap(); app.buttons["Відень"].firstMatch.tap()
        XCTAssertTrue(region.label.contains("Відень")); capture(app, "news-edit-selected-region")
        let submit = app.buttons["editor.news.submit"].firstMatch
        reveal(submit, app); submit.tap(); XCTAssertTrue(submit.waitForNonExistence(timeout: 10))
        app.buttons["detail.header.more-actions"].tap(); app.buttons["Редагувати"].tap()
        XCTAssertTrue(next.waitForExistence(timeout: 8)); reveal(next, app); next.tap(); reveal(next, app); next.tap()
        reveal(region, app); XCTAssertTrue(region.label.contains("Відень"))
        XCTAssertTrue(app.textFields.matching(NSPredicate(format: "value == %@", "https://example.org/details")).firstMatch.exists)
        capture(app, "news-edit-region-read-back")
    }

    func testOwnerDeletesCommentAndNewsWithExplicitConfirmation() {
        let app = launch(role: "owner")
        open("audit-own", app)
        let menu = app.buttons["news.comment.actions.comment-1"].firstMatch
        reveal(menu, app); menu.tap(); app.buttons["Видалити"].firstMatch.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5)); capture(app, "news-delete-comment-confirmation")
        app.alerts.buttons["Видалити"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["comments.row.comment-1"].waitForNonExistence(timeout: 8))
        app.buttons["navigation.back"].firstMatch.tap(); open("audit-own", app)
        let remaining = app.staticTexts["comments.row.comment-2"]
        reveal(remaining, app); XCTAssertFalse(app.staticTexts["comments.row.comment-1"].exists)
        let more = app.buttons["detail.header.more-actions"].firstMatch
        reveal(more, app, up: false); more.tap(); app.buttons["Видалити"].firstMatch.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5)); capture(app, "news-delete-news-confirmation")
        app.alerts.buttons["Видалити"].firstMatch.tap()
        XCTAssertTrue(app.buttons["home.filter.topic"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["home.card.news-audit-own"].exists)
        XCTAssertTrue(app.buttons["home.card.news-audit-foreign"].exists)
    }

    func testReportTargetsOpenedNewsAndCancelReturnsToIt() {
        let app = launch(role: "member", language: "de")
        open("audit-own", app)
        app.buttons["detail.header.more-actions"].tap(); app.buttons["Melden"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Inhalt melden"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Audit Own News"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Warum melden Sie diesen Inhalt?"].firstMatch.exists)
        XCTAssertFalse(app.buttons["Meldung senden"].isEnabled)
        capture(app, "news-report-target-and-validation")
        app.buttons["Abbrechen"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Inhalt melden"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["navigation.back"].exists)
    }

    func testBlockedAccountCanReadButCannotMutateNews() {
        let app = launch(role: "blocked")
        open("audit-own", app)
        let save = app.buttons["detail.header.action.bookmark"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 8)); XCTAssertFalse(save.isEnabled)
        XCTAssertTrue(app.buttons["detail.header.share"].isEnabled)
        XCTAssertFalse(app.buttons["detail.header.more-actions"].exists)
        let like = app.buttons["news.like.audit-own"]
        reveal(like, app); XCTAssertFalse(like.isEnabled)
        let comments = app.descendants(matching: .any).matching(identifier: "comments.section").firstMatch
        reveal(comments, app); XCTAssertFalse(app.textFields["comments.input"].exists)
        capture(app, "news-blocked-account-read-only")
    }

    private func launch(role: String, language: String = "uk", dark: Bool = false, large: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launchEnvironment = ["UITestResetUserSettings": "1", "UITestResetAppLock": "1", "UITestResetContentDrafts": "1",
            "UITestAppLanguage": language, "UITestAppAppearance": dark ? "dark" : "light", "UITestNewsAudit": "1"]
        if role == "owner" { app.launchEnvironment["UITestForceOwnerSession"] = "1" }
        else if role == "guest" { app.launchEnvironment["UITestForceGuestSession"] = "1" }
        else { app.launchEnvironment["UITestProfileRole"] = role }
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        return app
    }

    private func open(_ id: String, _ app: XCUIApplication) {
        let card = app.buttons["home.card.news-" + id].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10)); reveal(card, app); card.tap()
        XCTAssertTrue(app.buttons["navigation.back"].waitForExistence(timeout: 8))
    }

    private func reveal(_ element: XCUIElement, _ app: XCUIApplication, up: Bool = true, fullyVisible: Bool = false) {
        for _ in 0..<18 {
            let fits = !fullyVisible || (element.frame.minY > 70 && element.frame.maxY < app.frame.height - 70)
            if element.exists && element.isHittable && fits { return }
            let towardTop = element.exists ? element.frame.minY < 70 : !up
            app.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: towardTop ? 0.35 : 0.65))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: towardTop ? 0.65 : 0.35)))
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }

    private func alignTop(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<32 {
            if element.frame.minY >= 70 && element.frame.minY <= 260 { return }
            let towardTop = element.frame.minY < 70
            app.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: towardTop ? 0.4 : 0.55))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: towardTop ? 0.55 : 0.4)))
        }
        XCTFail("Cannot align top of " + element.identifier)
    }

    private func dismissKeyboard(_ app: XCUIApplication) {
        if app.keyboards.firstMatch.exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.12)).tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        }
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let item = XCTAttachment(screenshot: app.screenshot()); item.name = name; item.lifetime = .keepAlways; add(item)
    }
}
