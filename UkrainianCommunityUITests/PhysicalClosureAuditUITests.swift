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

    func testReturnOnlyTheAuthorizedTestRequestForRevisionAndReadHistory() throws {
        let requestID = ProcessInfo.processInfo.environment["UACPhysicalAuditRequestID"] ?? ""
        guard !requestID.isEmpty else { throw XCTSkip("Exact controlled request ID required") }
        let app = XCUIApplication()
        openProfile(app)
        let owner = app.staticTexts["Serlest"].firstMatch
        reveal(owner, app, towardTop: true)
        XCTAssertTrue(owner.exists, "Use the authorized platform owner account")
        let requests = app.buttons["profile.organizationRequests"].firstMatch
        reveal(requests, app); requests.tap()
        let open = app.buttons["organization.requests.open." + requestID].firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 20)); reveal(open, app); open.tap()
        XCTAssertTrue(app.staticTexts["UAC — тест перевірки заявки"].firstMatch.waitForExistence(timeout: 10),
                      "Never review another organization's request")
        let confirm = app.buttons["organization.request.confirm"].firstMatch
        XCTAssertTrue(confirm.exists); XCTAssertFalse(confirm.isEnabled)
        let approve = app.buttons["organization.request.choice.approve"].firstMatch
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
        let history = app.segmentedControls["organization.requests.mode"].firstMatch
        XCTAssertTrue(history.exists); history.buttons.element(boundBy: 1).tap()
        let recordedReason = app.staticTexts[reasonText].firstMatch
        XCTAssertTrue(recordedReason.waitForExistence(timeout: 15)); reveal(recordedReason, app)
        capture(app, "physical-review-test-history")
        // The only submitted decision is requestRevision for the exact controlled ID.
    }

    private func openProfile(_ app: XCUIApplication) {
        app.activate()
        let candidateCancel = app.buttons["organization.team.cancelSearch"].firstMatch
        if candidateCancel.exists && candidateCancel.isHittable { candidateCancel.tap() }
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        app.tabBars.buttons.element(boundBy: 4).tap()
        for _ in 0..<6 {
            let back = app.buttons["navigation.back"].firstMatch
            if !back.exists { break }
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
