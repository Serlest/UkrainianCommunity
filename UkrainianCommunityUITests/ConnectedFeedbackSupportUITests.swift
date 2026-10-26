import XCTest

/// Real UI and SDK against fixed loopback demo services. No production transport.
@MainActor final class ConnectedFeedbackSupportUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" else { throw XCTSkip("Isolated feedback emulators required") }
    }

    func testComposeOwnHistoryAndFollowupHaveIndependentReadback() async throws {
        let marker = "Connected feedback UI " + UUID().uuidString
        let app = login("reporter")
        app.tabBars.buttons.element(boundBy: 4).tap()
        let compose = app.buttons["profile.feedback.compose"]
        reveal(compose, app); compose.tap()
        let input = app.textViews["feedback.compose.text"]
        XCTAssertTrue(input.waitForExistence(timeout: 8)); input.tap(); input.typeText(marker)
        if app.keyboards.firstMatch.exists { app.swipeDown() }
        let submit = app.buttons["feedback.compose.submit"]
        reveal(submit, app); XCTAssertTrue(submit.isEnabled); capture(app, "sdk-feedback-composer-ready"); submit.tap()
        var records: [[String: Any]] = []
        for _ in 0..<40 {
            records = try await queryOwnFeedback(marker: marker)
            if !records.isEmpty { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        XCTAssertEqual(records.count, 1)
        let document = try XCTUnwrap(records.first)
        let path = try XCTUnwrap(document["name"] as? String)
        let id = try XCTUnwrap(path.split(separator: "/").last).description
        let fields = try XCTUnwrap(document["fields"] as? [String: [String: Any]])
        XCTAssertEqual(fields["userId"]?["stringValue"] as? String, "feedback-audit-reporter")
        XCTAssertEqual(fields["message"]?["stringValue"] as? String, marker)
        XCTAssertEqual(fields["status"]?["stringValue"] as? String, "open")
        capture(app, "sdk-feedback-submitted")
        app.buttons["Назад"].firstMatch.tap()
        let mine = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Мої звернення")).firstMatch
        reveal(mine, app); mine.tap()
        let row = app.buttons["feedback.mine.open." + id]
        XCTAssertTrue(row.waitForExistence(timeout: 15)); reveal(row, app); row.tap()
        let reply = app.textViews["feedback.reply.text"]
        XCTAssertTrue(reply.waitForExistence(timeout: 8)); reveal(reply, app); reply.tap(); reply.typeText("Connected follow-up from reporter")
        if app.keyboards.firstMatch.exists { app.swipeDown() }
        let send = app.buttons["feedback.reply.send"]
        reveal(send, app); send.tap()
        XCTAssertTrue(app.staticTexts["Connected follow-up from reporter"].firstMatch.waitForExistence(timeout: 15))
        let read = try await readOwnedMessages(feedbackID: id)
        let messages = try XCTUnwrap(read["documents"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 1)
        let message = try XCTUnwrap(messages.first?["fields"] as? [String: [String: Any]])
        XCTAssertEqual(message["text"]?["stringValue"] as? String, "Connected follow-up from reporter")
        XCTAssertEqual(message["senderId"]?["stringValue"] as? String, "feedback-audit-reporter")
        capture(app, "sdk-feedback-followup-confirmed")
        app.terminate()
    }

    private func login(_ suffix: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-sdk-ui-audit", "-selectedAppLanguage", "uk", "-selectedAppAppearance", "light",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launchEnvironment = ["UACFirebaseEmulators": "1"]
        app.launch()
        if app.tabBars.firstMatch.waitForExistence(timeout: 8) {
            app.tabBars.buttons.element(boundBy: 4).tap()
            // Guests also have tabs. Use a positive authenticated-profile control
            // before trying to sign out, instead of treating a tab bar as login proof.
            if app.buttons["profile.edit.open"].waitForExistence(timeout: 5) {
                let logout = app.buttons["profile.logout.button"]
                reveal(logout, app); logout.tap()
                let confirm = app.alerts.buttons["profile.logout.confirm"].firstMatch
                XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
            }
        }
        let signIn = app.buttons["auth.landing.signIn"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 20)); signIn.tap()
        let email = app.textFields["auth.login.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 8)); email.tap(); email.typeText("feedback-audit-" + suffix + "@uac.test")
        let password = app.secureTextFields["auth.login.password"]
        let focused = NSPredicate(format: "hasKeyboardFocus == true")
        for _ in 0..<3 {
            password.coordinate(withNormalizedOffset: .init(dx: 0.2, dy: 0.5)).tap()
            if XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: focused, object: password)], timeout: 2) == .completed { break }
        }
        XCTAssertTrue(focused.evaluate(with: password))
        password.typeText("Emulator-Only-2026!")
        app.swipeUp()
        let submit = app.buttons["auth.login.submit"]
        reveal(submit, app); submit.tap()
        XCTAssertTrue(submit.waitForNonExistence(timeout: 30))
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 30))
        let later = app.buttons["auth.passkeySuggestion.later"]
        if later.waitForExistence(timeout: 3) { later.tap() }
        return app
    }

    private var ownedFeedbackIDs = Set<String>()
    private func queryOwnFeedback(marker: String) async throws -> [[String: Any]] {
        let query: [String: Any] = ["structuredQuery": ["from": [["collectionId": "feedback"]], "where": ["compositeFilter": ["op": "AND", "filters": [
            ["fieldFilter": ["field": ["fieldPath": "userId"], "op": "EQUAL", "value": ["stringValue": "feedback-audit-reporter"]]],
            ["fieldFilter": ["field": ["fieldPath": "message"], "op": "EQUAL", "value": ["stringValue": marker]]]]]], "limit": 5]]
        let response = try await demoRequest(path: ":runQuery", body: query)
        let result = try XCTUnwrap(response as? [[String: Any]]).compactMap { $0["document"] as? [String: Any] }
        for record in result { if let name = record["name"] as? String, let id = name.split(separator: "/").last { ownedFeedbackIDs.insert(String(id)) } }
        return result
    }
    private func readOwnedMessages(feedbackID: String) async throws -> [String: Any] {
        guard ownedFeedbackIDs.contains(feedbackID), !feedbackID.contains("/") else { throw NSError(domain: "RefusingUnownedFeedbackRead", code: 1) }
        let response = try await demoRequest(path: "/feedback/" + feedbackID + "/messages")
        return try XCTUnwrap(response as? [String: Any])
    }
    private func demoRequest(path: String, body: [String: Any]? = nil) async throws -> Any {
        guard ProcessInfo.processInfo.environment["UACFirebaseEmulators"] == "1" else { throw NSError(domain: "RefusingNonLocalFeedbackUI", code: 1) }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:28080/v1/projects/demo-uac-release-audit/databases/(default)/documents" + path)!)
        request.setValue("Bearer owner", forHTTPHeaderField: "Authorization")
        if let body { request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        return try JSONSerialization.jsonObject(with: data)
    }
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<25 {
            if element.exists && element.isHittable { return }
            app.coordinate(withNormalizedOffset: .init(dx: 0.95, dy: 0.78)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: .init(dx: 0.95, dy: 0.3)))
        }
        XCTAssertTrue(element.exists, "Missing control: " + element.identifier + "\n" + app.debugDescription)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
