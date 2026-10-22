import XCTest

@MainActor
final class SystemLogDiagnosisUITests: XCTestCase {
    func testJournalShowsRealActionImpactAndDiagnosticFieldsInBothLanguages() {
        for language in ["uk", "de"] {
            for kind in ["analytics", "banner"] {
                let app = XCUIApplication()
                app.launchArguments = ["-ui-testing"]
                app.launchEnvironment = ["UITestSystemLogDiagnosis": "1", "UITestForceOwnerSession": "1",
                    "UITestAppLanguage": language, "UITestAppAppearance": language == "uk" ? "light" : "dark"]
                app.launch()
                let row = app.buttons["systemLogs.log." + kind].firstMatch
                XCTAssertTrue(row.waitForExistence(timeout: 15))
                for _ in 0..<10 { if row.isHittable { break }; app.swipeUp() }
                XCTAssertTrue(row.isHittable)
                row.tap()
                let action = kind == "analytics"
                    ? (language == "uk" ? "Фонова передача аналітики" : "Analyse im Hintergrund übermitteln")
                    : (language == "uk" ? "Завантаження налаштувань банера для керування" : "Bannereinstellungen für die Verwaltung laden")
                XCTAssertTrue(app.staticTexts[action].firstMatch.waitForExistence(timeout: 8))
                let impact = app.staticTexts[language == "uk" ? "Вплив на користувача" : "Auswirkung für die Person"].firstMatch
                for _ in 0..<6 { if impact.isHittable { break }; app.swipeUp() }
                XCTAssertTrue(impact.exists)
                let field = kind == "analytics"
                    ? (language == "uk" ? "Тип аналітичного сигналу" : "Art des Analysesignals")
                    : (language == "uk" ? "Проблемне поле" : "Betroffenes Feld")
                let detail = app.staticTexts[field].firstMatch
                for _ in 0..<6 { if detail.isHittable { break }; app.swipeUp() }
                XCTAssertTrue(detail.exists)
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = "system-log-\(kind)-\(language)"; screenshot.lifetime = .keepAlways; add(screenshot)
                app.terminate()
            }
        }
    }
}
