import XCTest

/// Opt-in, physical-device production checks. Never create credentials or confirm role changes.
@MainActor
final class PhysicalClosureAuditUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        #if targetEnvironment(simulator)
        throw XCTSkip("Physical iPhone required")
        #else
        guard ProcessInfo.processInfo.environment["UACPhysicalClosureAudit"] == "1" else {
            throw XCTSkip("Explicit controlled-account audit required")
        }
        #endif
    }

    override func tearDown() {
        // XCTest's stop-on-first-failure can bypass a Swift defer. Restore
        // the physical device even when an orientation assertion fails.
        if name.contains("testP14") { XCUIDevice.shared.orientation = .portrait }
        super.tearDown()
    }

    func testUserManagementProductionReadOnlyWithRealSession() {
        let app = XCUIApplication(); openProfile(app)
        let owner = app.staticTexts["Serlest"].firstMatch
        reveal(owner, app, towardTop: true); XCTAssertTrue(owner.exists)
        let entry = app.buttons["profile.userManagement"].firstMatch
        reveal(entry, app); entry.tap()
        let search = app.textFields["userManagement.search"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "userManagement.user.")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 30)); captureForeground(app, "physical-users-confirmed-directory")
        search.tap(); search.typeText("Serlest")
        if app.keyboards.firstMatch.exists { app.coordinate(withNormalizedOffset: .init(dx: 0.96, dy: 0.12)).tap() }
        let exact = app.descendants(matching: .any).matching(identifier: "userManagement.user.4jk3piOYIWMNsBf5gUAaOMpaQc83").firstMatch
        XCTAssertTrue(exact.waitForExistence(timeout: 30)); reveal(exact, app)
        if let count = ProcessInfo.processInfo.environment["UACPhysicalExpectedOrganizationCount"] {
            XCTAssertTrue(exact.label.contains(count + " орг."), exact.label)
        }
        captureForeground(app, "physical-users-server-search"); exact.tap()
        let presence = app.descendants(matching: .any)["user.presence.section"].firstMatch
        XCTAssertTrue(presence.waitForExistence(timeout: 20))
        let presenceResult = app.descendants(matching: .any).matching(NSPredicate(format: "identifier IN %@",
            ["user.presence.online", "user.presence.lastSeen", "user.presence.unknown"])).firstMatch
        XCTAssertTrue(presenceResult.waitForExistence(timeout: 30), "Wait for actual presence response, not its container")
        captureForeground(app, "physical-users-presence-and-protected-self")
        XCTAssertFalse(app.buttons["user.detail.accountAction.banned"].exists)
        let security = app.staticTexts["Вхід і безпека"].firstMatch
        reveal(security, app); captureForeground(app, "physical-users-security")
        // Read only: no account/role confirmation is opened or executed.
    }

    func testModerationProductionQueueReadOnlyWithRealSession() {
        let app = XCUIApplication()
        openProfile(app)
        let owner = app.staticTexts["Serlest"].firstMatch
        reveal(owner, app, towardTop: true)
        XCTAssertTrue(owner.exists, "Use the controlled platform owner")
        let entry = app.buttons["profile.moderation"].firstMatch
        reveal(entry, app); entry.tap()
        let type = app.segmentedControls["content.moderation.type"].firstMatch
        XCTAssertTrue(type.waitForExistence(timeout: 15))
        for index in 0...1 {
            type.buttons.element(boundBy: index).tap()
            let loading = app.descendants(matching: .any).matching(identifier: "content.moderation.loading").firstMatch
            XCTAssertTrue(loading.waitForNonExistence(timeout: 30))
            XCTAssertFalse(app.buttons["content.moderation.retry"].exists)
            XCTAssertFalse(type.buttons.element(boundBy: index).label.contains("—"), "A real server count is required")
            let empty = app.descendants(matching: .any).matching(identifier: "content.moderation.empty").firstMatch
            let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "content.moderation.open.")).firstMatch
            XCTAssertTrue(empty.exists || row.exists, "A confirmed loaded result is required")
            capture(app, "physical-production-moderation-type-" + String(index))
        }
        app.segmentedControls["content.moderation.mode"].buttons.element(boundBy: 1).tap()
        let loading = app.descendants(matching: .any).matching(identifier: "content.moderation.loading").firstMatch
        XCTAssertTrue(loading.waitForNonExistence(timeout: 30))
        XCTAssertFalse(app.buttons["content.moderation.retry"].exists)
        let empty = app.staticTexts["Рішень щодо матеріалів поки немає."].firstMatch
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "content.moderation.history.open.")).firstMatch
        XCTAssertTrue(empty.exists || row.exists)
        capture(app, "physical-production-moderation-history")
        // Read only: no material/decision button is ever selected.
    }

    func testControlledOwnershipConfirmationCancelRetainsServerOwner() async throws {
        let before = try await authority()
        let app = XCUIApplication()
        openProfile(app)
        let management = app.buttons["profile.organizationManagement"].firstMatch
        reveal(management, app, towardTop: true); management.tap()
        let search = app.textFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText("UAC Tirol Info")
        let manage = app.buttons["organization.manage.uac-tirol-info"].firstMatch
        XCTAssertTrue(manage.waitForExistence(timeout: 15)); reveal(manage, app); manage.tap()
        let change = app.buttons["Змінити власника"].firstMatch
        reveal(change, app); change.tap()
        let candidate = app.buttons.containing(.staticText, identifier: "Serlest Gmail").firstMatch
        XCTAssertTrue(candidate.waitForExistence(timeout: 15))
        reveal(candidate, app); capture(app, "physical-owner-candidate"); candidate.tap()
        let confirm = app.buttons["organization.team.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        capture(app, "physical-owner-exact-confirmation")
        // Deliberately never tap the confirmation. Popovers may omit the cancel row.
        let cancel = app.buttons["Скасувати"].firstMatch
        if cancel.exists && cancel.isHittable { cancel.tap() }
        else { app.coordinate(withNormalizedOffset: .init(dx: 0.2, dy: 0.12)).tap() }
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 8))
        capture(app, "physical-owner-cancelled")
        let after = try await authority()
        XCTAssertEqual(before, after, "Cancelling must not change any organization authority field")
    }

    func testGoogleCancellationThenPrepareControlledSignIn() {
        let app = XCUIApplication()
        openProfile(app)
        let logout = app.buttons["profile.logout.button"].firstMatch
        reveal(logout, app); logout.tap()
        let confirm = app.alerts.buttons["profile.logout.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        let google = app.buttons["auth.provider.google"].firstMatch
        XCTAssertTrue(google.waitForExistence(timeout: 20)); google.tap()
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = app.alerts.firstMatch.waitForExistence(timeout: 5) ? app.alerts.firstMatch : system.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "accounts.google.com")).firstMatch.exists)
        capture(app, "physical-google-native-consent")
        alert.buttons["Abbrechen"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 10))
        XCTAssertTrue(google.isEnabled)
        XCTAssertTrue(app.buttons["auth.provider.apple"].firstMatch.isEnabled)
        capture(app, "physical-google-cancel-restored")
        google.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        alert.buttons["Fortfahren"].tap()
        capture(app, "physical-google-ready-for-user-account")
        // The user completes account selection/credentials directly on the phone.
    }

    func testPrepareControlledTestRequestWithoutAcceptingLegalTermsOrSubmitting() {
        let app = XCUIApplication()
        openProfile(app)
        let name = app.staticTexts["Serlest Gmail"].firstMatch
        reveal(name, app, towardTop: true)
        XCTAssertTrue(name.exists, "Use only the second account explicitly identified by the user")
        let management = app.buttons["profile.organizationManagement"].firstMatch
        reveal(management, app); management.tap()
        let create = app.buttons["organization.management.create"].firstMatch
        reveal(create, app, towardTop: true); create.tap()
        let title = app.textFields["organization.editor.name"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        let existingTitle = title.value as? String ?? ""
        XCTAssertTrue(existingTitle.isEmpty || existingTitle == title.placeholderValue,
                      "Never overwrite an existing user draft")
        title.tap(); title.typeText("UAC — тест перевірки заявки")
        let details = app.descendants(matching: .any).matching(identifier: "organization.editor.description").firstMatch
        reveal(details, app); details.tap()
        details.typeText("Контрольована тестова заявка для перевірки доопрацювання та сповіщень. Не публікувати. Після перевірки заявник її відкличе.")
        dismissKeyboard(app)
        next(app)
        let region = app.buttons["organization.editor.region"].firstMatch
        reveal(region, app); region.tap(); app.buttons["Тіроль"].firstMatch.tap()
        let city = app.textFields["organization.editor.city"].firstMatch
        reveal(city, app); city.tap(); city.typeText("Innsbruck"); dismissKeyboard(app)
        next(app); next(app)
        let read = app.buttons["organizationEditor.rules.read"].firstMatch
        reveal(read, app); read.tap()
        XCTAssertTrue(app.buttons["organizationEditor.rules.close"].firstMatch.waitForExistence(timeout: 10))
        capture(app, "physical-test-request-legal-review-user-handoff")
        // Legal acceptance and final submission are deliberately left to the user.
    }

    func testSubmitOnlyUserConfirmedPreparedTestRequest() throws {
        guard ProcessInfo.processInfo.environment["UACPhysicalLegalSubmissionConfirmed"] == "2026-10-25" else {
            throw XCTSkip("Action-time user confirmation required for the prepared application")
        }
        let app = XCUIApplication()
        app.activate()
        XCTAssertTrue(app.staticTexts["UAC — тест перевірки заявки"].firstMatch.waitForExistence(timeout: 10))
        let acceptance = app.switches["organizationEditor.rules.confirm"].firstMatch
        XCTAssertTrue(acceptance.exists)
        XCTAssertEqual(acceptance.value as? String, "1", "The user must personally accept the rules")
        let submit = app.buttons["organizationEditor.submit"].firstMatch
        XCTAssertTrue(submit.exists); XCTAssertTrue(submit.isEnabled)
        XCTAssertEqual(submit.label, "Подати заявку", "Never use the platform-owner Publish action")
        capture(app, "physical-request-user-confirmed-before-submit")
        submit.tap()
        XCTAssertTrue(submit.waitForNonExistence(timeout: 25))
        capture(app, "physical-request-submission-result")
    }

    func testReturnOnlyTheAuthorizedTestRequestForRevisionAndReadHistory() throws {
        let requestID = ProcessInfo.processInfo.environment["UACPhysicalAuditRequestID"] ?? ""
        guard !requestID.isEmpty else { throw XCTSkip("Exact controlled request ID required") }
        let app = XCUIApplication()
        openProfile(app)
        let owner = app.staticTexts["Serlest"].firstMatch
        reveal(owner, app, towardTop: true)
        XCTAssertTrue(owner.exists, "Use the authorized platform owner account")
        let noticeID = ProcessInfo.processInfo.environment["UACPhysicalAuditReviewerNoticeID"] ?? ""
        if !noticeID.isEmpty {
            let inbox = app.buttons["profile.notifications.open"].firstMatch
            reveal(inbox, app); inbox.tap()
            let notice = app.buttons.matching(NSPredicate(format: "identifier == %@", "notificationInbox.open." + noticeID)).firstMatch
            XCTAssertTrue(notice.waitForExistence(timeout: 15)); reveal(notice, app); notice.tap()
            let body = app.staticTexts["notificationDetail.body"].firstMatch
            XCTAssertTrue(body.waitForExistence(timeout: 10))
            XCTAssertTrue(body.label.contains("UAC — тест перевірки заявки"))
            capture(app, "physical-reviewer-exact-submission-notice")
            let destination = app.buttons["notificationDetail.openDestination"].firstMatch
            reveal(destination, app); destination.tap()
        } else {
            let requests = app.buttons["profile.organizationRequests"].firstMatch
            reveal(requests, app); requests.tap()
        }
        let open = app.buttons["organization.requests.open." + requestID].firstMatch
        let approve = app.buttons["organization.request.choice.approve"].firstMatch
        // A targeted notification opens the exact review sheet directly.
        if !approve.waitForExistence(timeout: 5) {
            XCTAssertTrue(open.waitForExistence(timeout: 20)); reveal(open, app); open.tap()
        }
        XCTAssertTrue(app.staticTexts["UAC — тест перевірки заявки"].firstMatch.waitForExistence(timeout: 10),
                      "Never review another organization's request")
        let confirm = app.buttons["organization.request.confirm"].firstMatch
        XCTAssertTrue(confirm.exists); XCTAssertFalse(confirm.isEnabled)
        reveal(approve, app); approve.tap()
        XCTAssertTrue(confirm.isEnabled)
        let reject = app.buttons["organization.request.choice.reject"].firstMatch
        reveal(reject, app); reject.tap()
        XCTAssertFalse(confirm.isEnabled, "A rejection requires a reason")
        let revision = app.buttons["organization.request.choice.requestRevision"].firstMatch
        reveal(revision, app); revision.tap()
        XCTAssertFalse(confirm.isEnabled, "A revision request requires a reason")
        let reasonText = "Тест перевірки: уточніть опис і надішліть заявку повторно. Це контрольована перевірка UAC; організацію не публікувати."
        let reason = app.textFields["organization.request.reason"].firstMatch
        XCTAssertTrue(reason.waitForExistence(timeout: 5))
        reveal(reason, app); reason.tap(); reason.typeText(reasonText); dismissKeyboard(app)
        XCTAssertTrue(confirm.isEnabled); capture(app, "physical-review-test-revision-reason")
        confirm.tap()
        let execute = app.buttons["organization.request.execute"].firstMatch
        XCTAssertTrue(execute.waitForExistence(timeout: 5))
        capture(app, "physical-review-test-revision-confirmation")
        execute.tap()
        XCTAssertTrue(revision.waitForNonExistence(timeout: 20))
        XCTAssertTrue(open.waitForNonExistence(timeout: 20))
        if !noticeID.isEmpty {
            openProfile(app)
            let requests = app.buttons["profile.organizationRequests"].firstMatch
            reveal(requests, app); requests.tap()
        }
        let history = app.segmentedControls["organization.requests.mode"].firstMatch
        XCTAssertTrue(history.exists); history.buttons.element(boundBy: 1).tap()
        let recordedReason = app.staticTexts[reasonText].firstMatch
        XCTAssertTrue(recordedReason.waitForExistence(timeout: 15)); reveal(recordedReason, app)
        capture(app, "physical-review-test-history")
        // The only submitted decision is requestRevision for the exact controlled ID.
    }

    func testApplicantRevisionNoticeEditorAndAuthorizedTestRequestCleanup() throws {
        let requestID = ProcessInfo.processInfo.environment["UACPhysicalAuditRequestID"] ?? ""
        let noticeID = ProcessInfo.processInfo.environment["UACPhysicalAuditApplicantNoticeID"] ?? ""
        guard !requestID.isEmpty && !noticeID.isEmpty else { throw XCTSkip("Exact disposable request and recipient notice required") }
        let app = XCUIApplication()
        openProfile(app)
        let account = app.staticTexts["Serlest Gmail"].firstMatch
        reveal(account, app, towardTop: true); XCTAssertTrue(account.exists)
        let inbox = app.buttons["profile.notifications.open"].firstMatch
        reveal(inbox, app); inbox.tap()
        let notice = app.buttons.matching(NSPredicate(format: "identifier == %@", "notificationInbox.open." + noticeID)).firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 15)); reveal(notice, app); notice.tap()
        let body = app.staticTexts["notificationDetail.body"].firstMatch
        XCTAssertTrue(body.waitForExistence(timeout: 10))
        XCTAssertTrue(body.label.contains("UAC — тест перевірки заявки"))
        XCTAssertTrue(body.label.contains("уточніть опис"))
        capture(app, "physical-applicant-exact-revision-notice")
        let destination = app.buttons["notificationDetail.openDestination"].firstMatch
        reveal(destination, app); destination.tap()
        let name = app.textFields["organization.editor.name"].firstMatch
        if !name.waitForExistence(timeout: 3) {
            let edit = app.buttons["organization.request.preview." + requestID].firstMatch
            XCTAssertTrue(edit.waitForExistence(timeout: 15)); reveal(edit, app); edit.tap()
        }
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        XCTAssertEqual(name.value as? String, "UAC — тест перевірки заявки")
        capture(app, "physical-applicant-exact-revision-editor")
        let close = app.buttons["editor.close"].firstMatch
        XCTAssertTrue(close.exists); close.tap()
        XCTAssertTrue(name.waitForNonExistence(timeout: 8))
        let removeID = "organization.request.delete." + requestID
        let remove = app.buttons[removeID].firstMatch
        reveal(remove, app); remove.tap()
        let confirm = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Видалити заявку", removeID)).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        capture(app, "physical-applicant-test-request-cleanup-confirmation")
        confirm.tap()
        XCTAssertTrue(remove.waitForNonExistence(timeout: 25))
        capture(app, "physical-applicant-test-request-removed")
    }

    func testExistingOwnerSecurityPagesWithoutCredentialChanges() {
        let app = XCUIApplication()
        openProfile(app)
        let owner = app.staticTexts["Serlest"].firstMatch
        reveal(owner, app, towardTop: true); XCTAssertTrue(owner.exists)
        let settings = app.buttons["profile.settings.open"].firstMatch
        reveal(settings, app); settings.tap()
        let lock = app.switches["profile.settings.appLock"].firstMatch
        reveal(lock, app)
        let originalLockValue = lock.value as? String
        XCTAssertTrue(originalLockValue == "0" || originalLockValue == "1")
        capture(app, "physical-owner-app-lock-existing-setting")
        let security = app.buttons["profile.settings.accountSecurity"].firstMatch
        reveal(security, app, towardTop: true); security.tap()
        let passkey = app.buttons["accountSecurity.passkey.add"].firstMatch
        XCTAssertTrue(passkey.waitForExistence(timeout: 15)); reveal(passkey, app)
        // Adding a credential may remain disabled by the MFA policy even after
        // the read succeeds. Assert the successful read state itself.
        let keysLoaded = app.descendants(matching: .any)["accountSecurity.passkeys.loaded"].firstMatch
        XCTAssertTrue(keysLoaded.waitForExistence(timeout: 20),
                      "Capture the resolved key list, not its initial loading frame")
        XCTAssertFalse(app.buttons["accountSecurity.passkey.retry"].firstMatch.exists)
        capture(app, "physical-owner-existing-passkeys")
        let providers = app.descendants(matching: .any).matching(identifier: "accountSecurity.linkedMethods").firstMatch
        reveal(providers, app); capture(app, "physical-owner-existing-signin-methods")
        let linking = app.buttons["Додати спосіб входу"].firstMatch
        if linking.exists {
            reveal(linking, app); linking.tap(); capture(app, "physical-owner-linking-options-without-linking")
        }
        let manage = app.buttons["Керувати автентифікатором"].firstMatch
        reveal(manage, app); manage.tap()
        let protectedFactor = app.staticTexts["Останній автентифікатор не можна видалити, доки для цього акаунта обов’язковий двофакторний захист."].firstMatch
        XCTAssertTrue(protectedFactor.waitForExistence(timeout: 15)); reveal(protectedFactor, app)
        capture(app, "physical-owner-required-authenticator")
        XCTAssertFalse(app.buttons["accountSecurity.retry"].firstMatch.exists)
        XCTAssertFalse(app.buttons["accountSecurity.mfa.retry"].firstMatch.exists)
        if originalLockValue == "0" {
            XCUIDevice.shared.press(.home)
            app.activate()
            XCTAssertTrue(protectedFactor.waitForExistence(timeout: 15))
            capture(app, "physical-owner-security-after-background-with-lock-disabled")
        }
        // No provider, key, password, factor, app-lock or grace-period mutation.
    }

    func testExistingPasskeyNativeCancellationAndRepeatWithoutCredentialChanges() {
        let app = XCUIApplication()
        openProfile(app)
        let owner = app.staticTexts["Serlest"].firstMatch
        reveal(owner, app, towardTop: true); XCTAssertTrue(owner.exists)
        let logout = app.buttons["profile.logout.button"].firstMatch
        reveal(logout, app); logout.tap()
        let confirm = app.alerts.buttons["profile.logout.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        let passkey = app.buttons["auth.passkey.signIn"].firstMatch
        XCTAssertTrue(passkey.waitForExistence(timeout: 20))
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for attempt in 1...2 {
            passkey.tap()
            let predicate = NSPredicate(format: "label IN %@", ["Abbrechen", "Cancel", "Скасувати", "Schließen", "Close"])
            let inApp = app.buttons.matching(predicate).firstMatch
            let cancel = inApp.waitForExistence(timeout: 10) ? inApp : system.buttons.matching(predicate).firstMatch
            XCTAssertTrue(cancel.waitForExistence(timeout: 5))
            capture(app, "physical-passkey-native-cancel-\(attempt)")
            cancel.tap()
            XCTAssertTrue(cancel.waitForNonExistence(timeout: 10))
            XCTAssertTrue(passkey.isEnabled)
            XCTAssertTrue(app.buttons["auth.provider.apple"].firstMatch.isEnabled)
            XCTAssertTrue(app.buttons["auth.provider.google"].firstMatch.isEnabled)
            capture(app, "physical-passkey-cancel-restored-\(attempt)")
        }
    }

    func testCancelActualOwnerMFAChallengeRestoresAllSignInMethods() {
        let app = XCUIApplication()
        app.activate()
        let code = app.textFields["auth.mfa.code"].firstMatch
        XCTAssertTrue(code.waitForExistence(timeout: 10))
        let submit = app.buttons["auth.mfa.submit"].firstMatch
        XCTAssertFalse(submit.isEnabled)
        capture(app, "physical-owner-mfa-before-cancel")
        let cancel = app.buttons["auth.mfa.cancel"].firstMatch
        XCTAssertTrue(cancel.isEnabled); cancel.tap()
        XCTAssertTrue(code.waitForNonExistence(timeout: 10))
        for id in ["auth.provider.apple", "auth.provider.google", "auth.passkey.signIn"] {
            let method = app.buttons[id].firstMatch
            XCTAssertTrue(method.waitForExistence(timeout: 10)); XCTAssertTrue(method.isEnabled)
        }
        capture(app, "physical-owner-mfa-cancel-restored")
    }

    func testPrepareOwnerBiometricSettingsWithoutChangingThem() {
        let app = XCUIApplication()
        openProfile(app)
        let owner = app.staticTexts["Serlest"].firstMatch
        reveal(owner, app, towardTop: true); XCTAssertTrue(owner.exists)
        let settings = app.buttons["profile.settings.open"].firstMatch
        reveal(settings, app); settings.tap()
        let lock = app.switches["profile.settings.appLock"].firstMatch
        reveal(lock, app)
        XCTAssertEqual(lock.value as? String, "0", "Keep the original setting until the user's device confirmation")
        capture(app, "physical-owner-biometric-settings-user-handoff")
    }

    func testEnabledAppLockHidesProtectedUIAfterBackground() {
        let app = XCUIApplication()
        app.activate()
        let unlock = app.buttons["appLock.unlock"].firstMatch
        if !unlock.waitForExistence(timeout: 3) {
            let setting = app.switches["profile.settings.appLock"].firstMatch
            XCTAssertTrue(setting.waitForExistence(timeout: 10))
            XCTAssertEqual(setting.value as? String, "1")
            capture(app, "physical-biometric-enabled-before-background")
            XCUIDevice.shared.press(.home)
            app.activate()
        }
        // Starting the XCTest runner itself can already background the protected app.
        XCTAssertTrue(unlock.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["profile.settings.accountSecurity"].firstMatch.isHittable)
        XCTAssertFalse(app.tabBars.buttons["tab.profile"].firstMatch.isHittable)
        capture(app, "physical-biometric-protected-content-hidden")
        // Leave real authentication to the human on the physical device.
    }

    func testPasskeyRemovalConfirmationCanOpenAndCancelWithoutDeleting() {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        openSecondaryPasskeySettings(app)
        let remove = app.buttons["Видалити ключ доступу"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 15)); reveal(remove, app)
        remove.tap()
        let dialog = app.alerts.firstMatch
        let appeared = dialog.waitForExistence(timeout: 5)
        capture(app, "physical-passkey-removal-confirmation-open-or-failure")
        XCTAssertTrue(appeared, "Trash button must present a confirmation before any server mutation")
        let cancel = dialog.buttons["Скасувати"].firstMatch
        XCTAssertTrue(cancel.isHittable); cancel.tap()
        XCTAssertTrue(dialog.waitForNonExistence(timeout: 5))
        XCTAssertTrue(remove.exists)
        capture(app, "physical-passkey-removal-cancel-retains-key")
        // Never confirm credential removal from automation.
    }

    func testPrepareSecondaryPasskeySettingsWithoutCredentialChanges() {
        let app = XCUIApplication()
        openSecondaryPasskeySettings(app)
        capture(app, "physical-secondary-resolved-passkey-settings-before-user-action")
        // Credential creation/removal are user handoffs, never performed by this test.
    }

    private func openSecondaryPasskeySettings(_ app: XCUIApplication) {
        openProfile(app)
        let member = app.staticTexts["Serlest Gmail"].firstMatch
        reveal(member, app, towardTop: true); XCTAssertTrue(member.exists)
        let settings = app.buttons["profile.settings.open"].firstMatch
        reveal(settings, app); settings.tap()
        let security = app.buttons["profile.settings.accountSecurity"].firstMatch
        reveal(security, app, towardTop: true); security.tap()
        let add = app.buttons["accountSecurity.passkey.add"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 15)); reveal(add, app)
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: add)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 20), .completed)
    }

    func testPrepareOwnerSignInForRecoveryHelp() {
        let app = XCUIApplication()
        openProfile(app)
        let owner = app.staticTexts["Serlest"].firstMatch
        reveal(owner, app, towardTop: true); XCTAssertTrue(owner.exists)
        let logout = app.buttons["profile.logout.button"].firstMatch
        reveal(logout, app); logout.tap()
        let confirm = app.alerts.buttons["profile.logout.confirm"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(app.buttons["auth.provider.apple"].firstMatch.waitForExistence(timeout: 20))
        capture(app, "physical-recovery-check-ready-for-apple-signin")
    }

    func testActualMFARecoveryHelpPreservesPendingChallenge() {
        let app = XCUIApplication()
        app.activate()
        let code = app.textFields["auth.mfa.code"].firstMatch
        XCTAssertTrue(code.waitForExistence(timeout: 10))
        let empty = (code.value as? String ?? "").isEmpty || code.value as? String == code.placeholderValue
        XCTAssertTrue(empty, "Leave the code empty for this presentation check")
        let help = app.buttons["auth.mfa.recovery.open"].firstMatch
        reveal(help, app); help.tap()
        let contact = app.descendants(matching: .any).matching(identifier: "auth.mfa.recovery.email").firstMatch
        XCTAssertTrue(contact.waitForExistence(timeout: 10)); reveal(contact, app)
        XCTAssertTrue(app.staticTexts["ukrainian.community@outlook.com"].firstMatch.exists)
        capture(app, "physical-mfa-recovery-help-and-contact")
        let close = app.buttons["auth.mfa.recovery.close"].firstMatch
        XCTAssertTrue(close.isHittable); close.tap()
        XCTAssertTrue(code.waitForExistence(timeout: 10))
        let stillEmpty = (code.value as? String ?? "").isEmpty || code.value as? String == code.placeholderValue
        XCTAssertTrue(stillEmpty)
        XCTAssertFalse(app.buttons["auth.mfa.submit"].firstMatch.isEnabled)
        capture(app, "physical-mfa-recovery-return-preserves-challenge")
    }

    private func openProfile(_ app: XCUIApplication) {
        app.activate()
        let passkeyLater = app.buttons["auth.passkeySuggestion.later"].firstMatch
        if passkeyLater.waitForExistence(timeout: 3) {
            reveal(passkeyLater, app); capture(app, "physical-passkey-offer-deferred"); passkeyLater.tap()
        }
        let candidateCancel = app.buttons["organization.team.cancelSearch"].firstMatch
        if candidateCancel.exists && candidateCancel.isHittable { candidateCancel.tap() }
        if app.buttons["organization.request.choice.approve"].firstMatch.exists {
            let reviewCancel = app.buttons["Скасувати"].firstMatch
            if reviewCancel.exists && reviewCancel.isHittable { reviewCancel.tap() }
        }
        returnFromPushedScreens(app)
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        let taggedProfile = app.tabBars.buttons["tab.profile"].firstMatch
        let nativeProfile = app.tabBars.buttons.matching(NSPredicate(format: "label IN %@", ["Профіль", "Profil", "Profile"])).firstMatch
        let profile = taggedProfile.exists ? taggedProfile : nativeProfile
        XCTAssertTrue(profile.waitForExistence(timeout: 20), "Return from a tab-bar-hidden screen before selecting Profile")
        if profile.isHittable { profile.tap() }
        else {
            // Native tab AX hit testing can lag an on-device text-size change.
            // Only use the actual visible tab's bounds and verify selection.
            let frame = profile.frame.intersection(app.windows.firstMatch.frame)
            XCTAssertGreaterThan(frame.width, 20)
            XCTAssertGreaterThan(frame.height, 20)
            let diagnostic = XCTAttachment(string: profile.debugDescription)
            diagnostic.name = "physical-native-profile-tab-hit-test"; diagnostic.lifetime = .keepAlways; add(diagnostic)
            profile.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: profile)], timeout: 10), .completed)
        returnFromPushedScreens(app)
    }

    private func returnFromPushedScreens(_ app: XCUIApplication) {
        for _ in 0..<8 {
            let identified = app.buttons["navigation.back"].firstMatch
            if identified.exists {
                if !identified.isHittable { reveal(identified, app, towardTop: true) }
                if identified.isHittable { identified.tap(); continue }
            }
            let close = app.buttons["editor.close"].firstMatch
            if close.exists {
                reveal(close, app, towardTop: true)
                if close.isHittable { close.tap(); continue }
            }
            // A screen-level accessibility identifier can override the shared back ID.
            let candidates = app.buttons.matching(NSPredicate(format: "label IN %@", ["Назад", "Zurück", "Back"]))
                .allElementsBoundByIndex
            guard let back = candidates.first(where: {
                $0.isHittable && $0.frame.minY < 200 && $0.frame.minX < 100
            }) else { break }
            back.tap()
        }
    }

    private func dismissKeyboard(_ app: XCUIApplication) {
        if app.keyboards.firstMatch.exists {
            app.coordinate(withNormalizedOffset: .init(dx: 0.75, dy: 0.12)).tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        }
    }

    private func next(_ app: XCUIApplication) {
        let next = app.buttons["organizationEditor.next"].firstMatch
        reveal(next, app); XCTAssertTrue(next.isEnabled); next.tap()
    }

    private func authority() async throws -> NSDictionary {
        let url = URL(string: "https://firestore.googleapis.com/v1/projects/ukrainiancommunity-dbd5f/databases/(default)/documents/organizations/uac-tirol-info?mask.fieldPaths=ownerId&mask.fieldPaths=adminIds&mask.fieldPaths=moderatorIds")!
        let (data, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(document["fields"] as? NSDictionary)
    }

    private func reveal(_ element: XCUIElement, _ app: XCUIApplication, towardTop: Bool = false) {
        for _ in 0..<24 {
            if element.exists && element.isHittable && element.frame.midY > 80 && element.frame.midY < app.frame.height - 100 { return }
            let down = element.exists ? element.frame.midY < 80 : towardTop
            let keyboard = app.keyboards.firstMatch.exists
            let lower = keyboard ? 0.43 : 0.65
            let upper = keyboard ? 0.25 : 0.35
            // Stay in the form gutter. At accessibility sizes the multiline
            // field covers the centre and would consume gestures internally.
            app.coordinate(withNormalizedOffset: .init(dx: 0.97, dy: down ? upper : lower))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: .init(dx: 0.97, dy: down ? lower : upper)))
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }

    private func captureForeground(_ app: XCUIApplication, _ name: String) {
        // On a physical phone AX queries can still read a background app while
        // screenshot() captures another foreground app. Never accept those pixels.
        XCTAssertEqual(app.state, .runningForeground, "UAC must be foreground for visual acceptance")
        guard app.state == .runningForeground else { return }
        capture(app, name)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        // The physical app's AX root can keep portrait cropping bounds after
        // rotation. Capture the whole screen; callers guard the foreground app.
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

extension PhysicalClosureAuditUITests {
    func testP14AuthorizedVisualPreferencesCommand() throws {
        guard ProcessInfo.processInfo.environment["UACPhysicalVisualPreferencesApproved"] == "2026-10-27",
              let mode = ProcessInfo.processInfo.environment["UACPhysicalVisualCommand"] else {
            throw XCTSkip("Exact user-approved visual command required")
        }
        let app = XCUIApplication()
        if mode == "maximumOpaque" || mode == "restoreNative" {
            let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences"); settings.activate()
            openNativeDisplaySettings(settings)
            let transparency = settings.switches["Transparenz reduzieren"].firstMatch
            reveal(transparency, settings)
            if mode == "maximumOpaque" { XCTAssertEqual(transparency.value as? String, "0") }
            setNativeVisualSwitch(transparency, enabled: mode == "maximumOpaque")
            let larger = settings.staticTexts["Größerer Text"].firstMatch
            reveal(larger, settings, towardTop: true); larger.tap()
            let toggle = settings.switches["LARGER_DYNAMIC_TYPE_SWITCH"].firstMatch
            XCTAssertTrue(toggle.waitForExistence(timeout: 10))
            let slider = settings.sliders.firstMatch
            XCTAssertTrue(slider.waitForExistence(timeout: 10))
            if mode == "maximumOpaque" {
                XCTAssertEqual(toggle.value as? String, "0")
                XCTAssertEqual(sliderPercent(slider), 50, "Recheck the recorded baseline before mutation")
            }
            setNativeVisualSwitch(toggle, enabled: mode == "maximumOpaque")
            let targetPercent = mode == "maximumOpaque" ? 100 : 50
            for _ in 0..<3 {
                slider.adjust(toNormalizedSliderPosition: mode == "maximumOpaque" ? 1 : 0.5)
                let settled = NSPredicate { _, _ in self.sliderPercent(slider) == targetPercent }
                if XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: settled, object: nil)], timeout: 2) == .completed { break }
            }
            XCTAssertEqual(sliderPercent(slider), targetPercent)
            captureForeground(settings, "physical-visual-settings-" + mode)
            app.activate()
            return
        }
        let variants: [String: (String, [String])] = [
            "germanLight": ("de", ["Світлий", "Hell"]),
            "germanDark": ("de", ["Темний", "Dunkel"]),
            "ukrainianLight": ("uk", ["Світлий", "Hell"]),
            "restoreApp": ("uk", ["Системний", "System"])
        ]
        guard let variant = variants[mode] else { XCTFail("Unknown visual command"); return }
        openProfile(app)
        let entry = app.buttons["profile.settings.open"].firstMatch
        reveal(entry, app); entry.tap()
        let language = app.buttons["profile.settings.language"].firstMatch
        reveal(language, app, towardTop: true); language.tap()
        let languageOption = app.buttons["profile.settings.language." + variant.0].firstMatch
        XCTAssertTrue(languageOption.waitForExistence(timeout: 10)); languageOption.tap()
        let appearance = app.buttons["profile.settings.appearance"].firstMatch
        reveal(appearance, app); appearance.tap()
        let option = app.buttons.matching(NSPredicate(format: "label IN %@", variant.1)).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 10)); option.tap()
        XCTAssertTrue(variant.1.contains { appearance.label.contains($0) })
        let expectedLanguage = variant.0 == "uk" ? ["Українська", "Ukrainisch"] : ["Німецька", "Deutsch"]
        XCTAssertTrue(expectedLanguage.contains { language.label.contains($0) })
        captureForeground(app, "physical-visual-settings-" + mode)
        returnFromPushedScreens(app)
    }

    private func sliderPercent(_ slider: XCUIElement) -> Int? {
        Int((slider.value as? String ?? "").filter(\.isNumber))
    }

    private func setNativeVisualSwitch(_ row: XCUIElement, enabled: Bool) {
        let expected = enabled ? "1" : "0"
        guard row.value as? String != expected else { return }
        let inner = row.switches.firstMatch
        if inner.exists {
            inner.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).tap()
        } else {
            row.coordinate(withNormalizedOffset: .init(dx: 0.9, dy: 0.5)).tap()
        }
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: row)], timeout: 10) == .completed)
    }

    private func openNativeDisplaySettings(_ settings: XCUIApplication) {
        if settings.navigationBars["Anzeige & Textgröße"].exists { return }
        for _ in 0..<8 {
            let back = settings.navigationBars.buttons.matching(NSPredicate(format: "label IN %@",
                ["Zurück", "Einstellungen", "Apps", "Mitteilungen", "UAC", "UkrainianCommunity", "Anzeige & Textgröße", "Bedienungshilfen"])).firstMatch
            guard back.exists && back.isHittable else { break }
            back.tap()
            if settings.navigationBars["Anzeige & Textgröße"].exists { return }
        }
        let accessibility = settings.staticTexts["Bedienungshilfen"].firstMatch
        reveal(accessibility, settings); accessibility.tap()
        let display = settings.staticTexts["Anzeige & Textgröße"].firstMatch
        XCTAssertTrue(display.waitForExistence(timeout: 10)); reveal(display, settings); display.tap()
    }

    func testP14VisualBannerSurfacesAtActualPreferences() throws {
        guard ProcessInfo.processInfo.environment["UACPhysicalVisualPreferencesApproved"] == "2026-10-27",
              let marker = ProcessInfo.processInfo.environment["UACPhysicalVisualLabel"],
              ["de-light-maximum-opaque", "de-dark-maximum-opaque", "de-dark-normal", "uk-light-normal"].contains(marker) else {
            throw XCTSkip("Named real-device visual variant required")
        }
        let app = XCUIApplication(); openProfile(app)
        XCTAssertTrue(app.staticTexts["Serlest"].firstMatch.exists)
        app.tabBars.buttons["tab.home"].tap()
        let carousel = app.descendants(matching: .any)["featuredBanner.carousel"].firstMatch
        reveal(carousel, app, towardTop: true)
        captureForeground(app, "physical-p14-" + marker + "-public")
        openProfile(app)
        let entry = app.buttons["profile.featuredBanners"].firstMatch
        reveal(entry, app); entry.tap()
        let search = app.textFields["featured.management.search"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 20)); reveal(search, app)
        search.tap(); search.typeText("KFZ"); dismissKeyboard(app)
        let edit = app.buttons["bannerManagement.edit.kfz-profi-service-tirol-20260910"].firstMatch
        reveal(edit, app); edit.tap()
        let description = app.textViews.matching(NSPredicate(format: "value CONTAINS %@", "Ремонт і сервіс")).firstMatch
        reveal(description, app)
        captureForeground(app, "physical-p14-" + marker + "-multiline-description")
        let toggle = app.switches["bannerEditor.countdown.enabled"].firstMatch
        reveal(toggle, app); XCTAssertEqual(toggle.value as? String, "0"); toggle.tap()
        let label = app.textFields["bannerEditor.countdown.label"].firstMatch
        reveal(label, app); label.tap(); label.typeText("UAC TEST"); dismissKeyboard(app)
        let preview = app.descendants(matching: .any)["bannerEditor.preview"].firstMatch
        if marker.contains("maximum") {
            for _ in 0..<32 {
                if !preview.exists {
                    app.swipeDown()
                    continue
                }
                let frame = preview.frame
                if preview.exists && frame.minY >= 80 && frame.minY < 230 { break }
                let down = frame.minY < 80
                let farAway = abs(frame.minY - 150) > 350
                app.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: down ? 0.40 : 0.65))
                    .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: down ? (farAway ? 0.75 : 0.52) : (farAway ? 0.30 : 0.53))))
            }
            let timer = app.descendants(matching: .any)["featuredBanner.countdown"].firstMatch
            XCTAssertGreaterThanOrEqual(timer.frame.minY, 70)
            XCTAssertLessThan(timer.frame.maxY, app.frame.height - 30)
        } else { revealWholeBannerPreview(preview, app) }
        XCTAssertTrue(app.descendants(matching: .any)["featuredBanner.countdown"].firstMatch.exists)
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        captureForeground(app, "physical-p14-" + marker + "-countdown-preview-top")
        if marker.contains("maximum") { app.swipeUp(); captureForeground(app, "physical-p14-" + marker + "-preview-text") }
        let close = app.buttons["editor.close"].firstMatch
        reveal(close, app, towardTop: true); close.tap()
        let discard = app.buttons["bannerEditor.discard"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 10)); reveal(discard, app)
        captureForeground(app, "physical-p14-" + marker + "-discard"); discard.tap()
        reveal(edit, app); edit.tap()
        let statistics = app.buttons["bannerEditor.statistics"].firstMatch
        reveal(statistics, app, towardTop: true); statistics.tap()
        let metric = app.descendants(matching: .any)["ownerAnalytics.metric.eye"].firstMatch
        XCTAssertTrue(app.buttons["bannerReport.regionFilter"].firstMatch.waitForExistence(timeout: 25))
        reveal(metric, app)
        captureForeground(app, "physical-p14-" + marker + "-metrics")
        app.swipeUp()
        captureForeground(app, "physical-p14-" + marker + "-metrics-continuation")
        let regions = app.buttons["bannerReport.regionFilter"].firstMatch
        reveal(regions, app)
        captureForeground(app, "physical-p14-" + marker + "-confirmed-report")
        app.swipeUp()
        captureForeground(app, "physical-p14-" + marker + "-chart-and-regions")
        returnFromPushedScreens(app)
        XCTAssertTrue(app.tabBars.buttons["tab.profile"].waitForExistence(timeout: 15))
        // Only discarded local preview changes. Settings are restored by the
        // separately named, explicitly approved restore commands after this matrix.
    }

    func testP14FinishCurrentControlledPreviewAndReadReport() throws {
        guard ProcessInfo.processInfo.environment["UACPhysicalVisualPreferencesApproved"] == "2026-10-27",
              let marker = ProcessInfo.processInfo.environment["UACPhysicalVisualLabel"] else {
            throw XCTSkip("Exact approved controlled local preview required")
        }
        let app = XCUIApplication(); app.activate()
        let label = app.textFields["bannerEditor.countdown.label"].firstMatch
        XCTAssertTrue(label.exists)
        XCTAssertEqual(label.value as? String, "UAC TEST", "Only our unsaved preview may be discarded")
        let preview = app.descendants(matching: .any)["bannerEditor.preview"].firstMatch
        revealWholeBannerPreview(preview, app)
        captureForeground(app, "physical-p14-" + marker + "-complete-preview")
        let close = app.buttons["editor.close"].firstMatch
        reveal(close, app, towardTop: true); close.tap()
        let discard = app.buttons["bannerEditor.discard"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 10)); reveal(discard, app)
        captureForeground(app, "physical-p14-" + marker + "-discard"); discard.tap()
        let edit = app.buttons["bannerManagement.edit.kfz-profi-service-tirol-20260910"].firstMatch
        reveal(edit, app); edit.tap()
        let statistics = app.buttons["bannerEditor.statistics"].firstMatch
        reveal(statistics, app, towardTop: true); statistics.tap()
        try testP14ReadCurrentConfirmedBannerReportAtActualPreferences()
    }

    func testP14ReadCurrentConfirmedBannerReportAtActualPreferences() throws {
        guard ProcessInfo.processInfo.environment["UACPhysicalVisualPreferencesApproved"] == "2026-10-27",
              let marker = ProcessInfo.processInfo.environment["UACPhysicalVisualLabel"] else {
            throw XCTSkip("Approved visual variant and already open banner report required")
        }
        let app = XCUIApplication(); app.activate()
        XCTAssertTrue(app.buttons["bannerReport.period"].firstMatch.waitForExistence(timeout: 20))
        let regions = app.buttons["bannerReport.regionFilter"].firstMatch
        XCTAssertTrue(regions.waitForExistence(timeout: 25))
        let metric = app.descendants(matching: .any)["ownerAnalytics.metric.eye"].firstMatch
        // Lazy metric cards are below the long accessibility intro. Scroll down
        // until instantiated, rather than assuming a missing card is above us.
        reveal(metric, app)
        let total = metric.value as? String
        XCTAssertNotNil(total)
        captureForeground(app, "physical-p14-" + marker + "-report-metrics")
        let rate = app.descendants(matching: .any)["ownerAnalytics.metric.percent"].firstMatch
        reveal(rate, app)
        captureForeground(app, "physical-p14-" + marker + "-report-rate")
        reveal(regions, app); regions.tap()
        captureForeground(app, "physical-p14-" + marker + "-region-options")
        let allRegions = app.buttons.matching(NSPredicate(format: "label IN %@", ["Усі регіони показу", "Alle Anzeigeregionen"])).firstMatch
        XCTAssertTrue(allRegions.waitForExistence(timeout: 10)); allRegions.tap()
        let sections = app.buttons["bannerReport.sectionFilter"].firstMatch
        reveal(sections, app); sections.tap()
        let home = app.buttons.matching(NSPredicate(format: "label IN %@", ["Новини", "Nachrichten"])).firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 10)); home.tap()
        XCTAssertTrue(["Новини", "Nachrichten"].contains(sections.value as? String ?? ""))
        captureForeground(app, "physical-p14-" + marker + "-section-filter")
        sections.tap()
        let allSections = app.buttons.matching(NSPredicate(format: "label IN %@", ["Усі розділи", "Alle Bereiche"])).firstMatch
        XCTAssertTrue(allSections.waitForExistence(timeout: 10)); allSections.tap()
        captureForeground(app, "physical-p14-" + marker + "-wrapping-filters")
        app.swipeUp()
        captureForeground(app, "physical-p14-" + marker + "-chart")
        app.swipeUp()
        captureForeground(app, "physical-p14-" + marker + "-regions")
        reveal(metric, app, towardTop: true)
        XCTAssertEqual(metric.value as? String, total, "Resetting local filters restores the same confirmed totals")
        returnFromPushedScreens(app)
        XCTAssertTrue(app.tabBars.buttons["tab.profile"].waitForExistence(timeout: 15))
    }

    func testP14AResolveSystemPhotoPickerCancellation() {
        let app = XCUIApplication(); app.activate()
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10), "Only the currently open native photo picker is in scope")
        let diagnostic = XCTAttachment(string: cancel.debugDescription)
        diagnostic.name = "physical-photo-cancel-target"; diagnostic.lifetime = .keepAlways; add(diagnostic)
        XCTAssertTrue(cancel.isHittable)
        cancel.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 10), "Do not scroll or navigate until native picker cancellation actually completes")
        let close = app.buttons["editor.close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 10)); close.tap()
        XCTAssertFalse(app.buttons["bannerEditor.discard"].exists, "No banner fields were edited before this cancelled photo selection")
        let search = app.textFields["featured.management.search"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        captureForeground(app, "physical-p14-photo-cancel-returned-to-unchanged-management")
        returnFromPushedScreens(app)
    }

    private func controlledFeedbackContext() throws -> (id: String, notice: String, marker: String) {
        let env = ProcessInfo.processInfo.environment
        guard let id = env["UACPhysicalFeedbackID"], UUID(uuidString: id) != nil,
              let notice = env["UACPhysicalFeedbackOwnerNoticeID"], notice.hasPrefix("feedbackSubmitted_" + id + "_"),
              let marker = env["UACPhysicalFeedbackMarker"], marker.hasPrefix("UAC TEST P12-20261027") else {
            throw XCTSkip("Exact approved controlled feedback context required")
        }
        return (id, notice, marker)
    }

    private func openControlledFeedbackNotice(_ app: XCUIApplication, context: (id: String, notice: String, marker: String)) {
        app.activate()
        if app.textViews["feedback.reply.text"].firstMatch.exists {
            let input = app.textViews["feedback.reply.text"].firstMatch
            XCTAssertTrue((input.value as? String ?? "").isEmpty, "Do not discard a pending reply during setup")
            let done = app.buttons.matching(NSPredicate(format: "label IN %@", ["Готово", "Fertig", "Done"])).firstMatch
            XCTAssertTrue(done.isHittable); done.tap()
        }
        let detailClose = app.buttons["notificationDetail.close"].firstMatch
        if detailClose.exists && detailClose.isHittable { detailClose.tap() }
        openProfile(app)
        let owner = app.staticTexts["Serlest"].firstMatch
        reveal(owner, app, towardTop: true); XCTAssertTrue(owner.exists)
        let notifications = app.buttons["profile.notifications.open"].firstMatch
        reveal(notifications, app); notifications.tap()
        let notice = app.buttons["notificationInbox.open." + context.notice].firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 20))
        reveal(notice, app); captureForeground(app, "physical-p12-owner-exact-notice")
        notice.tap()
        let preview = app.staticTexts["notificationDetail.body"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 15))
        XCTAssertTrue(preview.label.contains("UAC TEST P12-20261027"))
        captureForeground(app, "physical-p12-owner-notification-detail")
        let destination = app.buttons["notificationDetail.openDestination"].firstMatch
        XCTAssertTrue(destination.waitForExistence(timeout: 15)); reveal(destination, app); destination.tap()
        let original = app.staticTexts.matching(NSPredicate(format: "label == %@", context.marker)).firstMatch
        XCTAssertTrue(original.waitForExistence(timeout: 20))
        captureForeground(app, "physical-p12-exact-feedback-thread")
        XCTAssertTrue(app.textViews["feedback.reply.text"].firstMatch.exists)
    }

    func testP12AOwnerNotificationOpensTheExactControlledFeedback() throws {
        let context = try controlledFeedbackContext()
        let app = XCUIApplication(); openControlledFeedbackNotice(app, context: context)
        // A controlled deep link installs its manager inbox as the parent route.
        // Done dismisses the conversation into that inbox, not into Profile.
        let done = app.buttons.matching(NSPredicate(format: "label IN %@", ["Готово", "Fertig", "Done"])).firstMatch
        XCTAssertTrue(done.isHittable); done.tap()
        XCTAssertTrue(app.textViews["feedback.reply.text"].firstMatch.waitForNonExistence(timeout: 10))
        let search = app.textFields["feedbackInbox.search"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 15)); reveal(search, app)
        XCTAssertTrue(search.isHittable)
        captureForeground(app, "physical-p12-return-to-manager-inbox")
    }

    func testP12BOwnerRepliesOnlyToTheApprovedControlledFeedback() throws {
        let context = try controlledFeedbackContext()
        guard ProcessInfo.processInfo.environment["UACPhysicalFeedbackRoundTripApproved"] == "2026-10-27" else {
            throw XCTSkip("Human authorization for this exact test exchange required")
        }
        let app = XCUIApplication(); openControlledFeedbackNotice(app, context: context)
        let reply = "UAC TEST P12-20261027 REPLY-1: повідомлення отримано. Контрольована перевірка відповіді."
        XCTAssertFalse(app.staticTexts[reply].firstMatch.exists, "Never send this test response twice")
        let input = app.textViews["feedback.reply.text"].firstMatch
        reveal(input, app); input.tap(); input.typeText(reply)
        XCTAssertEqual(input.value as? String, reply)
        captureForeground(app, "physical-p12-owner-reply-keyboard")
        dismissKeyboard(app)
        let send = app.buttons["feedback.reply.send"].firstMatch
        reveal(send, app); XCTAssertTrue(send.isEnabled); send.tap()
        XCTAssertTrue(app.staticTexts[reply].firstMatch.waitForExistence(timeout: 20))
        captureForeground(app, "physical-p12-owner-reply-saved")
    }
}

