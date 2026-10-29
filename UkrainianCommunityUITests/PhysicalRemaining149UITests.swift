import XCTest

/// Production reads and disposable local drafts only. Never clicks save, publish,
/// scene activation or credential mutations.
@MainActor final class PhysicalRemaining149UITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
#if targetEnvironment(simulator)
        throw XCTSkip("Real device required")
#else
        guard ProcessInfo.processInfo.environment["UACPhysicalRemaining149"] == "1" else { throw XCTSkip("Explicit physical follow-up required") }
#endif
    }
    override func tearDown() {
        let app = XCUIApplication()
        let stop = app.buttons["seasonal.localPreview.stop"]
        if stop.exists && stop.isHittable { stop.tap() }
        XCUIDevice.shared.orientation = .portrait
        app.terminate(); app.launchArguments = []; app.launch()
        super.tearDown()
    }
    private func shot(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
    private func reveal(_ item: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<25 {
            if item.exists && item.isHittable && item.frame.midY > 140 && item.frame.midY < app.frame.height - 110 { return }
            if item.exists && item.frame.midY < 140 { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(item.exists && item.isHittable)
    }
    private func tab(_ id: String, labels: [String], _ app: XCUIApplication) -> XCUIElement {
        let value = app.tabBars.buttons.matching(NSPredicate(format: "identifier == %@ OR label IN %@", id, labels)).firstMatch
        XCTAssertTrue(value.waitForExistence(timeout: 20)); value.tap(); return value
    }
    private func back(_ app: XCUIApplication) {
        let b = app.buttons.matching(NSPredicate(format: "label IN %@", ["Назад", "Zurück", "Back"])).allElementsBoundByIndex.first { $0.isHittable && $0.frame.minY < 200 && $0.frame.minX < 100 }
        XCTAssertNotNil(b); b?.tap()
    }
    private func cancel(_ app: XCUIApplication) {
        let b = app.buttons.matching(NSPredicate(format: "label IN %@", ["Скасувати", "Abbrechen", "Cancel"])).allElementsBoundByIndex.first { $0.isHittable && $0.frame.minY < 200 }
        XCTAssertNotNil(b); b?.tap()
    }
    private func seasonal(_ app: XCUIApplication) {
        _ = tab("tab.profile", labels: ["Профіль", "Profil"], app)
        let entry = app.buttons["profile.seasonalManagement"]; reveal(entry, app); entry.tap()
        let toggle = app.buttons["seasonal.quick.uac.preset.halloween"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 25))
        let loaded = NSPredicate { _, _ in toggle.exists && toggle.isEnabled }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: loaded, object: nil)], timeout: 25), .completed)
    }
    func testSeasonalStatusDraftDiscardAndPrivatePreviewInBothAppearances() {
        let app = XCUIApplication()
        for (language, appearance) in [("uk", "light"), ("de", "dark")] {
            app.launchArguments = ["-selectedAppLanguage", language, "-selectedAppAppearance", appearance]; app.launch()
            seasonal(app)
            let status = app.staticTexts["seasonal.liveStatus.title"]
            XCTAssertTrue(status.waitForExistence(timeout: 15)); let originalStatus = status.label
            reveal(status, app); shot(app, "Physical149-Seasonal-Confirmed-" + language)
            XCTAssertFalse(app.buttons["seasonal.saveAndActivate"].exists)
            let edit = app.buttons["seasonal.quick.edit.uac.preset.halloween"]; reveal(edit, app); edit.tap()
            let name = app.textFields["seasonal.editor.name"]
            XCTAssertTrue(name.waitForExistence(timeout: 10)); reveal(name, app); name.tap(); name.typeText(" QA-local\n")
            app.buttons["seasonal.editor.apply"].tap()
            let apply = app.buttons["seasonal.saveAndActivate"]
            XCTAssertTrue(apply.waitForExistence(timeout: 10)); reveal(apply, app)
            XCTAssertTrue(apply.isEnabled); XCTAssertTrue(app.buttons["seasonal.saveLibrary"].isEnabled)
            XCTAssertEqual(status.label, originalStatus)
            shot(app, "Physical149-Seasonal-Local-Draft-Not-Published-" + language)
            back(app)
            let discard = app.sheets.buttons.matching(NSPredicate(format: "label IN %@", ["Відкинути зміни", "Änderungen verwerfen"])).firstMatch
            XCTAssertTrue(discard.waitForExistence(timeout: 10)); discard.tap()
            seasonal(app); XCTAssertFalse(app.buttons["seasonal.saveAndActivate"].exists)
            XCTAssertEqual(status.label, originalStatus)
            let preview = app.buttons["seasonal.quick.preview.uac.preset.halloween"]; reveal(preview, app); preview.tap()
            let stop = app.buttons["seasonal.localPreview.stop"]
            XCTAssertTrue(stop.waitForExistence(timeout: 10))
            _ = tab("tab.home", labels: ["Новини", "Nachrichten"], app)
            shot(app, "Physical149-Private-Halloween-Preview-" + language)
            seasonal(app)
            let end = app.buttons["seasonal.management.stopPreview"]
            XCTAssertTrue(end.waitForExistence(timeout: 10)); XCTAssertEqual(status.label, originalStatus)
            reveal(end, app); shot(app, "Physical149-Seasonal-Preview-Separate-" + language); end.tap()
            XCTAssertTrue(end.waitForNonExistence(timeout: 10)); XCTAssertEqual(status.label, originalStatus)
            let advanced = app.buttons["seasonal.advanced"]; reveal(advanced, app); advanced.tap()
            let addScene = app.buttons["seasonal.library.addScene"]; XCTAssertTrue(addScene.waitForExistence(timeout: 10)); reveal(addScene, app)
            shot(app, "Physical149-Seasonal-Library-" + language)
            let schedule = app.buttons["seasonal.publish"]; reveal(schedule, app)
            shot(app, "Physical149-Seasonal-Schedule-" + language)
            app.terminate()
        }
    }
    func testAppleMapsAddressResolvesAndEditedEventIsDiscarded() throws {
        let app = XCUIApplication(); app.launchArguments = ["-selectedAppLanguage", "uk"]; app.launch()
        _ = tab("tab.events", labels: ["Події", "Veranstaltungen"], app)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "event.card.")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 25)); let eventID = String(row.identifier.dropFirst("event.card.".count))
        reveal(row, app); row.tap()
        let menu = app.buttons["detail.header.more-actions"]; XCTAssertTrue(menu.waitForExistence(timeout: 25)); menu.tap()
        let edit = app.buttons["Редагувати"].firstMatch; XCTAssertTrue(edit.waitForExistence(timeout: 10)); XCTAssertTrue(edit.isHittable); edit.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()
        let title = app.textFields["editor.event.title"]
        shot(app, "Physical149-Event-After-Edit-Menu")
        if !title.waitForExistence(timeout: 8) {
            // A separately recorded human-assisted step, never an automatic pass.
            // Production calls retain their original bounded deadlines below.
            print("PHYSICAL_MANUAL_EVENT_EDIT_REQUIRED")
            shot(app, "Physical149-Native-Menu-Awaiting-Physical-Tap")
            XCTAssertTrue(title.waitForExistence(timeout: 180), "Physical selection of the native Edit menu is required; editor entry remains unverified without it")
        }
        let originalTitle = title.value as? String
        let next = app.buttons["editor.event.next"]; reveal(next, app); XCTAssertTrue(next.isEnabled); next.tap()
        let venue = app.textFields["editor.event.venue"], address = app.textFields["editor.event.address"], city = app.textFields["editor.event.city"]
        reveal(venue, app)
        let original: [String: String] = ["id": eventID, "title": originalTitle ?? "", "venue": venue.value as? String ?? "", "address": address.value as? String ?? "", "city": city.value as? String ?? ""]
        let a = XCTAttachment(string: String(data: try JSONSerialization.data(withJSONObject: original), encoding: .utf8)!); a.name = "Map-Original-Event-Fields"; a.lifetime = .keepAlways; add(a)
        let map = app.buttons["Вибрати на карті"].firstMatch; reveal(map, app); map.tap()
        let query = app.textFields["Пошук місця або адреси"].firstMatch; XCTAssertTrue(query.waitForExistence(timeout: 10))
        let clear = app.buttons["Очистити пошук"].firstMatch
        if clear.exists && clear.isHittable { clear.tap() }
        query.tap(); query.typeText("Stephansplatz Wien\n")
        let result = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Stephansplatz"))
        let ready = NSPredicate { _, _ in app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Stephansplatz")).allElementsBoundByIndex.contains { $0.isHittable && $0.frame.minY < 500 } }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 25), .completed)
        shot(app, "Physical149-Maps-Actual-Address-Results")
        let selected = try XCTUnwrap(result.allElementsBoundByIndex.first { $0.isHittable && $0.frame.minY < 500 }); selected.tap()
        let resolved = NSPredicate { _, _ in !app.activityIndicators.allElementsBoundByIndex.contains { $0.isHittable } }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: resolved, object: nil)], timeout: 25), .completed)
        let choose = app.buttons["Вибрати"].firstMatch; XCTAssertTrue(choose.waitForExistence(timeout: 10)); XCTAssertTrue(choose.isHittable); XCTAssertTrue(choose.isEnabled); choose.tap()
        XCTAssertTrue(venue.waitForExistence(timeout: 10)); reveal(venue, app)
        XCTAssertTrue((venue.value as? String ?? "").localizedCaseInsensitiveContains("Stephansplatz"))
        shot(app, "Physical149-Maps-Resolved-Into-Local-Editor-Only")
        cancel(app)
        let discard = app.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Відкинути зміни", "Відхилити зміни", "Änderungen verwerfen"])).firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 10)); discard.tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.otherElements["event.detail.loaded." + eventID].waitForExistence(timeout: 10))
        shot(app, "Physical149-Maps-Discarded-Back-To-Original-Event")
        // Verify original public content independently through server readback;
        // no save/submit control is part of this scenario.
    }
}
