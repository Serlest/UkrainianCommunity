import XCTest
final class LegalAudit18VisualUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    @MainActor private func launch(_ language:String, largest:Bool = true)->XCUIApplication {
        let app=XCUIApplication(); app.launchArguments = largest ? ["-ui-testing","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"] : ["-ui-testing"]
        app.launchEnvironment=["UITestForceOwnerSession":"1","UITestResetUserSettings":"1","UITestResetAppLock":"1","UITestFeedbackInbox":"1","UITestLegalEvidence":"1","UITestUserRefresh":"1","UITestAppLanguage":language,"UITestAppAppearance":language == "uk" ? "light":"dark"]
        app.launch(); let profile=app.tabBars.buttons.element(boundBy:4);XCTAssertTrue(profile.waitForExistence(timeout:20));profile.tap();return app
    }
    @MainActor private func reach(_ item:XCUIElement,_ app:XCUIApplication) {
        for _ in 0..<45 {
            let editorBar = app.buttons["legal.edit.save"]
            let editorVisible = editorBar.exists && editorBar.isHittable
            var lowerEdge = app.frame.height - 28
            if editorVisible { lowerEdge = editorBar.frame.minY - 8 }
            else if app.tabBars.firstMatch.exists && app.tabBars.firstMatch.isHittable { lowerEdge = app.tabBars.firstMatch.frame.minY - 8 }
            if item.exists && item.isHittable && item.frame.midY > 90 && item.frame.midY < lowerEdge { return }
            let down = item.exists && item.frame.midY < 90
            let bottom: CGFloat = editorVisible ? 0.55 : 0.8
            app.coordinate(withNormalizedOffset: CGVector(dx:0.04,dy:down ? 0.25:bottom)).press(forDuration:0.05,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.04,dy:down ? bottom:0.25)),withVelocity:.slow,thenHoldForDuration:0.15)
        };capture(app,"unreachable-control");let tree=XCTAttachment(string:app.debugDescription);tree.name="audit18-unreachable-tree";tree.lifetime = .keepAlways;add(tree);XCTFail("Unreachable: \(item)")
    }
    @MainActor private func capture(_ app:XCUIApplication,_ name:String){let a=XCTAttachment(screenshot:app.screenshot());a.name="audit18-"+name;a.lifetime = .keepAlways;add(a)}
    @MainActor private func back(_ app:XCUIApplication){let button=app.buttons["navigation.back"].firstMatch;XCTAssertTrue(button.waitForExistence(timeout:5));button.tap()}
    @MainActor func testLargestManagementCurrentReaderEditorAndPreview() {
        for lang in [ProcessInfo.processInfo.environment["LegalVisualLanguage"] ?? "uk"] {
            let app=launch(lang);let entry=app.buttons["profile.owner.legalDocuments"];reach(entry,app);entry.tap()
            let active=app.buttons["legal.manage.active.privacy"];reach(active,app);capture(app,lang+"-management-max");active.tap()
            let picker=app.segmentedControls.firstMatch;XCTAssertTrue(picker.waitForExistence(timeout:8));capture(app,lang+"-current-reader-max");picker.buttons.element(boundBy:1).tap();capture(app,lang+"-current-reader-uk-max");back(app)
            let edit=app.buttons["legal.manage.edit.privacy"];reach(edit,app);edit.tap();XCTAssertTrue(app.buttons["legal.edit.save"].waitForExistence(timeout:5));capture(app,lang+"-editor-top-max")
            let body=app.descendants(matching:.any).matching(identifier:"legal.edit.body").firstMatch;reach(body,app);capture(app,lang+"-editor-body-max")
            app.buttons["legal.edit.actions"].tap();let preview=app.buttons[lang == "uk" ? "Попередній перегляд":"Vorschau"].firstMatch;XCTAssertTrue(preview.waitForExistence(timeout:5));capture(app,lang+"-editor-actions-max");preview.tap();let done=app.buttons[lang == "uk" ? "Готово":"Fertig"].firstMatch;XCTAssertTrue(done.waitForExistence(timeout:5));capture(app,lang+"-preview-max");done.tap();XCTAssertTrue(app.buttons["legal.edit.save"].waitForExistence(timeout:5));app.terminate()
        }
    }
    @MainActor func testLargestEvidenceAccountRecordedVersionAndFilter() {
        for lang in [ProcessInfo.processInfo.environment["LegalVisualLanguage"] ?? "uk"] {
            let app=launch(lang);let entry=app.buttons["profile.owner.legalEvidence"];reach(entry,app);entry.tap();let account=app.buttons["legalEvidence.account.legal-fixture"];reach(account,app);capture(app,lang+"-accounts-max");account.tap()
            let reader=app.buttons["legalEvidence.readVersion.fixture-terms"];reach(reader,app);capture(app,lang+"-receipt-card-max");reader.tap();XCTAssertTrue(app.otherElements["screen.legalEvidence.version"].waitForExistence(timeout:8));capture(app,lang+"-recorded-reader-max");back(app)
            let filter=app.buttons["legalEvidence.filter"];reach(filter,app);capture(app,lang+"-filter-row-max");filter.tap();capture(app,lang+"-filter-menu-max");app.terminate()
        }
    }
}

