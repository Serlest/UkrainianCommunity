import XCTest

final class DirectoryArticleEditorUITests: XCTestCase {
    @MainActor
    func testExistingSectionDeletionDoesNotNavigateIntoTheSection() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launchEnvironment["UITestResetUserSettings"] = "1"
        app.launchEnvironment["UITestAppLanguage"] = "uk"
        app.launchEnvironment["UITestForceOwnerSession"] = "1"
        app.launch()
        let tab = app.tabBars.buttons.element(boundBy: 3)
        XCTAssertTrue(tab.waitForExistence(timeout: 15)); tab.tap()
        let manage = app.buttons["directory.manage"]
        reveal(manage, app); manage.tap()
        let category = app.buttons["directory.category.manage.first-steps"]
        XCTAssertTrue(category.waitForExistence(timeout: 8)); category.tap()
        let topic = app.buttons["directory.topic.edit.arrival"]
        reveal(topic, app); topic.tap()
        let deletion = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "directory.section.delete.")).firstMatch
        reveal(deletion, app)
        let deletedID = deletion.identifier
        deletion.tap()
        let confirm = app.buttons["directory.section.confirmDelete"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        let cancel = app.alerts.buttons["directory.section.cancelDelete"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5)); cancel.tap()
        XCTAssertTrue(app.buttons[deletedID].exists, "Cancel must preserve the section")
        app.buttons[deletedID].firstMatch.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(app.navigationBars["Стаття"].waitForExistence(timeout: 5), "Deleting must not open the section editor")
        XCTAssertFalse(app.buttons[deletedID].exists, "Confirmed section must disappear from the draft")
        app.navigationBars["Стаття"].buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["directory.category.publish"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["directory.category.publish"].isEnabled)
        reveal(topic, app); topic.tap()
        let remaining = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "directory.section.delete.")).firstMatch
        reveal(remaining, app)
        XCTAssertNotEqual(remaining.identifier, deletedID)
        XCTAssertFalse(app.buttons[deletedID].exists, "Reopening the article must preserve the draft deletion")
        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = "existing-section-deleted-after-reopening"; proof.lifetime = .keepAlways; add(proof)
    }

    @MainActor
    func testExistingRegionalSectionDeletionPersistsWhenReopened() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launchEnvironment["UITestResetUserSettings"] = "1"
        app.launchEnvironment["UITestAppLanguage"] = "uk"
        app.launchEnvironment["UITestForceOwnerSession"] = "1"
        app.launch()
        let tab = app.tabBars.buttons.element(boundBy: 3)
        XCTAssertTrue(tab.waitForExistence(timeout: 15)); tab.tap()
        let manage = app.buttons["directory.manage"]
        reveal(manage, app); manage.tap()
        let category = app.buttons["directory.category.manage.first-steps"]
        XCTAssertTrue(category.waitForExistence(timeout: 8)); category.tap()
        let topic = app.buttons["directory.topic.edit.arrival"]
        reveal(topic, app); topic.tap()
        let region = app.buttons["directory.region.edit.wien"]
        reveal(region, app); region.tap()
        let deletion = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "directory.region.section.delete.")).firstMatch
        reveal(deletion, app)
        let deletedID = deletion.identifier
        deletion.tap()
        let confirm = app.buttons["directory.region.section.confirmDelete"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertFalse(app.buttons[deletedID].exists)
        app.navigationBars.buttons.firstMatch.tap()
        reveal(region, app); region.tap()
        XCTAssertFalse(app.buttons[deletedID].exists, "Regional deletion must survive reopening")
        XCTAssertTrue(app.buttons["Додати блок"].exists)
        let proof = XCTAttachment(screenshot: app.screenshot())
        proof.name = "regional-section-deleted-after-reopening"; proof.lifetime = .keepAlways; add(proof)
    }

    @MainActor
    func testArticleTranslationAndSpecificSourceValidation() throws {
        try addArticle(sourceURL: "serlest.com/path?x=1")
    }

    @MainActor
    func testArticleAcceptsHTTPSourceWithPathAndQuery() throws {
        try addArticle(sourceURL: "http://serlest.com/path?x=1")
    }

    @MainActor
    private func addArticle(sourceURL: String) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launchEnvironment["UITestResetUserSettings"] = "1"
        app.launchEnvironment["UITestAppLanguage"] = "uk"
        app.launchEnvironment["UITestForceOwnerSession"] = "1"
        app.launch()
        let tab = app.tabBars.buttons.element(boundBy: 3)
        XCTAssertTrue(tab.waitForExistence(timeout: 15)); tab.tap()
        let manage = app.buttons["directory.manage"]
        reveal(manage, app); manage.tap()
        let category = app.buttons["directory.category.manage.first-steps"]
        XCTAssertTrue(category.waitForExistence(timeout: 8)); category.tap()
        let add = app.buttons["Додати статтю сюди"].firstMatch
        reveal(add, app); add.tap()
        let title = app.textFields["directory.field.articleTitle.uk"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap(); title.typeText("Нова стаття")
        let intro = app.textViews["directory.field.articleSummary.uk"]
        reveal(intro, app); intro.tap(); intro.typeText("Вступ до статті")
        let heading = app.textFields["directory.field.sectionTitle.uk"]
        reveal(heading, app); heading.tap(); heading.typeText("Інформація")
        let body = app.textViews["directory.field.sectionBody.uk"]
        reveal(body, app); body.tap(); body.typeText("Детальні кроки")
        for _ in 0..<8 {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48)))
        }
        let translate = app.buttons["translation.directory"]
        XCTAssertTrue(translate.waitForExistence(timeout: 5))
        reveal(translate, app); translate.tap()
        let result = app.textViews["translation.result.articleTitle"]
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        XCTAssertTrue((result.value as? String)?.contains("DE: Нова стаття") == true)
        let apply = app.buttons["translation.apply"]
        reveal(apply, app); apply.tap()
        let name = app.textFields["directory.source.name"]
        reveal(name, app); name.tap(); name.typeText("Amt")
        let url = app.textFields["directory.source.url"]
        let invalidSource = "javascript:alert(1)"
        reveal(url, app); url.tap(); url.typeText(invalidSource)
        app.buttons["Додати"].firstMatch.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.alerts.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "HTTPS")).firstMatch.exists)
        app.alerts.buttons["Гаразд"].tap()
        url.tap()
        // Clear through the keyboard rather than editing the app's model.
        url.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: invalidSource.count))
        url.typeText(sourceURL)
        app.buttons["Додати"].firstMatch.tap()
        XCTAssertFalse(app.navigationBars["Нова стаття"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["directory.category.publish"].exists)
    }

    @MainActor
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22)))
        }
        XCTAssertTrue(element.exists)
    }
}
