import XCTest

@MainActor final class UserDirectoryUITests: XCTestCase {
    func testGlobalFilterFindsUserBeyondFirstPageAndOpensCardInBothLanguages() {
        for language in ["uk", "de"] {
            let app = XCUIApplication()
            app.launchArguments = ["-ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]
            app.launchEnvironment = ["UITestForceOwnerSession":"1", "UITestUserRefresh":"1", "UITestUserRegionFilter":"1", "UITestUserDirectory":"1", "UITestAppLanguage":language, "UITestAppAppearance":language == "de" ? "dark":"light", "UITestResetUserSettings":"1"]
            app.launch();XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout:20));app.tabBars.buttons.element(boundBy:4).tap()
            let users=app.buttons["profile.userManagement"].firstMatch
            scroll(users,app:app);XCTAssertTrue(users.isHittable);users.tap()
            XCTAssertFalse(app.tabBars.firstMatch.isHittable)
            let menu=app.buttons["userManagement.filter"].firstMatch
            XCTAssertTrue(menu.waitForExistence(timeout:10));scroll(menu,app:app);menu.tap()
            let banned=app.buttons[language == "uk" ? "Заблоковані":"Gesperrt"].firstMatch
            XCTAssertTrue(banned.waitForExistence(timeout:5));banned.tap()
            let row=app.descendants(matching:.any)["userManagement.user.region-44"].firstMatch
            scroll(row,app:app);XCTAssertTrue(row.waitForExistence(timeout:10));row.tap()
            let presence=app.descendants(matching:.any)["user.presence.section"].firstMatch
            scroll(presence,app:app);XCTAssertTrue(presence.waitForExistence(timeout:10))
            let shot=XCTAttachment(screenshot:app.screenshot());shot.name="user-directory-"+language;shot.lifetime = .keepAlways;add(shot);app.terminate()
        }
    }
    private func scroll(_ element:XCUIElement,app:XCUIApplication) {
        for _ in 0..<14 { if element.exists && element.isHittable { return };app.swipeUp() }
    }
}