extension LegalAudit18VisualUITests {
    @MainActor func testLargestKeyboardSaveAndReopen() {
        let lang = ProcessInfo.processInfo.environment["LegalVisualLanguage"] ?? "uk"
        let app = launch(lang)
        let entry = app.buttons["profile.owner.legalDocuments"]; reach(entry, app); entry.tap()
        let edit = app.buttons["legal.manage.edit.terms"]; reach(edit, app); edit.tap()
        for (locale, text) in [("de", "Isolierter Tastaturtest"), ("uk", "Ізольована перевірка введення")] {
            let summary = app.textFields["legal.edit.summary." + locale]; reach(summary, app); summary.tap(); XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5)); summary.typeText(text)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.35)).tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        }
        let body = app.textViews["legal.edit.body"]; reach(body, app)
        body.tap(); XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        body.typeText("\n\nLEGAL18 keyboard persistence")
        capture(app, lang + "-body-keyboard-max")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.35)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        let save = app.buttons["legal.edit.save"]; XCTAssertTrue(save.isEnabled); save.tap()
        expectation(for: NSPredicate(format: "enabled == false"), evaluatedWith: save)
        waitForExpectations(timeout: 10)
        back(app); reach(edit, app); edit.tap(); reach(body, app)
        XCTAssertTrue((body.value as? String ?? "").contains("LEGAL18 keyboard persistence"))
        capture(app, lang + "-saved-body-reopened-max")
        app.buttons["legal.edit.actions"].tap()
        let publish = app.buttons["legal.edit.publish"]
        XCTAssertTrue(publish.waitForExistence(timeout: 5)); publish.tap()
        let confirm = app.buttons["legal.edit.confirmPublish"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); reach(confirm, app)
        capture(app, lang + "-publish-confirm-max")
        let cancel = app.buttons[lang == "uk" ? "Скасувати" : "Abbrechen"].firstMatch; XCTAssertTrue(cancel.isHittable); cancel.tap()
        XCTAssertTrue(save.waitForExistence(timeout: 5)); XCTAssertFalse(save.isEnabled)
        back(app); back(app)
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
    }
}

extension LegalAudit18VisualUITests {
    @MainActor func testTranslationReviewAndPublishedHistoryInIsolatedRepository() {
        let app = launch("uk", largest: false)
        let entry = app.buttons["profile.owner.legalDocuments"]; reach(entry, app); entry.tap()
        let activeVersion = app.descendants(matching: .any).matching(identifier: "legal.manage.version.terms").firstMatch
        reach(activeVersion, app)
        let oldVersion = activeVersion.label.components(separatedBy: " ").last!
        let edit = app.buttons["legal.manage.edit.terms"]; reach(edit, app); edit.tap()
        for (locale, text) in [("de", "Isolierter Versionsvergleich"), ("uk", "Ізольоване порівняння версій")] {
            let summary = app.textFields["legal.edit.summary." + locale]; reach(summary, app); summary.tap(); XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5)); summary.typeText(text)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.35)).tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        }
        let translate = app.buttons["translation.legal"]; reach(translate, app); translate.tap()
        let apply = app.buttons["translation.apply"]; XCTAssertTrue(apply.waitForExistence(timeout: 8))
        XCTAssertFalse(apply.isEnabled); capture(app, "translation-review-before-confirmation")
        let original = app.descendants(matching: .any).matching(identifier: "translation.source.toggle.markdown").firstMatch; reach(original, app); original.tap()
        XCTAssertTrue(app.staticTexts["translation.source.body.markdown"].exists)
        original.tap(); XCTAssertFalse(app.staticTexts["translation.source.body.markdown"].exists)
        let cancel = app.buttons["Скасувати"].firstMatch; XCTAssertTrue(cancel.isHittable); cancel.tap()
        reach(translate, app); translate.tap(); XCTAssertTrue(apply.waitForExistence(timeout: 8))
        let confirm = app.switches["translation.confirm"]; reach(confirm, app); confirm.tap()
        reach(apply, app); XCTAssertTrue(apply.isEnabled); apply.tap()
        let picker = app.segmentedControls.firstMatch; reach(picker, app); picker.buttons.element(boundBy: 1).tap()
        let title = app.textFields["legal.edit.title"]; reach(title, app)
        XCTAssertTrue((title.value as? String ?? "").hasPrefix("UK: "))
        title.tap(); title.typeText(" Audit18")
        XCTAssertTrue((title.value as? String ?? "").contains("Audit18"))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.35)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        let save = app.buttons["legal.edit.save"]; save.tap()
        expectation(for: NSPredicate(format: "enabled == false"), evaluatedWith: save); waitForExpectations(timeout: 10)
        app.buttons["legal.edit.actions"].tap(); app.buttons["legal.edit.publish"].tap()
        let publish = app.buttons["legal.edit.confirmPublish"]; XCTAssertTrue(publish.waitForExistence(timeout: 5)); reach(publish, app)
        capture(app, "isolated-publication-confirmation"); publish.tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        let history = app.buttons["legal.manage.history.terms"]; reach(history, app); history.tap()
        let read = app.buttons["legal.history.read." + oldVersion]; reach(read, app); read.tap()
        XCTAssertTrue(app.segmentedControls.firstMatch.waitForExistence(timeout: 5)); capture(app, "history-original-version"); back(app)
        let compare = app.buttons["legal.history.compare." + oldVersion]; reach(compare, app); compare.tap()
        XCTAssertTrue(app.staticTexts["Видалено"].firstMatch.waitForExistence(timeout: 5)); capture(app, "history-published-difference")
        let comparisonLanguage = app.segmentedControls.firstMatch
        comparisonLanguage.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["Текст не змінився."].waitForExistence(timeout: 5))
        back(app); back(app); back(app)
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 5))
    }
}
