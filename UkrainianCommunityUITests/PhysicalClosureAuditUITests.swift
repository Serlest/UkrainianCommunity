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
        let keysLoaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: passkey)
        XCTAssertEqual(XCTWaiter.wait(for: [keysLoaded], timeout: 20), .completed,
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
        let profile = app.tabBars.buttons["tab.profile"].firstMatch
        XCTAssertTrue(profile.isHittable, "Return from a tab-bar-hidden screen before selecting Profile")
        profile.tap()
        returnFromPushedScreens(app)
    }

    private func returnFromPushedScreens(_ app: XCUIApplication) {
        for _ in 0..<8 {
            let identified = app.buttons["navigation.back"].firstMatch
            if identified.exists && identified.isHittable { identified.tap(); continue }
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
        for _ in 0..<16 {
            if element.exists && element.isHittable && element.frame.midY > 80 && element.frame.midY < app.frame.height - 100 { return }
            let down = element.exists ? element.frame.midY < 80 : towardTop
            let keyboard = app.keyboards.firstMatch.exists
            let lower = keyboard ? 0.43 : 0.65
            let upper = keyboard ? 0.25 : 0.35
            app.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: down ? upper : lower))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: down ? lower : upper)))
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
