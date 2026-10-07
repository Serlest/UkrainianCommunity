import XCTest

final class RootTabHeaderAlignmentUITests: XCTestCase {
    @MainActor
    func testBrandHeaderKeepsSameVerticalPositionAcrossTabs() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launchEnvironment["UITestResetUserSettings"] = "1"
        app.launchEnvironment["UITestAppLanguage"] = "de"
        app.launchEnvironment["UITestForceGuestSession"] = "1"
        app.launch()

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 20))
        let brand = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Ukrainian Community"))
            .firstMatch
        XCTAssertTrue(brand.waitForExistence(timeout: 20))
        let newsTop = brand.frame.minY

        for (index, name) in ["Veranstaltungen", "Organisationen", "Profil"].enumerated() {
            tabBar.coordinate(withNormalizedOffset: CGVector(dx: (CGFloat(index) + 1.5) / 4, dy: 0.5)).tap()
            XCTAssertTrue(brand.waitForExistence(timeout: 10), "Missing brand header on \(name)")
            XCTAssertEqual(brand.frame.minY, newsTop, accuracy: 2, "Header offset on \(name)")
        }
    }
}
