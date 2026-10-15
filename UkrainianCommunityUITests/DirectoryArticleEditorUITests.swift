import XCTest

final class DirectoryArticleEditorUITests: XCTestCase {
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
