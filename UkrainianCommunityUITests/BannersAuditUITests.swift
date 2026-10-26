import XCTest

@MainActor
final class BannersAuditUITests: XCTestCase {
    private func launch(_ scope:String, language:String="uk", maximum:Bool=false, owner:Bool=true, artwork:Bool=false, palette:String?=nil)->XCUIApplication {
        let app=XCUIApplication();app.launchArguments=["-ui-testing","-UIPreferredContentSizeCategoryName",maximum ? "UICTContentSizeCategoryAccessibilityXXXL":"UICTContentSizeCategoryL"]
        app.launchEnvironment=["UITestBanner14":"1","UITestBanner14Scope":scope,"UITestAppLanguage":language,"UITestAppAppearance":language=="de" ? "dark":"light",owner ? "UITestForceOwnerSession":"UITestForceAuthenticatedSession":"1"]
        if artwork { app.launchEnvironment["UITestBanner14Artwork"] = "1" }
        if let palette { app.launchEnvironment["UITestBanner14ArtworkPalette"] = palette }
        app.launch();return app
    }
    private func capture(_ app:XCUIApplication,_ name:String){let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
    private func reveal(_ element:XCUIElement,in app:XCUIApplication){for _ in 0..<25 {if element.exists && element.isHittable{return};app.swipeUp()};XCTAssertTrue(element.isHittable,app.debugDescription)}
    func testCountdownSecondsAdvanceWithoutChangingBannerSize() {
        let app = launch("carousel", artwork: true)
        let card = app.buttons["featuredBanner.card.banner14-1"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        let timer = app.descendants(matching: .any)["featuredBanner.countdown"].firstMatch
        XCTAssertTrue(timer.exists)
        let before = timer.label
        let frame = card.frame
        XCTAssertTrue(before.contains("с"))
        XCTAssertTrue(XCTNSPredicateExpectation(predicate: NSPredicate(format: "label != %@", before), object: timer).evaluate(timeout: 4), "Seconds must visibly advance")
        XCTAssertEqual(card.frame.height, frame.height, accuracy: 1)
        capture(app, "B14-live-seconds-without-panel")
        app.terminate()
    }
    func testIndependentTextColorsSaveReopenAndResetInBothLanguages() {
        for language in ["uk", "de"] {
            let app = launch("management", language: language, maximum: language == "de", artwork: true)
            let edit = app.buttons["bannerManagement.edit.banner14-1"].firstMatch
            reveal(edit, in: app); edit.tap()
            let blue = app.buttons["bannerEditor.titleColor.blue"].firstMatch
            let yellow = app.buttons["bannerEditor.subtitleColor.yellow"].firstMatch
            reveal(blue, in: app); blue.tap()
            reveal(yellow, in: app); yellow.tap()
            XCTAssertTrue(blue.isSelected); XCTAssertTrue(yellow.isSelected)
            capture(app, "B14-independent-color-controls-" + language)
            let preview = app.descendants(matching: .any)["bannerEditor.preview"].firstMatch
            for _ in 0..<25 { if preview.exists && preview.frame.minY >= 100 { break }; app.swipeDown() }
            if language == "uk" {
                XCTAssertEqual(preview.frame.height, preview.frame.width / (16.0 / 9.0), accuracy: 2, "Normal editor preview must show the same overlay layout as the feed")
            }
            capture(app, "B14-colored-title-and-description-preview-" + language)
            let save = app.buttons["bannerEditor.save"].firstMatch
            reveal(save, in: app); save.tap()
            reveal(edit, in: app); edit.tap()
            reveal(blue, in: app); XCTAssertTrue(blue.isSelected)
            reveal(yellow, in: app); XCTAssertTrue(yellow.isSelected)
            let resetTitle = app.buttons["bannerEditor.titleColor.reset"].firstMatch
            reveal(resetTitle, in: app); resetTitle.tap()
            XCTAssertFalse(blue.isSelected); XCTAssertTrue(yellow.isSelected)
            let resetBoth = app.buttons["bannerEditor.colors.reset"].firstMatch
            reveal(resetBoth, in: app); resetBoth.tap()
            XCTAssertFalse(yellow.isSelected)
            capture(app, "B14-colors-reset-" + language)
            app.terminate()
        }
    }
    func testNativeTitleColorPickerCanOpenAndClose() {
        let app = launch("editor", artwork: true)
        let picker = app.descendants(matching: .any)["bannerEditor.titleColor"].firstMatch
        reveal(picker, in: app); picker.tap()
        capture(app, "B14-native-title-color-picker")
        let close = app.buttons.matching(NSPredicate(format: "label IN %@", ["Schließen", "Close", "Fertig", "Готово"])).firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5), app.debugDescription)
        close.tap()
        XCTAssertTrue(picker.exists)
        for _ in 0..<25 { if app.buttons["editor.close"].firstMatch.isHittable { break }; app.swipeDown() }
        app.buttons["editor.close"].firstMatch.tap()
        XCTAssertFalse(app.buttons["bannerEditor.discardChanges"].exists, "Opening and closing the color picker must not alter default colors")
        app.terminate()
    }
    func testActualArtworkWithAndWithoutCountdownAtNormalAndLargestType() {
        for language in ["uk", "de"] {
            let app = launch("carousel", language: language, maximum: language == "de", artwork: true)
            let first = app.buttons["featuredBanner.card.banner14-1"].firstMatch
            XCTAssertTrue(first.waitForExistence(timeout: 15))
            let viewport = app.descendants(matching: .any)["featuredBanner.carousel"].firstMatch
            let probe = app.descendants(matching: .any)["featuredBanner.artworkGeometry"].firstMatch
            let ready = NSPredicate(format: "value CONTAINS %@ AND NOT value CONTAINS %@", "id=banner14-1", "width=0.0")
            XCTAssertTrue(XCTNSPredicateExpectation(predicate: ready, object: probe).evaluate(timeout: 5))
            let values = (probe.value as? String ?? "").split(separator: ";").reduce(into: [String: String]()) { result, field in
                let pair = field.split(separator: "=", maxSplits: 1)
                if pair.count == 2 { result[String(pair[0])] = String(pair[1]) }
            }
            XCTAssertEqual(Double(values["width"] ?? "") ?? 0, Double(viewport.frame.width), accuracy: 1, "The selected banner must retain full width: \(String(describing: probe.value))")
            XCTAssertEqual(Double(values["artwork"] ?? "") ?? 0, Double(viewport.frame.width) / (16.0 / 9.0), accuracy: 1, "Large text and countdown must retain the full picture height")
            let countdownHeight = first.frame.height
            capture(app, "B14-real-artwork-countdown-" + language)
            first.swipeLeft()
            let second = app.buttons["featuredBanner.card.banner14-2"].firstMatch
            XCTAssertTrue(second.waitForExistence(timeout: 5))
            if language == "uk" {
                XCTAssertEqual(second.frame.height, countdownHeight, accuracy: 1, "Countdown must not resize the normal-size picture")
            }
            capture(app, "B14-real-artwork-plain-" + language)
            app.terminate()
        }
    }
    func testTextOnlyCountdownOnLightAndDarkArtwork() {
        for palette in ["light", "dark"] {
            let app = launch("carousel", artwork: true, palette: palette)
            XCTAssertTrue(app.buttons["featuredBanner.card.banner14-1"].firstMatch.waitForExistence(timeout: 15))
            XCTAssertTrue(app.descendants(matching: .any)["featuredBanner.countdown"].firstMatch.exists)
            capture(app, "B14-text-only-counter-" + palette)
            app.terminate()
        }
    }
    func testSeparatedCarouselCountdownAndOnlySettledCardMeasurements(){
        for language in ["uk","de"] {
            let app=launch("carousel",language:language,maximum:language=="de")
            let first=app.buttons["featuredBanner.card.banner14-1"].firstMatch
            XCTAssertTrue(first.waitForExistence(timeout:15));XCTAssertTrue(app.descendants(matching:.any)["featuredBanner.countdown"].firstMatch.exists)
            XCTAssertTrue(first.label.contains(language == "uk" ? "До зустрічі" : "Bis zum"), "VoiceOver must include the countdown")
            capture(app,"B14-carousel-\(language)-initial")
            let events=app.staticTexts["banner14.events"]
            let firstImpression=NSPredicate(format:"label CONTAINS %@","banner14-1:impression")
            XCTAssertTrue(XCTNSPredicateExpectation(predicate:firstImpression,object:events).evaluate(timeout:8))
            XCTAssertFalse(events.label.contains("banner14-2:impression"));XCTAssertFalse(events.label.contains("banner14-3:impression"))
            first.swipeLeft()
            let second=app.buttons["featuredBanner.card.banner14-2"].firstMatch
            XCTAssertTrue(second.waitForExistence(timeout:5))
            let secondImpression=NSPredicate(format:"label CONTAINS %@","banner14-2:impression")
            XCTAssertTrue(XCTNSPredicateExpectation(predicate:secondImpression,object:events).evaluate(timeout:8))
            capture(app,"B14-carousel-\(language)-second")
            second.tap()
            XCTAssertTrue(events.label.contains("banner14-2:click"))
            app.terminate()
        }
    }
    func testCountdownEditorAndExplicitDiscardInBothLanguages(){
        for language in ["uk","de"] {
            let app=launch("editor",language:language,maximum:language=="de")
            XCTAssertTrue(app.buttons["bannerEditor.statistics"].waitForExistence(timeout:15))
            capture(app,"B14-editor-preview-\(language)")
            let toggle=app.switches["bannerEditor.countdown.enabled"].firstMatch;reveal(toggle,in:app)
            XCTAssertEqual(toggle.value as? String,"1");capture(app,"B14-countdown-controls-\(language)")
            toggle.tap();XCTAssertEqual(toggle.value as? String,"0")
            toggle.tap();XCTAssertEqual(toggle.value as? String,"1")
            let field=app.textFields.matching(identifier:"bannerEditor.countdown.label").firstMatch
            reveal(field,in:app);field.tap();field.typeText(" !")
            if app.keyboards.buttons["Done"].exists {app.keyboards.buttons["Done"].tap()}
            for _ in 0..<25 {if app.buttons["editor.close"].firstMatch.isHittable{break};app.swipeDown()}
            let close=app.buttons.matching(identifier:"editor.close").allElementsBoundByIndex.first(where:{$0.isHittable})
            XCTAssertNotNil(close,app.debugDescription);close?.tap()
            let keep=app.buttons["bannerEditor.keepEditing"].firstMatch;reveal(keep,in:app)
            capture(app,"B14-discard-\(language)");keep.tap()
            XCTAssertTrue(app.switches["bannerEditor.countdown.enabled"].firstMatch.exists)
            app.terminate()
        }
    }
    func testNonOwnerCannotLoadManagement(){
        let app=launch("management",owner:false)
        XCTAssertFalse(app.buttons["bannerManagement.edit.banner14-1"].waitForExistence(timeout:3))
        XCTAssertFalse(app.buttons["bannerManagement.statistics.banner14-1"].exists)
        capture(app,"B14-management-member-denied");app.terminate()
    }
    func testOwnerSavesCountdownAndReopensThenCancelsAndConfirmsDeletion() {
        let app=launch("management")
        let edit=app.buttons["bannerManagement.edit.banner14-1"].firstMatch
        reveal(edit,in:app);edit.tap()
        let field=app.textFields["bannerEditor.countdown.label"].firstMatch
        reveal(field,in:app);field.tap();field.typeText(" !")
        app.coordinate(withNormalizedOffset:CGVector(dx:0.75,dy:0.12)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout:5))
        let save=app.buttons["bannerEditor.save"].firstMatch;reveal(save,in:app)
        XCTAssertTrue(save.isEnabled);save.tap()
        reveal(edit,in:app);edit.tap();reveal(field,in:app)
        XCTAssertTrue((field.value as? String ?? "").contains("!"));capture(app,"B14-countdown-saved-reopened")
        for _ in 0..<25 {if app.buttons["editor.close"].firstMatch.isHittable{break};app.swipeDown()}
        app.buttons["editor.close"].firstMatch.tap()
        let remove=app.buttons["bannerManagement.delete.banner14-1"].firstMatch;reveal(remove,in:app);remove.tap()
        let cancel=app.buttons["bannerManagement.cancelDelete"].firstMatch;reveal(cancel,in:app);capture(app,"B14-delete-confirmation");cancel.tap()
        XCTAssertTrue(remove.exists);remove.tap()
        let confirm=app.buttons["bannerManagement.confirmDelete"].firstMatch;reveal(confirm,in:app);confirm.tap()
        XCTAssertFalse(remove.waitForExistence(timeout:3));capture(app,"B14-after-delete")
        app.terminate()
    }

    func testActionTargetPickerUsesSharedSearchAndReturnsExactSelection() {
        let app=launch("editor")
        let action=app.buttons["bannerEditor.actionType"].firstMatch
        reveal(action,in:app);action.tap()
        app.buttons["Новини"].firstMatch.tap()
        let choose=app.buttons["bannerEditor.chooseTarget"].firstMatch;reveal(choose,in:app);choose.tap()
        let search=app.textFields["bannerEditor.targetSearch"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout:10));search.tap();search.typeText("ZZZZ-no-target")
        capture(app,"B14-target-search-no-match")
        let clear=app.buttons["bannerEditor.targetSearch.clear"].firstMatch
        XCTAssertTrue(clear.isHittable);clear.tap()
        let rows=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","bannerEditor.target."))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout:5));let selected=rows.firstMatch.label
        rows.firstMatch.tap();XCTAssertTrue(choose.waitForExistence(timeout:5))
        capture(app,"B14-selected-news-target")
        XCTAssertFalse(app.textFields["bannerEditor.targetSearch"].exists)
        XCTAssertFalse(selected.isEmpty)
        app.terminate()
    }

    func testMemberDirectStatisticsRouteShowsDenialInsteadOfLoadingOrMetrics() {
        let app=XCUIApplication();app.launchArguments=["-ui-testing"]
        app.launchEnvironment=["UITestBannerReportAudit":"1","UITestForceAuthenticatedSession":"1","UITestAppLanguage":"uk"]
        app.launch()
        XCTAssertTrue(app.descendants(matching:.any)["bannerReport.denied"].firstMatch.waitForExistence(timeout:10))
        XCTAssertFalse(app.buttons["bannerReport.export"].exists);XCTAssertFalse(app.buttons["bannerReport.bannerFilter"].exists)
        capture(app,"B14-direct-statistics-member-denied");app.terminate()
    }

    func testNativePhotoPickerSelectionReturnsProcessedPreviewWithoutSaving() {
        let app=launch("editor")
        let image=app.buttons["bannerEditor.chooseImage"].firstMatch;reveal(image,in:app);image.tap()
        let cancel=app.buttons.matching(NSPredicate(format:"label IN %@",["Cancel","Abbrechen","Скасувати"])).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout:10));capture(app,"B14-native-photo-picker")
        let photo=app.images.matching(identifier:"PXGGridLayout-Info").firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout:5),app.debugDescription)
        XCTAssertGreaterThan(photo.frame.width,70)
        photo.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout:10))
        let save=app.buttons["bannerEditor.save"].firstMatch
        XCTAssertTrue(XCTNSPredicateExpectation(predicate:NSPredicate(format:"enabled == true"),object:save).evaluate(timeout:10))
        capture(app,"B14-selected-photo-processed-unsaved")
        app.terminate()
    }

    func testAutomaticRotationStopsWhenPausedAndRestartsAfterUserSwipe() {
        let app=XCUIApplication();app.launchArguments=["-ui-testing","-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryL"]
        app.launchEnvironment=["UITestBanner14":"1","UITestBanner14Autoplay":"1","UITestForceOwnerSession":"1","UITestAppLanguage":"uk"]
        app.launch()
        let indicator=app.descendants(matching:.any)["featuredBanner.pageIndicator"].firstMatch
        XCTAssertTrue(indicator.waitForExistence(timeout:10))
        let second=NSPredicate(format:"label CONTAINS %@","2")
        XCTAssertTrue(XCTNSPredicateExpectation(predicate:second,object:indicator).evaluate(timeout:8))
        let pause=app.buttons["banner14.pause"];pause.tap()
        let stable=indicator.label
        let changes=XCTNSPredicateExpectation(predicate:NSPredicate(format:"label != %@",stable),object:indicator);changes.isInverted=true
        XCTAssertTrue(changes.evaluate(timeout:4))
        capture(app,"B14-auto-rotation-paused")
        app.buttons["featuredBanner.card.banner14-2"].firstMatch.swipeRight()
        let first=NSPredicate(format:"label CONTAINS %@","1")
        XCTAssertTrue(XCTNSPredicateExpectation(predicate:first,object:indicator).evaluate(timeout:5))
        pause.tap()
        let tooEarly=XCTNSPredicateExpectation(predicate:second,object:indicator);tooEarly.isInverted=true
        XCTAssertTrue(tooEarly.evaluate(timeout:2))
        XCTAssertTrue(XCTNSPredicateExpectation(predicate:second,object:indicator).evaluate(timeout:5))
        capture(app,"B14-auto-rotation-resumed")
        app.terminate()
    }

    func testNativeCountdownDateAndCompletionMenuAreUsable() {
        let app=launch("editor")
        let date=app.descendants(matching:.any).matching(identifier:"bannerEditor.countdown.date").firstMatch
        reveal(date,in:app)
        let button=date.buttons.firstMatch
        if button.exists {button.tap()} else {date.tap()}
        let month=app.descendants(matching:.any).matching(NSPredicate(format:"label CONTAINS[c] 'Oktober' OR label CONTAINS[c] 'October' OR label CONTAINS[c] 'жовт' ")).firstMatch
        XCTAssertTrue(month.waitForExistence(timeout:5));capture(app,"B14-native-countdown-date")
        app.coordinate(withNormalizedOffset:CGVector(dx:0.95,dy:0.15)).tap()
        let completion=app.buttons["bannerEditor.countdown.completion"].firstMatch
        reveal(completion,in:app);completion.tap()
        let hide=app.buttons["Завершити показ банера"].firstMatch
        XCTAssertTrue(hide.waitForExistence(timeout:5));capture(app,"B14-countdown-completion-menu");hide.tap()
        XCTAssertTrue(completion.label.contains("Завершити"));capture(app,"B14-countdown-hide-banner-selected")
        app.terminate()
    }

}

private extension XCTNSPredicateExpectation {
    func evaluate(timeout:TimeInterval)->Bool {XCTWaiter.wait(for:[self],timeout:timeout) == .completed}
}
