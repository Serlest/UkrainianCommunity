import XCTest

@MainActor
final class ModerationAuditUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testInitialFailureRetryAndEmptyStateDoNotContradictEachOther() {
        let app = launch(flags: ["UITestModerationFailure": "1", "UITestModerationPreviewFailure": "1"])
        openQueue(app)
        let retry = app.buttons["content.moderation.retry"].firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        XCTAssertFalse(element("content.moderation.empty", app).exists)
        capture(app, "moderation-first-load-error-without-false-empty")
        retry.tap()
        XCTAssertTrue(app.buttons["content.moderation.open.moderation-news-0"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(retry.exists)
        capture(app, "moderation-retry-loaded-queue")
        app.buttons["content.moderation.open.moderation-news-0"].firstMatch.tap()
        let previewRetry = app.buttons["content.review.retry"].firstMatch
        XCTAssertTrue(previewRetry.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["content.review.confirm"].exists)
        capture(app, "moderation-preview-error-without-decision-actions")
        previewRetry.tap()
        XCTAssertTrue(element("content.review.language", app).waitForExistence(timeout: 8))
        capture(app, "moderation-preview-retry-restored-material")
        app.terminate()
        let empty = launch(flags: ["UITestModerationEmpty": "1"])
        openQueue(empty)
        XCTAssertTrue(element("content.moderation.empty", empty).waitForExistence(timeout: 10))
        XCTAssertFalse(empty.buttons["content.moderation.retry"].exists)
        capture(empty, "moderation-real-empty")
    }

    func testEventFullPreviewImageRetryDecisionCancelAndHistoryAtMaximumText() {
        let app = launch(language: "de", maximumText: true, flags: ["UITestModerationRich": "1"])
        openQueue(app)
        select("content.moderation.type", index: 1, prefix: "Ereignis:", app)
        let event = app.buttons["content.moderation.open.moderation-event-0"].firstMatch
        reveal(event, app); event.tap()
        XCTAssertTrue(element("content.review.language", app).waitForExistence(timeout: 10))
        capture(app, "moderation-event-de-dark-maximum-header")
        let imageRetry = app.buttons["remoteImage.retry"].firstMatch
        reveal(imageRetry, app); imageRetry.tap()
        XCTAssertTrue(imageRetry.waitForExistence(timeout: 10))
        capture(app, "moderation-event-image-error-and-retry")
        let contact = app.staticTexts["fixture@example.org"].firstMatch
        reveal(contact, app); capture(app, "moderation-event-complete-contacts-and-fields")
        let credit = app.staticTexts["Fixture author"].firstMatch
        reveal(credit, app); capture(app, "moderation-event-dates-and-image-metadata")
        let revise = app.buttons["content.review.choice.needsRevision"].firstMatch
        reveal(revise, app); revise.tap()
        XCTAssertTrue(revise.isSelected)
        let confirm = app.buttons["content.review.confirm"].firstMatch
        XCTAssertFalse(confirm.isEnabled)
        let reason = app.textFields["content.review.reason"].firstMatch
        reveal(reason, app); reason.tap(); reason.typeText("Bitte die Teilnahmebedingungen und den zweiten Termin prüfen.")
        dismissKeyboard(app)
        reveal(confirm, app); XCTAssertTrue(confirm.isEnabled); confirm.tap()
        let cancel = app.buttons["content.review.cancelDecision"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        capture(app, "moderation-event-confirmation-full-title-reason-maximum")
        cancel.tap()
        XCTAssertTrue((reason.value as? String ?? "").contains("Teilnahmebedingungen"))
        reveal(confirm, app); confirm.tap()
        let execute = app.buttons["content.review.execute"].firstMatch
        reveal(execute, app); capture(app, "moderation-accessible-confirmation-complete-reason-and-execute"); execute.tap()
        XCTAssertTrue(event.waitForNonExistence(timeout: 10))
        select("content.moderation.mode", index: 1, prefix: "Entscheidungsverlauf", app)
        let history = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "content.moderation.history.open.")).firstMatch
        reveal(history, app); capture(app, "moderation-history-event-de-maximum"); history.tap()
        XCTAssertTrue(app.staticTexts["Bitte die Teilnahmebedingungen und den zweiten Termin prüfen."].firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["content.review.confirm"].exists)
        capture(app, "moderation-history-current-material-readonly")
    }

    func testReadOnlyPreviewKeepsLoadedPagesAndSearchOnReturn() {
        let app = launch()
        openQueue(app)
        let search = app.textFields["content.moderation.search"].firstMatch
        reveal(search, app); search.tap(); search.typeText("36\n")
        let more = app.buttons["content.moderation.more"].firstMatch
        reveal(more, app); more.tap()
        let row = app.buttons["content.moderation.open.moderation-news-36"].firstMatch
        reveal(row, app); row.tap()
        let close = app.buttons["content.review.close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 8)); close.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        XCTAssertFalse(more.exists)
        XCTAssertTrue((search.value as? String ?? "").contains("36"))
        capture(app, "moderation-preview-return-preserves-page-and-search")
    }

    func testDeletedMaterialExplainsUnavailabilityAndAllowsClosingWithoutDecision() {
        let app = launch(flags: ["UITestModerationMissingMaterial": "1"])
        openQueue(app)
        let row = app.buttons["content.moderation.open.moderation-news-0"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8)); row.tap()
        XCTAssertTrue(app.staticTexts["Матеріал видалено або він більше недоступний."].firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["content.review.confirm"].exists)
        XCTAssertFalse(app.buttons["content.review.edit"].exists)
        XCTAssertFalse(app.buttons["content.review.retry"].exists, "A deleted material has no useful retry action")
        capture(app, "moderation-deleted-material-explanation")
        app.buttons["content.review.close"].firstMatch.tap()
        XCTAssertTrue(row.waitForExistence(timeout: 8))
    }

