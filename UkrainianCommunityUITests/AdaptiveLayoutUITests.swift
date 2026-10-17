import XCTest

/// iPhone/iPad resizing coverage also used as the baseline before Duo runtime testing.
@MainActor
final class AdaptiveLayoutUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    override func tearDownWithError() throws { XCUIDevice.shared.orientation = .portrait }

    func testDirectoryDraftSurvivesOrientationChange() {
        let app = launch(language: "uk", largeText: false)
        tapTab("directory", app: app)
        let manage = app.buttons["directory.manage"].firstMatch
        reveal(manage, app: app); manage.tap()
        let category = app.buttons["directory.category.manage.first-steps"].firstMatch
        reveal(category, app: app); category.tap()
        let topic = app.buttons["directory.topic.edit.arrival"].firstMatch
        reveal(topic, app: app); topic.tap()
        let title = app.textFields["directory.field.articleTitle.uk"].firstMatch
        reveal(title, app: app); title.tap()
        title.typeText(" UACDRAFT4827")
        let expected = title.value as? String
        XCTAssertTrue(expected?.contains("UACDRAFT4827") == true)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        XCTAssertEqual(title.value as? String, expected)
        capture("draft-landscape", app: app)
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        XCTAssertEqual(title.value as? String, expected)
        capture("draft-portrait", app: app)
    }

    func testDuoOpenClosePreservesDirectoryDraft() throws {
        let flag = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EnableUACDuoManualAudit")
        guard ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] == "iPhone19,4",
              FileManager.default.fileExists(atPath: flag.path) else {
            throw XCTSkip("Opt-in Duo audit: requires Device Hub operator and EnableUACDuoManualAudit in runner Documents")
        }
        let app = launch(language: "uk", largeText: false)
        tapTab("directory", app: app)
        let manage = app.buttons["directory.manage"].firstMatch
        reveal(manage, app: app); manage.tap()
        let category = app.buttons["directory.category.manage.first-steps"].firstMatch
        reveal(category, app: app); category.tap()
        let topic = app.buttons["directory.topic.edit.arrival"].firstMatch
        reveal(topic, app: app); topic.tap()
        let title = app.textFields["directory.field.articleTitle.uk"].firstMatch
        reveal(title, app: app); title.tap()
        title.typeText(" UACDUO4827")
        let expected = title.value as? String
        XCTAssertTrue(expected?.contains("UACDUO4827") == true)
        let closedSize = app.windows.firstMatch.frame.size
        capture("duo-draft-closed", app: app)
        print("DUO_READY_FOR_OPEN")
        waitForSizeChange(app: app, original: closedSize, larger: true)
        XCTAssertEqual(title.value as? String, expected)
        capture("duo-draft-open", app: app)
        print("DUO_READY_FOR_PARTIAL_THEN_CLOSE")
        waitForSizeChange(app: app, original: closedSize, larger: false)
        XCTAssertEqual(title.value as? String, expected)
        capture("duo-draft-closed-again", app: app)
        print("DUO_READY_FOR_SECOND_OPEN")
        waitForSizeChange(app: app, original: closedSize, larger: true)
        XCTAssertEqual(title.value as? String, expected)
        capture("duo-draft-open-again", app: app)
    }

    private func waitForSizeChange(app: XCUIApplication, original: CGSize, larger: Bool) {
        let predicate = NSPredicate { _, _ in
            let size = app.windows.firstMatch.frame.size
            let expanded = size.width * size.height > original.width * original.height * 1.2
            return larger ? expanded : !expanded
        }
        let ready = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 120), .completed)
    }

    private func launch(language: String, largeText: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launchEnvironment = ["UITestForceOwnerSession": "1", "UITestResetUserSettings": "1",
            "UITestAppLanguage": language, "UITestDirectoryRecentEmpty": "1",
            "UITestResetAppLock": "1", "UITestResetContentDrafts": "1"]
        app.launch()
        return app
    }

    private func tapTab(_ name: String, app: XCUIApplication) {
        let identified = app.descendants(matching: .any).matching(identifier: "tab.\(name)").firstMatch
        if identified.waitForExistence(timeout: 2) {
            identified.tap()
            return
        }
        // iOS 27 native tab controls can omit the SwiftUI label's identifier.
        let names = ["directory": ["Довідник", "Ratgeber"], "home": ["Новини", "Nachrichten"],
                     "events": ["Події", "Termine"], "organizations": ["Організації", "Organisation"],
                     "profile": ["Профіль", "Profil"]]
        let fallback = app.tabBars.buttons.matching(NSPredicate(format: "label IN %@", names[name] ?? [])).firstMatch
        XCTAssertTrue(fallback.waitForExistence(timeout: 12)); fallback.tap()
    }

    private func reveal(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<24 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
