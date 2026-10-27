import XCTest
final class Support19VisualAuditUITests: XCTestCase {
    override func setUp() { continueAfterFailure=false }
    @MainActor private func capture(_ app:XCUIApplication,_ name:String){let a=XCTAttachment(screenshot:app.screenshot());a.name="support19-"+name;a.lifetime = .keepAlways;add(a)}
    @MainActor private func reach(_ e:XCUIElement,_ app:XCUIApplication){
        for _ in 0..<48 {
            let save=app.buttons["donation.edit.save"]
            let bottom=save.exists && save.isHittable ? save.frame.minY-8 : app.frame.height-95
            if e.exists && e.isHittable && e.frame.midY>110 && e.frame.midY<bottom{return}
            let up=e.exists && e.frame.midY<110
            let upper:CGFloat = 0.23
            let lower=max(upper+0.08,min(0.72,(bottom-16)/app.frame.height))
            app.coordinate(withNormalizedOffset:CGVector(dx:0.02,dy:up ? upper:lower)).press(forDuration:0.05,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.02,dy:up ? lower:upper)),withVelocity:.slow,thenHoldForDuration:0.1)
        };capture(app,"unreachable");XCTFail("Unreachable control: \(e)")
    }
    @MainActor private func assertVisibleInput(_ field: XCUIElement, _ app: XCUIApplication) {
        XCTAssertGreaterThan(field.frame.minY,70)
        XCTAssertLessThanOrEqual(field.frame.maxY,app.buttons["donation.edit.save"].frame.minY)
    }
    @MainActor private func dismissKeyboard(_ app:XCUIApplication) {
        app.coordinate(withNormalizedOffset:CGVector(dx:0.02,dy:0.35)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout:5))
    }
    @MainActor func testMaximumEditorPreviewKeyboardAndClose() {
        maximumEditorPreviewKeyboardAndClose(language: ProcessInfo.processInfo.environment["Support19Language"] ?? "uk")
    }
    @MainActor func testMaximumGermanEditorPreviewKeyboardAndClose() {
        maximumEditorPreviewKeyboardAndClose(language: "de")
    }
    @MainActor private func maximumEditorPreviewKeyboardAndClose(language lang: String) {
        let app=XCUIApplication();app.launchArguments=["-ui-testing","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL"]
        app.launchEnvironment=["UITestForceOwnerSession":"1","UITestResetUserSettings":"1","UITestResetAppLock":"1","UITestFeedbackInbox":"1","UITestAppLanguage":lang,"UITestAppAppearance":lang == "uk" ? "light":"dark"]
        app.launch();let profile=app.tabBars.buttons.element(boundBy:4);XCTAssertTrue(profile.waitForExistence(timeout:20));profile.tap()
        let entry=app.buttons["profile.owner.donationSettings"];reach(entry,app);entry.tap()
        let save=app.buttons["donation.edit.save"];XCTAssertTrue(save.waitForExistence(timeout:8));capture(app,lang+"-preview-top-max")
        XCTAssertFalse(app.tabBars.firstMatch.exists);XCTAssertLessThan(save.frame.height,150)
        let url=app.textFields["donation.edit.url"];reach(url,app);url.tap();url.typeText("https://example.org/support");capture(app,lang+"-url-keyboard-max");assertVisibleInput(url,app)
        dismissKeyboard(app)
        let edit=app.segmentedControls["donation.edit.language"];reach(edit,app);edit.buttons.element(boundBy:lang == "uk" ? 0:1).tap()
        let title=app.textFields["donation.edit.title.\(lang)"];reach(title,app);title.tap();title.typeText(" TEST19");capture(app,lang+"-title-keyboard-max");dismissKeyboard(app)
        let message=app.descendants(matching:.any).matching(identifier:"donation.edit.message.\(lang)").firstMatch;reach(message,app);message.tap();message.typeText(" MARKER19");capture(app,lang+"-message-keyboard-max");assertVisibleInput(message,app);dismissKeyboard(app)
        let button=app.textFields["donation.edit.button.\(lang)"];reach(button,app);capture(app,lang+"-button-text-max")
        let preview=app.buttons["donation.preview.toggle"];reach(preview,app);preview.tap()
        let previewLanguage=app.segmentedControls["donation.preview.language"];reach(previewLanguage,app);previewLanguage.buttons.element(boundBy:lang == "uk" ? 1:0).tap();capture(app,lang+"-preview-other-language-max")
        let translate=app.buttons["translation.donation"];reach(translate,app);capture(app,lang+"-translation-entry-max")
        let back=app.buttons["navigation.back"].firstMatch;XCTAssertTrue(back.exists);back.tap();capture(app,lang+"-close-confirmation-max")
        let saveClose=app.buttons["donation.confirm.save"].firstMatch
        XCTAssertTrue(saveClose.waitForExistence(timeout:5));reach(saveClose,app);capture(app,lang+"-close-actions-max");saveClose.tap();XCTAssertTrue(entry.waitForExistence(timeout:8));entry.tap()
        reach(url,app);XCTAssertEqual(url.value as? String,"https://example.org/support")
        let reopened=app.textFields["donation.edit.title.\(lang)"];reach(reopened,app);XCTAssertTrue((reopened.value as? String)?.contains("TEST19")==true);capture(app,lang+"-reopened-title-max");reach(message,app);XCTAssertTrue((message.value as? String)?.contains("MARKER19")==true)
    }
}

