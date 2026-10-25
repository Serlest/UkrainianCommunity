import XCTest

@MainActor final class UserAdministrationAuditUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testActionFormsAndRoleWindowsAtMaximumText() {
        let app = launch(language: "de", maximum: true)
        openUser("audit-member", app)
        let warn = app.buttons["user.detail.accountAction.warningIssued"]
        reveal(warn, app); warn.tap()
        let confirm = app.buttons["user.action.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); XCTAssertFalse(confirm.isEnabled)
        let reason = app.textFields["user.action.reason"].firstMatch
        reveal(reason, app); reason.tap(); reason.typeText("Bitte prüfen Sie die gemeldete Veröffentlichung.")
        dismissKeyboard(app); reveal(confirm, app); XCTAssertTrue(confirm.isEnabled)
        capture(app, "user-warning-reason-de-dark-maximum")
        app.buttons["user.action.cancel"].tap()

        let suspend = app.buttons["user.detail.accountAction.suspended"]
        reveal(suspend, app); suspend.tap()
        let duration = app.buttons["user.action.duration"].firstMatch
        XCTAssertTrue(duration.waitForExistence(timeout: 5)); reveal(duration, app); duration.tap()
        let option = app.buttons["30 Tg."].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5)); option.tap()
        capture(app, "user-suspension-duration-de-dark-maximum")
        app.buttons["user.action.cancel"].tap()

    }

    func testPlatformAndRemovalFormsAtMaximumText() {
        let app = launch(language: "de", maximum: true)
        openUser("audit-member", app)
        for id in ["user.detail.platformRole.assignAppAdmin", "user.detail.organizationRole.remove.audit-org-0"] {
            let action = app.buttons[id].firstMatch
            reveal(action, app); action.tap()
            let confirm = app.buttons["user.action.confirm"].firstMatch
            XCTAssertTrue(confirm.waitForExistence(timeout: 5)); XCTAssertFalse(confirm.isEnabled)
            let reason = app.textFields["user.action.reason"].firstMatch
            reveal(reason, app); reason.tap(); reason.typeText("Geprüfte Änderung der Zugriffsrechte.")
            dismissKeyboard(app); reveal(confirm, app); XCTAssertTrue(confirm.isEnabled)
            capture(app, "user-reviewed-" + id + "-de-dark-maximum")
            app.buttons["user.action.cancel"].tap()
            XCTAssertTrue(confirm.waitForNonExistence(timeout: 5))
        }
    }

    func testOwnershipWindowAtMaximumText() {
        let app = launch(language: "de", maximum: true)
        openUser("audit-member", app)
        let assignment = app.descendants(matching: .any).matching(identifier: "user.detail.organizationAssignment").firstMatch
        reveal(assignment, app); assignment.tap()
        let picker = app.buttons["user.detail.rolePicker"].firstMatch
        reveal(picker, app); picker.tap()
        let owner = app.buttons["Inhaber"].firstMatch
        XCTAssertTrue(owner.waitForExistence(timeout: 5)); owner.tap()
        let roleReason = app.textFields["user.detail.roleReason"].firstMatch
        reveal(roleReason, app); roleReason.tap(); roleReason.typeText("Geprüfter Wechsel der zuständigen Person.")
        dismissKeyboard(app)
        let transfer = app.buttons["user.detail.assignRole"]
        reveal(transfer, app); XCTAssertTrue(transfer.isEnabled); transfer.tap()
        let transferConfirm = app.buttons["user.ownership.confirm"]
        reveal(transferConfirm, app); XCTAssertTrue(transferConfirm.isEnabled)
        capture(app, "user-ownership-confirmation-de-dark-maximum")
        app.buttons["user.ownership.cancel"].tap()
        XCTAssertTrue(roleReason.waitForExistence(timeout: 5))
        XCTAssertTrue((roleReason.value as? String ?? "").contains("Geprüfter Wechsel"))
        // All mutation confirmations are cancelled; actual writes use the fixed demo SDK suite.
    }

    func testHistoryPagesAndRetryKeepEarlierRecords() {
        let app = launch(language: "uk", mode: "history-page-error")
        openUser("audit-member", app)
        let more = app.buttons["user.audit.more"].firstMatch
        reveal(more, app); more.tap()
        let retry = app.buttons["user.audit.retry"].firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["user.audit.item.audit-0"].exists)
        capture(app, "user-audit-failed-next-page-retains-records")
        reveal(retry, app); retry.tap()
        XCTAssertTrue(app.descendants(matching: .any)["user.audit.item.audit-39"].waitForExistence(timeout: 8))
        reveal(more, app); more.tap()
        let last = app.descendants(matching: .any)["user.audit.item.audit-44"]
        reveal(last, app); capture(app, "user-audit-all-45-records")
        XCTAssertFalse(more.exists)
    }

    func testDeletedUserHasNoActionableCachedCard() {
        let app = launch(language: "uk", mode: "deleted")
        openUser("audit-member", app, waitForDetail: false)
        XCTAssertTrue(app.descendants(matching: .any)["user.detail.unavailable"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["user.detail.accountAction.warningIssued"].exists)
        XCTAssertFalse(app.buttons["user.detail.platformRole.assignAppAdmin"].exists)
        capture(app, "user-deleted-card-no-actions")
        app.buttons["navigation.back"].firstMatch.tap()
        XCTAssertTrue(app.textFields["userManagement.search"].firstMatch.waitForExistence(timeout: 5))
    }

    func testGuideAndAdminHierarchyAtMaximumText() {
        let app = launch(language: "de", maximum: true, role: "admin")
        let guide = app.buttons["userManagement.roleGuide"].firstMatch
        reveal(guide, app); guide.tap()
        for index in 0..<5 {
            let row = app.descendants(matching: .any)["user.guide.row.\(index)"].firstMatch
            reveal(row, app); capture(app, "user-guide-role-\(index)-de-dark-maximum")
        }
        app.buttons["user.guide.done"].tap()
        openUser("audit-member", app)
        let warning = app.buttons["user.detail.accountAction.warningIssued"].firstMatch
        reveal(warning, app); XCTAssertTrue(warning.isEnabled)
        XCTAssertFalse(app.buttons["user.detail.platformRole.assignAppAdmin"].exists)
        let assignment = app.buttons["user.detail.organizationAssignment"].firstMatch
        reveal(assignment, app); assignment.tap()
        let roles = app.buttons["user.detail.rolePicker"].firstMatch
        reveal(roles, app); roles.tap()
        XCTAssertFalse(app.buttons["Inhaber"].exists)
        XCTAssertTrue(app.buttons["Moderator"].exists)
        app.coordinate(withNormalizedOffset: .init(dx: 0.05, dy: 0.2)).tap()
        capture(app, "user-app-admin-hierarchy-de-dark-maximum")
    }

    private func launch(language: String, maximum: Bool = false, mode: String = "normal", role: String = "owner") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-UIPreferredContentSizeCategoryName", maximum ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
        app.launchEnvironment = ["UITestUserAdministrationAudit": "1", "UITestUserAdministrationState": mode,
            "UITestResetUserSettings": "1", "UITestResetAppLock": "1", "UITestAppLanguage": language,
            "UITestAppAppearance": maximum ? "dark" : "light"]
        if role == "owner" { app.launchEnvironment["UITestForceOwnerSession"] = "1" }
        else { app.launchEnvironment["UITestProfileRole"] = role }
        app.launch(); XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        app.tabBars.buttons.element(boundBy: 4).tap()
        let entry = app.buttons["profile.userManagement"].firstMatch
        reveal(entry, app); entry.tap()
        return app
    }
    private func openUser(_ id: String, _ app: XCUIApplication, waitForDetail: Bool = true) {
        let row = app.descendants(matching: .any).matching(identifier: "userManagement.user." + id).firstMatch
        reveal(row, app); row.tap()
        if waitForDetail {
            let loading = app.descendants(matching: .any)["user.detail.loading"].firstMatch
            XCTAssertTrue(loading.waitForNonExistence(timeout: 8))
            XCTAssertFalse(app.descendants(matching: .any)["user.detail.unavailable"].exists)
        }
    }
    private func dismissKeyboard(_ app: XCUIApplication) {
        if app.keyboards.firstMatch.exists {
            app.coordinate(withNormalizedOffset: .init(dx: 0.95, dy: 0.12)).tap()
            if app.keyboards.firstMatch.exists { app.swipeDown() }
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        }
    }
    private func reveal(_ target: XCUIElement, _ app: XCUIApplication) {
        _ = target.waitForExistence(timeout: 5)
        for _ in 0..<35 {
            let scroll = app.scrollViews.allElementsBoundByIndex.first(where: { $0.isHittable })
            let top = max(scroll?.frame.minY ?? 90, app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY : 90) + 15
            let bottom = min(scroll?.frame.maxY ?? app.frame.height, app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY - 12 : app.frame.height - 35)
            if target.exists && target.isHittable && target.frame.midY > top && target.frame.midY < bottom { return }
            let upward = target.exists && target.frame.midY < top
            let upper = min(max((top + 30) / app.frame.height, 0.2), 0.55)
            let lower = max(min((bottom - 25) / app.frame.height, 0.8), upper + 0.15)
            app.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: upward ? upper : lower))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: upward ? lower : upper)))
        }
        XCTFail("Unreachable user administration control: \(target)")
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
}
