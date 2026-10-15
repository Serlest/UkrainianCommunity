import XCTest

@MainActor
final class ForegroundNavigationUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testNewsDetailAndReadingPositionSurviveLegalReverification() {
        let app = launch()
        let card = app.buttons["home.card.news-news-1"].firstMatch
        reveal(card, in: app)
        card.tap()
        assertDetailSurvivesReturn(in: app, tabIndex: 0)
    }

    func testEventDetailAndReadingPositionSurviveLegalReverification() {
        let app = launch()
        app.tabBars.buttons.element(boundBy: 1).tap()
        let card = app.buttons["event.card.event-1"].firstMatch
        reveal(card, in: app)
        card.tap()
        assertDetailSurvivesReturn(in: app, tabIndex: 1)
    }

    func testConnectionFailureBlocksAccessThenReturnsToSameSettingsPosition() {
        let app = launch(scenario: "offline")
        app.tabBars.buttons.element(boundBy: 4).tap()
        let settings = app.buttons["profile.settings.open"].firstMatch
        reveal(settings, in: app)
        settings.tap()
        let toggle = app.switches["profile.settings.appLock"].firstMatch
        reveal(toggle, in: app)
        let originalY = toggle.frame.midY

        backgroundAndReturn(app)
        let retry = app.buttons["startup.retry"].firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        XCTAssertFalse(toggle.isHittable, "Settings must remain blocked while legal access is unverified")
        retry.tap()
        XCTAssertTrue(retry.waitForNonExistence(timeout: 10))
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        XCTAssertTrue(toggle.isHittable)
        XCTAssertEqual(toggle.frame.midY, originalY, accuracy: 3)
        XCTAssertTrue(app.tabBars.buttons.element(boundBy: 4).isSelected)
    }

    func testLegalVerificationCoversPresentedEditorAndPreservesDraft() {
        let app = launch(owner: true)
        let create = app.buttons["quickCreate.news"].firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 15))
        create.tap()
        let newDraft = app.buttons["Neu erstellen"].firstMatch
        if newDraft.waitForExistence(timeout: 2) { newDraft.tap() }
        let title = app.textFields["editor.news.title"].firstMatch
        reveal(title, in: app)
        title.tap()
        title.typeText("Preserved foreground draft")

        backgroundAndReturn(app)
        let verifying = app.otherElements["startup.access.verifying"].firstMatch
        XCTAssertTrue(verifying.waitForExistence(timeout: 5))
        XCTAssertFalse(title.exists, "A presented editor must not cover the legal access shield")
        XCTAssertTrue(verifying.waitForNonExistence(timeout: 10))
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.value as? String, "Preserved foreground draft")
    }

    func testUpdatedPrivacyMustBeReviewedAndAcceptedBeforeReturningToNews() {
        let app = launch(scenario: "updated")
        let card = app.buttons["home.card.news-news-1"].firstMatch
        reveal(card, in: app)
        card.tap()
        let back = app.buttons["navigation.back"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10))

        backgroundAndReturn(app)
        let accept = app.buttons["legal.required.accept"].firstMatch
        XCTAssertTrue(accept.waitForExistence(timeout: 10))
        XCTAssertFalse(accept.isEnabled)
        XCTAssertFalse(back.exists, "The underlying news must stay inaccessible until legal acceptance")
        app.buttons["legal.required.document.privacy"].tap()
        let reviewed = app.buttons["legal.document.reviewComplete"].firstMatch
        reveal(reviewed, in: app)
        reviewed.tap()
        XCTAssertTrue(accept.isEnabled)
        accept.tap()
        XCTAssertTrue(accept.waitForNonExistence(timeout: 15))
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons.element(boundBy: 0).isSelected)
    }

    private func launch(scenario: String = "success", owner: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launchEnvironment = [
            owner ? "UITestForceOwnerSession" : "UITestForceAuthenticatedSession": "1",
            "UITestResetUserSettings": "1", "UITestAppLanguage": "de",
            "UITestLegalReverification": scenario, "UITestAppLockScenario": "success",
            "UITestResetAppLock": "1", "UITestResetContentDrafts": "1",
        ]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20))
        return app
    }

    private func assertDetailSurvivesReturn(in app: XCUIApplication, tabIndex: Int) {
        let back = app.buttons["navigation.back"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        app.swipeUp()
        let anchor = app.staticTexts.allElementsBoundByIndex.first {
            $0.isHittable && $0.label.count > 4
                && $0.frame.minY > 130 && $0.frame.maxY < app.frame.height - 130
        }
        XCTAssertNotNil(anchor, "The detail must expose a reading-position anchor")
        guard let anchor else { return }
        let label = anchor.label
        let originalY = anchor.frame.midY

        backgroundAndReturn(app)
        let verifying = app.otherElements["startup.access.verifying"].firstMatch
        XCTAssertTrue(verifying.waitForExistence(timeout: 5))
        XCTAssertFalse(back.exists)
        XCTAssertTrue(verifying.waitForNonExistence(timeout: 10))
        XCTAssertTrue(back.waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons.element(boundBy: tabIndex).isSelected)
        let retainedAnchor = app.staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch
        XCTAssertTrue(retainedAnchor.isHittable)
        XCTAssertEqual(retainedAnchor.frame.midY, originalY, accuracy: 3)
    }

    private func backgroundAndReturn(_ app: XCUIApplication) {
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        app.activate()
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 15))
        for _ in 0..<16 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }
}