extension PhysicalClosureAuditUITests {
    func testP14ReadOriginalVisualPreferences() throws {
        guard ProcessInfo.processInfo.environment["UACPhysicalVisualPreferencesApproved"] == "2026-10-27" else {
            throw XCTSkip("User-approved temporary visual settings check required")
        }
        let app = XCUIApplication(); openProfile(app)
        let settingsEntry = app.buttons["profile.settings.open"].firstMatch
        reveal(settingsEntry, app); settingsEntry.tap()
        let language = app.buttons["profile.settings.language"].firstMatch
        let appearance = app.buttons["profile.settings.appearance"].firstMatch
        XCTAssertTrue(language.waitForExistence(timeout: 15)); reveal(language, app, towardTop: true)
        let preferences = XCTAttachment(string: "language=\(language.value ?? "nil") / \(language.label)\nappearance=\(appearance.value ?? "nil") / \(appearance.label)")
        preferences.name = "physical-original-uac-visual-preferences"
        preferences.lifetime = .keepAlways; add(preferences)
        captureForeground(app, "physical-original-language-and-theme")
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.activate()
        defer { app.activate() }
        for _ in 0..<8 {
            let back = settings.navigationBars.buttons.matching(NSPredicate(format: "label IN %@",
                ["Zurück", "Einstellungen", "Apps", "Mitteilungen", "UAC", "UkrainianCommunity", "Anzeige & Textgröße", "Bedienungshilfen"])).firstMatch
            guard back.exists && back.isHittable else { break }
            back.tap()
        }
        let accessibility = settings.staticTexts["Bedienungshilfen"].firstMatch
        reveal(accessibility, settings); accessibility.tap()
        let display = settings.staticTexts["Anzeige & Textgröße"].firstMatch
        XCTAssertTrue(display.waitForExistence(timeout: 10)); reveal(display, settings); display.tap()
        let transparency = settings.switches["Transparenz reduzieren"].firstMatch
        reveal(transparency, settings)
        let originalTransparency = transparency.value as? String ?? "unknown"
        captureForeground(settings, "physical-original-reduce-transparency")
        let larger = settings.staticTexts["Größerer Text"].firstMatch
        reveal(larger, settings, towardTop: true); larger.tap()
        let slider = settings.sliders.firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 10))
        let original = XCTAttachment(string: "reduceTransparency=\(originalTransparency)\n" + settings.debugDescription)
        original.name = "physical-original-accessibility-visual-preferences"
        original.lifetime = .keepAlways; add(original)
        captureForeground(settings, "physical-original-larger-text")
        // Read only. Capture the actual baseline before any approved mutation.
    }

    func testP15ActualNewsEventAndOrganizationAnalyticsDetails() {
        let app = XCUIApplication(); openProfile(app)
        let entry = app.buttons["profile.owner.analytics"].firstMatch
        reveal(entry, app); entry.tap()
        let updated = app.descendants(matching: .any)["ownerAnalytics.updatedAt"].firstMatch
        XCTAssertTrue(updated.waitForExistence(timeout: 30))
        let thirty = app.buttons["30 днів"].firstMatch
        reveal(thirty, app, towardTop: true); thirty.tap()
        XCTAssertTrue(updated.waitForExistence(timeout: 30))
        for type in ["news", "event", "organization"] {
            let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ownerAnalytics.content." + type + ".")).firstMatch
            reveal(row, app); let title = row.label; row.tap()
            let screenID = type == "organization" ? "screen.ownerAnalytics.organizationDetail" : "screen.ownerAnalytics.contentDetail"
            let detail = app.descendants(matching: .any)[screenID].firstMatch
            XCTAssertTrue(detail.waitForExistence(timeout: 20))
            // The screen identifier can belong to a shell AX element rather
            // than an ancestor of the cards. Select only the foreground tile.
            var visibleMetric: XCUIElement?
            let metricID = type == "organization" ? "ownerAnalytics.metric.person.crop.rectangle" : "ownerAnalytics.metric.eye"
            let confirmed = NSPredicate { _, _ in
                visibleMetric = app.descendants(matching: .any).matching(identifier: metricID)
                    .allElementsBoundByIndex.first { $0.isHittable }
                return visibleMetric != nil
            }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: confirmed, object: nil)], timeout: 30), .completed)
            guard let metric = visibleMetric else { XCTFail("No confirmed foreground detail metric"); return }
            let loaded = XCTAttachment(string: "Opened actual " + type + " analytics for " + title + "; views=" + (metric.value as? String ?? "missing"))
            loaded.name = "physical-p15-confirmed-detail-" + type; loaded.lifetime = .keepAlways; add(loaded)
            captureForeground(app, "physical-p15-" + type + "-confirmed-detail")
            for periodTitle in ["7 днів", "30 днів"] {
                let candidates = app.buttons.matching(NSPredicate(format: "label == %@", periodTitle)).allElementsBoundByIndex
                guard let period = candidates.first(where: { $0.isHittable }) else { XCTFail("Foreground detail period is not visible"); return }
                period.tap()
                XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: period)], timeout: 10), .completed)
                captureForeground(app, "physical-p15-" + type + "-period-" + periodTitle)
            }
            app.swipeUp()
            captureForeground(app, "physical-p15-" + type + "-regions")
            let identifiedBack = app.buttons.matching(identifier: "navigation.back").allElementsBoundByIndex.first { $0.isHittable }
            // The shell screen ID can override the back ID on the actual phone.
            let localizedBack = app.buttons.matching(NSPredicate(format: "label IN %@", ["Назад", "Zurück", "Back"]))
                .allElementsBoundByIndex.first { $0.isHittable && $0.frame.minY < 200 && $0.frame.minX < 100 }
            let back = identifiedBack ?? localizedBack
            XCTAssertNotNil(back); back?.tap()
            XCTAssertTrue(detail.waitForNonExistence(timeout: 10))
            XCTAssertTrue(thirty.isSelected, "Returning from details retains the root30day report")
        }
        returnFromPushedScreens(app)
        XCTAssertTrue(app.tabBars.buttons["tab.profile"].waitForExistence(timeout: 15))
    }

    func testP15ActualOwnerAnalyticsPeriodsSearchAndConfirmedCount() {
        let app = XCUIApplication(); openProfile(app)
        let entry = app.buttons["profile.owner.analytics"].firstMatch
        reveal(entry, app); entry.tap()
        let updated = app.descendants(matching: .any)["ownerAnalytics.updatedAt"].firstMatch
        XCTAssertTrue(updated.waitForExistence(timeout: 30))
        let count = app.descendants(matching: .any)["ownerAnalytics.metric.person.3"].firstMatch
        reveal(count, app)
        let value = count.value as? String ?? ""
        XCTAssertNotNil(Int(value))
        let countEvidence = XCTAttachment(string: "Actual protected current-account count: " + value)
        countEvidence.name = "physical-p15-confirmed-account-count"; countEvidence.lifetime = .keepAlways; add(countEvidence)
        captureForeground(app, "physical-p15-owner-current-count-and-report")
        for title in ["7 днів", "30 днів"] {
            let period = app.buttons[title].firstMatch
            reveal(period, app, towardTop: true); period.tap()
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: period)], timeout: 10), .completed)
            XCTAssertTrue(updated.waitForExistence(timeout: 30))
            captureForeground(app, "physical-p15-actual-period-" + title)
        }
        let search = app.textFields["ownerAnalytics.search"].firstMatch
        reveal(search, app, towardTop: true); search.tap(); search.typeText("UAC-NO-MATCH-20261027\n")
        let empty = app.descendants(matching: .any)["ownerAnalytics.search.empty"].firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 15))
        captureForeground(app, "physical-p15-search-confirmed-no-match")
        let clear = app.buttons["ownerAnalytics.search.clear"].firstMatch
        reveal(clear, app, towardTop: true); clear.tap()
        search.typeText("\n")
        XCTAssertTrue(clear.waitForNonExistence(timeout: 10))
        XCTAssertTrue(empty.waitForNonExistence(timeout: 10))
        XCTAssertTrue(updated.waitForExistence(timeout: 20))
        let chart = app.descendants(matching: .any)["ownerAnalytics.trendChart"].firstMatch
        reveal(chart, app)
        captureForeground(app, "physical-p15-actual-thirty-day-trend")
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "physical-p15-actual-loaded-owner-hierarchy"; hierarchy.lifetime = .keepAlways; add(hierarchy)
        returnFromPushedScreens(app)
        XCTAssertTrue(app.tabBars.buttons["tab.profile"].waitForExistence(timeout: 15))
    }

    func testP14CurrentPublicCarouselReadAndSwipe() {
        let app = XCUIApplication(); openProfile(app)
        app.tabBars.buttons["tab.home"].tap()
        let carousel = app.descendants(matching: .any)["featuredBanner.carousel"].firstMatch
        reveal(carousel, app, towardTop: true)
        captureForeground(app, "physical-p14-current-public-carousel-before-swipe")
        carousel.swipeLeft()
        captureForeground(app, "physical-p14-current-public-carousel-after-swipe")
    }

    func testP14PhysicalBannerOrientationVisualEvidence() {
        let app = XCUIApplication(); app.activate()
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(waitForStablePhysicalOrientation(app, landscape: false))
        openProfile(app); app.tabBars.buttons["tab.home"].tap()
        let carousel = app.descendants(matching: .any)["featuredBanner.carousel"].firstMatch
        reveal(carousel, app, towardTop: true)
        captureForeground(app, "physical-p14-orientation-portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertEqual(XCUIDevice.shared.orientation, .landscapeLeft)
        // The root AX frame and UIImage.size are not reliable orientation
        // probes here. Wait for the main window's transform to settle before
        // capturing; a mid-animation screenshot is not visual acceptance.
        XCTAssertTrue(waitForStablePhysicalOrientation(app, landscape: true))
        let landscapeCarousel = app.descendants(matching: .any)["featuredBanner.carousel"].firstMatch
        let settled = NSPredicate { _, _ in
            guard landscapeCarousel.exists else { return false }
            let viewport = landscapeCarousel.frame
            // Query the stable carousel container, not indices into a lazy
            // card list that is being rebuilt by rotation.
            return viewport.height > 0 && viewport.height < app.windows.firstMatch.frame.height
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: settled, object: nil)], timeout: 12), .completed,
                       "A settled window transform must also replace the stale accessibility-height carousel measurement")
        captureForeground(app, "physical-p14-orientation-landscape")
        let geometry = XCTAttachment(string: app.debugDescription)
        geometry.name = "physical-p14-landscape-actual-hierarchy"
        geometry.lifetime = .keepAlways; add(geometry)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(waitForStablePhysicalOrientation(app, landscape: false))
        captureForeground(app, "physical-p14-orientation-restored")
    }

    private func waitForStablePhysicalOrientation(_ app: XCUIApplication, landscape: Bool) -> Bool {
        let predicate = NSPredicate { _, _ in
            let frame = app.windows.firstMatch.frame
            return abs(frame.minX) < 1 && abs(frame.minY) < 1
                && (landscape ? frame.width > frame.height : frame.height > frame.width)
        }
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 10) == .completed
    }

    private func revealWholeBannerPreview(_ preview: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<12 {
            let top = app.buttons["editor.close"].firstMatch.frame.maxY + 36
            let frame = preview.frame
            if preview.exists && frame.minY >= top && frame.maxY < app.frame.height - 40 { return }
            let moveDown = frame.minY < top
            app.coordinate(withNormalizedOffset: .init(dx: 0.97, dy: moveDown ? 0.40 : 0.65))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: .init(dx: 0.97, dy: moveDown ? 0.58 : 0.45)))
        }
        XCTAssertGreaterThanOrEqual(preview.frame.minY, app.buttons["editor.close"].firstMatch.frame.maxY + 36)
        XCTAssertLessThan(preview.frame.maxY, app.frame.height - 40)
    }

    func testP14InstalledBannerDraftPreviewDiscardAndSpecificStatistics() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication(); app.activate()
        if app.textViews["feedback.reply.text"].firstMatch.exists {
            XCTAssertTrue((app.textViews["feedback.reply.text"].firstMatch.value as? String ?? "").isEmpty)
            app.buttons.matching(NSPredicate(format: "label IN %@", ["Готово", "Fertig", "Done"])).firstMatch.tap()
        }
        openProfile(app)
        let owner = app.staticTexts["Serlest"].firstMatch
        reveal(owner, app, towardTop: true); XCTAssertTrue(owner.exists)
        app.tabBars.buttons["tab.home"].tap()
        let carousel = app.descendants(matching: .any)["featuredBanner.carousel"].firstMatch
        reveal(carousel, app, towardTop: true)
        XCTAssertTrue(carousel.waitForExistence(timeout: 20))
        captureForeground(app, "physical-p14-public-carousel-portrait")
        carousel.swipeLeft()
        captureForeground(app, "physical-p14-public-carousel-after-swipe")
        openProfile(app)
        let entry = app.buttons["profile.featuredBanners"].firstMatch
        reveal(entry, app); entry.tap()
        let search = app.textFields["featured.management.search"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 25))
        XCTAssertTrue(app.tabBars.firstMatch.waitForNonExistence(timeout: 5))
        search.tap(); search.typeText("KFZ Profi Service")
        dismissKeyboard(app)
        let bannerID = "kfz-profi-service-tirol-20260910"
        let edit = app.buttons["bannerManagement.edit." + bannerID].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 25)); reveal(edit, app)
        captureForeground(app, "physical-p14-real-banner-management")
        edit.tap()
        let preview = app.descendants(matching: .any)["bannerEditor.preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 15)); reveal(preview, app, towardTop: true)
        XCTAssertFalse(app.tabBars.firstMatch.exists, "Editor fields must not be covered by root tabs")
        let originalPreviewHeight = preview.frame.height
        captureForeground(app, "physical-p14-original-editor-preview")
        let picker = app.descendants(matching: .any)["bannerEditor.titleColor"].firstMatch
        reveal(picker, app); picker.tap()
        captureForeground(app, "physical-p14-native-color-picker")
        let pickerClose = app.buttons.matching(NSPredicate(format: "label IN %@", ["Schließen", "Close", "Fertig", "Готово"])).firstMatch
        XCTAssertTrue(pickerClose.waitForExistence(timeout: 5)); pickerClose.tap()
        // Native photo open/cancel has separate installed-device evidence.
        // Keep this repeat focused on countdown, preview and chart regressions.
        let toggle = app.switches["bannerEditor.countdown.enabled"].firstMatch
        reveal(toggle, app); let original = toggle.value as? String
        XCTAssertEqual(original, "0", "The exact server baseline has no countdown")
        toggle.tap()
        let date = app.descendants(matching: .any)["bannerEditor.countdown.date"].firstMatch
        reveal(date, app); XCTAssertTrue(date.exists)
        captureForeground(app, "physical-p14-local-countdown-controls")
        let dateButton = date.buttons.firstMatch
        if dateButton.exists { dateButton.tap() } else { date.tap() }
        captureForeground(app, "physical-p14-native-countdown-date")
        app.coordinate(withNormalizedOffset: .init(dx: 0.97, dy: 0.12)).tap()
        let label = app.textFields["bannerEditor.countdown.label"].firstMatch
        reveal(label, app); label.tap(); label.typeText("UAC TEST — лише чернетка")
        XCTAssertTrue((label.value as? String ?? "").contains("лише чернетка"))
        dismissKeyboard(app)
        let headingColor = app.buttons["bannerEditor.titleColor.yellow"].firstMatch
        reveal(headingColor, app, towardTop: true); headingColor.tap()
        let subtitleColor = app.buttons["bannerEditor.subtitleColor.white"].firstMatch
        reveal(subtitleColor, app); subtitleColor.tap()
        revealWholeBannerPreview(preview, app)
        let timer = app.descendants(matching: .any)["featuredBanner.countdown"].firstMatch
        XCTAssertTrue(timer.waitForExistence(timeout: 10))
        XCTAssertEqual(preview.frame.height, originalPreviewHeight, accuracy: 1, "Adding a countdown must not shrink the artwork at this type size")
        captureForeground(app, "physical-p14-countdown-colors-local-preview")
        let first = timer.label
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", first), object: timer)], timeout: 5) == .completed)
        captureForeground(app, "physical-p14-countdown-seconds-advanced")
        let close = app.buttons["editor.close"].firstMatch
        XCTAssertTrue(close.isHittable); close.tap()
        let keep = app.buttons["bannerEditor.keepEditing"].firstMatch
        XCTAssertTrue(keep.waitForExistence(timeout: 5)); captureForeground(app, "physical-p14-discard-confirmation")
        keep.tap(); close.tap()
        app.buttons["bannerEditor.discard"].tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 10)); reveal(edit, app); edit.tap()
        reveal(toggle, app)
        XCTAssertEqual(toggle.value as? String, original, "Discard must not publish the local countdown")
        captureForeground(app, "physical-p14-reopened-original-without-countdown")
        let statistics = app.buttons["bannerEditor.statistics"].firstMatch
        reveal(statistics, app, towardTop: true); statistics.tap()
        let period = app.buttons["bannerReport.period"].firstMatch
        XCTAssertTrue(period.waitForExistence(timeout: 15))
        let regions = app.buttons["bannerReport.regionFilter"].firstMatch
        XCTAssertTrue(regions.waitForExistence(timeout: 30), "Filters appear only after the actual protected report loads")
        XCTAssertFalse(app.tabBars.firstMatch.exists)
        captureForeground(app, "physical-p14-exact-banner-statistics-confirmed")
        reveal(regions, app)
        captureForeground(app, "physical-p14-exact-banner-statistics-regions")
        // No Save, active toggle, duplicate, deletion, export or external ad click.
    }

    func testP13InstalledNotificationFiltersAndExistingPreferences() {
        let app = XCUIApplication(); app.activate()
        if app.textViews["feedback.reply.text"].firstMatch.exists {
            XCTAssertTrue((app.textViews["feedback.reply.text"].firstMatch.value as? String ?? "").isEmpty)
            app.buttons.matching(NSPredicate(format: "label IN %@", ["Готово", "Fertig", "Done"])).firstMatch.tap()
        }
        openProfile(app)
        let owner = app.staticTexts["Serlest"].firstMatch
        reveal(owner, app, towardTop: true); XCTAssertTrue(owner.exists)
        let notifications = app.buttons["profile.notifications.open"].firstMatch
        reveal(notifications, app); notifications.tap()
        let filter = app.buttons["notificationInbox.filter"].firstMatch
        XCTAssertTrue(filter.waitForExistence(timeout: 20))
        XCTAssertTrue(app.tabBars.firstMatch.waitForNonExistence(timeout: 5), "Owning stack must hide tabs on the actual phone")
        captureForeground(app, "physical-p13-installed-inbox-no-root-tabs")
        for labels in [["Непрочитані", "Ungelesen"], ["Архів", "Archiv"], ["Усі", "Alle"]] {
            filter.tap()
            let option = app.buttons.matching(NSPredicate(format: "label IN %@", labels)).firstMatch
            XCTAssertTrue(option.waitForExistence(timeout: 5)); option.tap()
            XCTAssertTrue(filter.waitForExistence(timeout: 10))
            XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: filter)], timeout: 20) == .completed)
            XCTAssertFalse(app.buttons["notificationInbox.retry"].exists)
            captureForeground(app, "physical-p13-filter-" + labels[1])
        }
        returnFromPushedScreens(app)
        let settings = app.buttons["profile.settings.open"].firstMatch
        reveal(settings, app); settings.tap()
        let enabled = app.switches["notifications.enabled"].firstMatch
        reveal(enabled, app)
        XCTAssertTrue(enabled.isHittable)
        XCTAssertTrue(["0", "1"].contains(enabled.value as? String ?? ""))
        XCTAssertFalse(app.buttons["notifications.retry"].exists)
        captureForeground(app, "physical-p13-existing-notification-preferences")
        let reminders = app.switches["notifications.reminders"].firstMatch
        reveal(reminders, app)
        XCTAssertTrue(["0", "1"].contains(reminders.value as? String ?? ""))
        captureForeground(app, "physical-p13-existing-reminders-and-test-action")
        // Read-only: retain preferences and permissions. Never mark all real notices read.
    }
}