extension Support19VisualAuditUITests {
    @MainActor func testCloseCancellationDiscardAndTranslationDirections() {
        let app=XCUIApplication();app.launchArguments=["-ui-testing","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryL"]
        app.launchEnvironment=["UITestForceOwnerSession":"1","UITestResetUserSettings":"1","UITestResetAppLock":"1","UITestAppLanguage":"uk","UITestAppAppearance":"light"]
        app.launch();let profile=app.tabBars.buttons.element(boundBy:4);XCTAssertTrue(profile.waitForExistence(timeout:20));profile.tap()
        let entry=app.buttons["profile.owner.donationSettings"];reach(entry,app);entry.tap()
        let url=app.textFields["donation.edit.url"];reach(url,app);url.tap();url.typeText("https://example.org/disposable-support19")
        dismissKeyboard(app)
        let back=app.buttons["navigation.back"].firstMatch;back.tap()
        XCTAssertTrue(app.buttons["donation.confirm.discard"].waitForExistence(timeout:5));capture(app,"close-cancel-before")
        let cancel=app.buttons["Скасувати"].firstMatch
        XCTAssertTrue(cancel.exists && cancel.isHittable);cancel.tap()
        XCTAssertTrue(app.buttons["donation.edit.save"].waitForExistence(timeout:5));reach(url,app);XCTAssertEqual(url.value as? String,"https://example.org/disposable-support19")
        back.tap();let discard=app.buttons["donation.confirm.discard"];XCTAssertTrue(discard.waitForExistence(timeout:5));discard.tap();XCTAssertTrue(entry.waitForExistence(timeout:8));entry.tap();reach(url,app)
        XCTAssertNotEqual(url.value as? String,"https://example.org/disposable-support19");XCTAssertFalse(app.buttons["donation.edit.save"].isEnabled)
        let title=app.textFields["donation.edit.title.uk"];reach(title,app);let original=title.value as? String ?? "";XCTAssertFalse(original.isEmpty)
        let translate=app.buttons["translation.donation"];reach(translate,app);translate.tap()
        let apply=app.buttons["translation.apply"];XCTAssertTrue(apply.waitForExistence(timeout:8));XCTAssertFalse(apply.isEnabled)
        let confirm=app.switches["translation.confirm"];reach(confirm,app);confirm.tap();reach(apply,app);capture(app,"uk-de-translation-review");XCTAssertTrue(apply.isEnabled);apply.tap()
        let language=app.segmentedControls["donation.edit.language"];reach(language,app);language.buttons.element(boundBy:1).tap()
        let german=app.textFields["donation.edit.title.de"];reach(german,app);XCTAssertEqual(german.value as? String,"DE: "+original)
        reach(translate,app);translate.tap();XCTAssertTrue(apply.waitForExistence(timeout:8));capture(app,"de-uk-translation-cancel");app.buttons["editor.close"].tap()
        reach(language,app);language.buttons.element(boundBy:0).tap();reach(title,app);XCTAssertEqual(title.value as? String,original)
    }
}

