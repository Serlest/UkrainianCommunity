import XCTest

@MainActor
final class SystemAccessibilityAuditUITests: XCTestCase {
    func testSystemAccessibilityVariantsReachTheAppInBothThemes() throws {
        guard ProcessInfo.processInfo.environment["UACSystemAccessibilityAudit"] == "1" else {
            throw XCTSkip("Opt in to changing and restoring this simulator's actual system accessibility settings")
        }
        continueAfterFailure = true
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        settings.launch()
        guard open("Accessibility", in: settings), open("Display & Text Size", in: settings) else { return }
        let transparency = systemSwitch("Reduce Transparency", in: settings)
        let contrast = systemSwitch("Increase Contrast", in: settings)
        guard transparency.waitForExistence(timeout: 8), contrast.exists else {
            diagnose(settings); XCTFail("Missing display accessibility switches"); return
        }
        guard let oldTransparency = isOn(transparency), let oldContrast = isOn(contrast) else {
            diagnose(settings); XCTFail("Cannot read accessibility switch states"); return
        }
        set(transparency, enabled: true); set(contrast, enabled: true)
        XCTAssertEqual(isOn(transparency), true); XCTAssertEqual(isOn(contrast), true)
        capture(settings, "system-transparency-contrast-on")
        defer {
            settings.activate()
            let back = settings.navigationBars.buttons["Accessibility"].firstMatch
            if back.exists { back.tap() }
            if open("Display & Text Size", in: settings) {
                restore(transparency, value: oldTransparency)
                restore(contrast, value: oldContrast)
            }
        }
        let back = settings.navigationBars.buttons["Accessibility"].firstMatch
        guard back.exists else { diagnose(settings); XCTFail("Missing Accessibility back action"); return }
        back.tap()
        guard open("Motion", in: settings) else { return }
        let motion = systemSwitch("Reduce Motion", in: settings)
        guard motion.waitForExistence(timeout: 8) else { diagnose(settings); XCTFail("Missing Reduce Motion"); return }
        guard let oldMotion = isOn(motion) else { diagnose(settings); XCTFail("Cannot read Reduce Motion"); return }
        set(motion, enabled: true); XCTAssertEqual(isOn(motion), true)
        defer { settings.activate(); restore(motion, value: oldMotion) }
        capture(settings, "system-reduce-motion-on")
        let app = XCUIApplication()
        for appearance in ["light", "dark"] {
            app.launchArguments = ["-ui-testing", "-selectedAppAppearance", appearance,
                                   "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
            app.launchEnvironment = ["UACFirebaseEmulators": "1", "UITestForceAuthenticatedSession": "1",
                                     "UITestSystemAccessibilityProbe": "1", "UITestResetAppLock": "1", "UITestAppLanguage": "uk"]
            app.launch()
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 25))
            let probe = app.descendants(matching: .any).matching(identifier: "audit.accessibilityProbe").firstMatch
            XCTAssertTrue(probe.waitForExistence(timeout: 5))
            XCTAssertEqual(probe.value as? String, "motion=1;transparency=1;contrast=1")
            capture(app, "accessibility-root-" + appearance)
            let toggle = app.buttons["header.search.toggle"].firstMatch
            XCTAssertTrue(toggle.waitForExistence(timeout: 5)); toggle.tap()
            XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5))
            capture(app, "accessibility-search-" + appearance)
            toggle.tap()
            let card = app.buttons["home.card.news-news-1"].firstMatch
            for _ in 0..<8 { if card.exists && card.isHittable { break }; app.swipeUp() }
            XCTAssertTrue(card.exists); if card.exists { card.tap() }
            let back = app.buttons["navigation.back"].firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 5)); settle(back)
            capture(app, "accessibility-detail-" + appearance)
            back.tap()
            app.tabBars.buttons.element(boundBy: 4).tap()
            let edit = app.buttons["profile.edit.open"]
            XCTAssertTrue(edit.waitForExistence(timeout: 5)); edit.tap()
            let field = app.textFields["profile.edit.displayName"]
            XCTAssertTrue(field.waitForExistence(timeout: 8)); settle(field)
            capture(app, "accessibility-editor-" + appearance)
            app.terminate()
        }
    }

    private func settle(_ element: XCUIElement) {
        var previous: CGRect?
        var stableSince = Date()
        let predicate = NSPredicate { _, _ in
            let current = element.frame
            if previous != current { stableSince = Date() }
            previous = current
            return Date().timeIntervalSince(stableSince) >= 0.5
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 5), .completed)
    }

    private func open(_ label: String, in app: XCUIApplication) -> Bool {
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
        for _ in 0..<10 { if row.exists && row.isHittable { row.tap(); return true }; app.swipeUp() }
        diagnose(app); XCTFail("Missing Settings row: " + label); return false
    }
    private func systemSwitch(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.switches.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
    }
    private func isOn(_ element: XCUIElement) -> Bool? {
        if let value = element.value as? NSNumber { return value.boolValue }
        if let value = element.value as? String {
            if ["1", "true", "on"].contains(value.lowercased()) { return true }
            if ["0", "false", "off"].contains(value.lowercased()) { return false }
        }
        return nil
    }
    private func set(_ element: XCUIElement, enabled: Bool) {
        if isOn(element) != enabled {
            // Settings exposes the whole row as a switch. Tap its actual thumb,
            // not the center of a noninteractive text label.
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        }
    }
    private func restore(_ element: XCUIElement, value: Bool) {
        if element.exists { set(element, enabled: value); XCTAssertEqual(isOn(element), value) }
    }
    private func diagnose(_ app: XCUIApplication) {
        let tree = XCTAttachment(string: app.debugDescription); tree.name = "system-settings-tree"; tree.lifetime = .keepAlways; add(tree)
        capture(app, "system-settings-diagnostic")
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