    func testSlowLoadingAndTypeSwitchNeverPresentAnOldQueueAsNewOrFalseEmpty() {
        let app = launch(flags: ["UITestModerationSlow": "1"])
        openQueue(app)
        XCTAssertTrue(element("content.moderation.loading", app).waitForExistence(timeout: 2))
        XCTAssertFalse(element("content.moderation.empty", app).exists)
        capture(app, "moderation-slow-first-page-loading")
        XCTAssertTrue(app.buttons["content.moderation.open.moderation-news-0"].firstMatch.waitForExistence(timeout: 8))
        app.segmentedControls["content.moderation.type"].buttons.element(boundBy: 1).tap()
        XCTAssertTrue(element("content.moderation.loading", app).waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["content.moderation.open.moderation-news-0"].exists)
        XCTAssertFalse(element("content.moderation.empty", app).exists)
        capture(app, "moderation-slow-type-switch-loading-no-old-news")
        XCTAssertTrue(element("content.moderation.empty", app).waitForExistence(timeout: 8))
        capture(app, "moderation-events-empty-after-confirmed-response")
    }

    func testOnlyPlatformReviewersSeeModerationEntryAndBothRolesCanOpenIt() {
        for role in ["owner", "admin", "org-owner", "org-admin", "org-moderator", "member", "warned"] {
            let app = launch(role: role)
            let entry = app.buttons["profile.moderation"].firstMatch
            if ["owner", "admin"].contains(role) {
                reveal(entry, app); entry.tap()
                XCTAssertTrue(element("content.moderation.mode", app).waitForExistence(timeout: 10))
                XCTAssertTrue(app.buttons["content.moderation.open.moderation-news-0"].firstMatch.waitForExistence(timeout: 8))
            } else {
                XCTAssertTrue(app.buttons["profile.edit.open"].firstMatch.waitForExistence(timeout: 10))
                XCTAssertFalse(entry.exists)
            }
            capture(app, "moderation-role-" + role)
            app.terminate()
        }
    }

    private func launch(language: String = "uk", maximumText: Bool = false, role: String = "owner", flags: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-UIPreferredContentSizeCategoryName", maximumText ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launchEnvironment = ["UITestResetUserSettings": "1", "UITestResetAppLock": "1", "UITestAppLanguage": language,
                                 "UITestAppAppearance": maximumText ? "dark" : "light"]
        if role == "owner" { app.launchEnvironment["UITestForceOwnerSession"] = "1" }
        else { app.launchEnvironment["UITestProfileRole"] = role }
        app.launchEnvironment.merge(flags, uniquingKeysWith: { _, new in new })
        app.launch()
        let profile = app.tabBars.buttons.element(boundBy: 4)
        XCTAssertTrue(profile.waitForExistence(timeout: 20)); profile.tap()
        return app
    }
    private func openQueue(_ app: XCUIApplication) {
        let entry = app.buttons["profile.moderation"].firstMatch
        reveal(entry, app); entry.tap()
        XCTAssertTrue(element("content.moderation.mode", app).waitForExistence(timeout: 10))
    }
    private func select(_ id: String, index: Int, prefix: String, _ app: XCUIApplication) {
        let segmented = app.segmentedControls[id].firstMatch
        if segmented.exists { reveal(segmented, app); segmented.buttons.element(boundBy: index).tap(); return }
        let menu = element(id, app)
        reveal(menu, app); menu.tap()
        let option = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND identifier != %@", prefix, id)).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5)); option.tap()
    }
    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
    private func dismissKeyboard(_ app: XCUIApplication) {
        if app.keyboards.firstMatch.exists {
            app.coordinate(withNormalizedOffset: .init(dx: 0.95, dy: 0.12)).tap()
            if app.keyboards.firstMatch.exists { app.swipeDown() }
        }
    }
    private func reveal(_ target: XCUIElement, _ app: XCUIApplication) {
        _ = target.waitForExistence(timeout: 5)
        for _ in 0..<24 {
            let scroll = app.scrollViews.allElementsBoundByIndex.first(where: { $0.isHittable })
            let top = max(scroll?.frame.minY ?? 80, app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY : 80) + 12
            var bottom = min(scroll?.frame.maxY ?? app.frame.height, app.frame.height - 35)
            let footer = app.buttons["content.review.confirm"].firstMatch
            if footer.exists, footer.isHittable, (!target.exists || target.identifier != "content.review.confirm"),
               footer.frame.minY > app.frame.height * 0.6 { bottom = min(bottom, footer.frame.minY - 18) }
            let bar = app.tabBars.firstMatch
            if bar.exists && bar.isHittable { bottom = min(bottom, bar.frame.minY - 12) }
            if target.exists && target.isHittable && target.frame.midY > top && target.frame.midY < bottom { return }
            let upward = target.exists && target.frame.midY < top
            let upper = min(max((top + 35) / app.frame.height, 0.2), 0.55)
            let lower = max(min((bottom - 20) / app.frame.height, 0.8), upper + 0.15)
            app.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: upward ? upper : lower))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: upward ? lower : upper)))
        }
        XCTFail("Moderation control not visible in its scroll viewport: \(target)")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