extension Support19VisualAuditUITests {
    @MainActor private func startSupportScenario(_ scenario:String, role:String = "owner") -> XCUIApplication {
        let app=XCUIApplication();app.launchArguments=["-ui-testing","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryL"]
        app.launchEnvironment=["UITestForceOwnerSession":role == "owner" ? "1":"0","UITestProfileRole":role,"UITestResetUserSettings":"1","UITestResetAppLock":"1","UITestFeedbackInbox":"1","UITestAppLanguage":"uk","UITestAppAppearance":"light","UITestProjectSupport":scenario,"UITestProjectSupportOpenFailure":"1"]
        app.launch();let profile=app.tabBars.buttons.element(boundBy:4);XCTAssertTrue(profile.waitForExistence(timeout:20));profile.tap();return app
    }
    @MainActor func testPublicAdminSupportDestinationAndFailedExternalOpen() {
        let app=startSupportScenario("enabled",role:"admin")
        XCTAssertFalse(app.buttons["profile.owner.donationSettings"].exists)
        let entry=app.buttons["profile.supportProject"];reach(entry,app);entry.tap()
        let link=app.buttons["donation.public.openLink"];reach(link,app);link.tap()
        let error=app.descendants(matching:.any).matching(identifier:"donation.public.linkFailure").firstMatch
        XCTAssertTrue(error.waitForExistence(timeout:5))
        let copy=app.buttons["donation.public.copyLink"];reach(copy,app);capture(app,"public-external-failure");copy.tap()
        app.buttons["navigation.back"].firstMatch.tap();XCTAssertTrue(entry.waitForExistence(timeout:5))
    }
    @MainActor func testConcurrentConflictReloadCancelAndConfirmedReload() {
        let app=startSupportScenario("conflict")
        let entry=app.buttons["profile.owner.donationSettings"];reach(entry,app);entry.tap()
        let title=app.textFields["donation.edit.title.uk"];reach(title,app);title.tap();title.typeText(" LOCAL19");dismissKeyboard(app)
        app.buttons["donation.edit.save"].tap()
        let reload=app.buttons["donation.edit.reload"];XCTAssertTrue(reload.waitForExistence(timeout:8));reach(reload,app);reload.tap()
        XCTAssertTrue(app.buttons["donation.confirm.reload"].waitForExistence(timeout:5));capture(app,"conflict-reload-confirmation")
        app.buttons["Скасувати"].tap();reach(title,app);XCTAssertTrue((title.value as? String)?.contains("LOCAL19")==true)
        reach(reload,app);reload.tap();app.buttons["donation.confirm.reload"].tap()
        reach(title,app);XCTAssertEqual(title.value as? String,"Серверна версія19");XCTAssertFalse(app.buttons["donation.edit.save"].isEnabled)
        app.buttons["navigation.back"].firstMatch.tap();XCTAssertTrue(entry.waitForExistence(timeout:8));entry.tap();reach(title,app);XCTAssertEqual(title.value as? String,"Серверна версія19")
    }
    @MainActor func testUnconfirmedSaveRequiresReadbackBeforeAnotherSave() {
        let app=startSupportScenario("unconfirmed")
        let entry=app.buttons["profile.owner.donationSettings"];reach(entry,app);entry.tap()
        let title=app.textFields["donation.edit.title.uk"];reach(title,app);title.tap();title.typeText(" UNCERTAIN19");dismissKeyboard(app)
        app.buttons["donation.edit.save"].tap()
        let reload=app.buttons["donation.edit.reload"];XCTAssertTrue(reload.waitForExistence(timeout:8));XCTAssertFalse(app.buttons["donation.edit.save"].isEnabled)
        reach(reload,app);capture(app,"unconfirmed-save");reload.tap();app.buttons["donation.confirm.reload"].tap()
        reach(title,app);XCTAssertTrue((title.value as? String)?.contains("UNCERTAIN19")==true);XCTAssertFalse(app.buttons["donation.edit.save"].isEnabled)
        XCTAssertFalse(reload.exists)
    }
}

extension Support19VisualAuditUITests {
    @MainActor func testInitialOfflineStateAndRetryNeverExposeDefaultDraftAsSaved() {
        let app = startSupportScenario("readRecovery")
        let entry = app.buttons["profile.owner.donationSettings"]; reach(entry,app); entry.tap()
        let loading = app.descendants(matching:.any).matching(identifier:"donation.edit.loading").firstMatch
        XCTAssertTrue(loading.waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["donation.edit.save"].exists)
        XCTAssertFalse(app.staticTexts["donation.saved.visibility"].exists)
        capture(app,"initial-loading")
        let failure = app.staticTexts["Не вдалося завантажити налаштування підтримки."]
        XCTAssertTrue(failure.waitForExistence(timeout:6)); capture(app,"initial-offline-error")
        for _ in 0..<2 {
            if app.buttons["donation.edit.save"].exists { break }
            let retry = app.buttons["Спробувати ще раз"].firstMatch
            XCTAssertTrue(retry.waitForExistence(timeout:5)); retry.tap()
            _ = app.buttons["donation.edit.save"].waitForExistence(timeout:4)
        }
        let save = app.buttons["donation.edit.save"]
        XCTAssertTrue(save.waitForExistence(timeout:5)); XCTAssertFalse(save.isEnabled)
        XCTAssertFalse(failure.exists); XCTAssertTrue(app.staticTexts["donation.saved.visibility"].exists)
        capture(app,"read-recovered")
    }
}
