import XCTest

@MainActor
final class DirectoryAuditUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testPublishReopenAndDiscardCategoryInBothThemes() {
        for german in [false, true] {
            let app = launch(german: german)
            openCategoryEditor(app)
            let name = app.textFields["directory.field.categoryTitle.uk"].firstMatch
            reveal(name, app); let original = name.value as! String
            name.tap(); name.typeText(" 909\n"); XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
            capture(app, "directory-category-edit-\(german)")
            let publish = app.buttons["directory.category.publish"].firstMatch
            XCTAssertTrue(publish.isEnabled); publish.tap()
            let confirm = app.popovers.buttons[german ? "Veröffentlichen" : "Опублікувати"].firstMatch
            XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
            XCTAssertTrue(name.waitForNonExistence(timeout: 10))
            let category = app.buttons["directory.category.manage.first-steps"].firstMatch
            reveal(category, app); category.tap(); reveal(name, app)
            XCTAssertEqual(name.value as? String, original + " 909")
            name.tap(); name.typeText(" 808\n"); XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
            app.navigationBars.buttons.element(boundBy: 0).tap()
            let discard = app.buttons[german ? "Änderungen verwerfen" : "Відкинути зміни"].firstMatch
            XCTAssertTrue(discard.waitForExistence(timeout: 5)); capture(app, "directory-discard-\(german)"); discard.tap()
            reveal(category, app); category.tap(); reveal(name, app)
            XCTAssertEqual(name.value as? String, original + " 909")
            app.terminate()
        }
    }

    func testNestedArticleRegionBlockAndNewDraftCancellation() {
        let app = launch(german: true, large: true)
        openCategoryEditor(app)
        let topic = app.buttons["directory.topic.edit.arrival"].firstMatch
        reveal(topic, app); topic.tap()
        let title = app.textFields["directory.field.articleTitle.uk"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5)); capture(app, "directory-article-de-dark-AX")
        let section = app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@", "directory.section.edit.")).firstMatch
        reveal(section, app); section.tap()
        XCTAssertTrue(app.textFields["directory.field.sectionTitle.uk"].firstMatch.waitForExistence(timeout: 5))
        capture(app, "directory-block-de-dark-AX")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let region = app.buttons["directory.region.edit.wien"].firstMatch
        reveal(region, app); region.tap(); capture(app, "directory-region-de-dark-AX")
        let add = app.buttons["Abschnitt hinzufügen"].firstMatch
        reveal(add, app); add.tap()
        let field = app.textFields["directory.field.sectionTitle.uk"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("Draft\n"); XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        app.buttons["Abbrechen"].firstMatch.tap()
        let discard = app.buttons["Änderungen verwerfen"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 5)); capture(app, "directory-new-block-discard"); discard.tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
    }

    func testDirectoryRoleEntryRightsAndPublicRead() {
        for role in ["owner", "admin", "member", "org-owner", "org-admin", "org-moderator", "mixed", "warned", "blocked", "guest", "directoryEditor"] {
            let app = launch(role: role)
            let manage = app.buttons["directory.manage"].firstMatch
            if role == "owner" || role == "directoryEditor" {
                reveal(manage, app); XCTAssertTrue(manage.isEnabled)
            } else { XCTAssertFalse(manage.exists) }
            let publicCategory = app.buttons["directory.category.safety"].firstMatch
            reveal(publicCategory, app); publicCategory.tap()
            XCTAssertTrue(app.buttons["directory.topic.emergency"].waitForExistence(timeout: 8))
            capture(app, "directory-read-" + role); app.terminate()
        }
    }

    func testCategoryGroupSymbolAndNewCategoryForms() {
        let app = launch(german: true, large: true)
        openCategoryEditor(app)
        let symbol = app.buttons["Symbol des Bereichs"].firstMatch
        reveal(symbol, app); symbol.tap()
        let symbolSearch = app.textFields["directory.symbol.search"].firstMatch
        XCTAssertTrue(symbolSearch.waitForExistence(timeout: 5)); symbolSearch.tap(); symbolSearch.typeText("Information\n")
        XCTAssertTrue(app.buttons["Information"].firstMatch.waitForExistence(timeout: 5))
        capture(app, "directory-symbol-picker-AX")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let group = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "directory.group.edit.")).firstMatch
        reveal(group, app); group.tap()
        XCTAssertTrue(app.textFields["directory.field.groupTitle.uk"].firstMatch.waitForExistence(timeout: 5)); capture(app, "directory-group-editor-AX")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let addGroup = app.buttons["Unterbereich hinzufügen"].firstMatch
        reveal(addGroup, app); addGroup.tap()
        let groupTitle = app.textFields["directory.field.groupTitle.uk"].firstMatch
        XCTAssertTrue(groupTitle.waitForExistence(timeout: 5)); capture(app, "directory-new-group-AX")
        app.buttons["Abbrechen"].firstMatch.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let create = app.buttons["directory.category.add.start"].firstMatch
        reveal(create, app); create.tap()
        let title = app.textFields["directory.field.categoryTitle.uk"].firstMatch
        reveal(title, app); capture(app, "directory-new-category-AX"); title.tap(); title.typeText("909\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let discard = app.buttons["Änderungen verwerfen"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 5)); discard.tap()
        XCTAssertTrue(create.waitForExistence(timeout: 5))
    }

    func testPublicArticleSearchInAlternateLanguageThemes() {
        for german in [false, true] {
            let app = launch(role: "member", german: german, alternateTheme: true)
            let search = app.buttons[german ? "Suchen" : "Пошук"].firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 8)); search.tap()
            let field = app.textFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap()
            field.typeText(german ? "Erster Tag" : "Перший день")
            let result = app.buttons["directory.search.first-steps.arrival"].firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 8)); field.typeText("\n")
            result.tap()
            XCTAssertTrue(app.staticTexts[german ? "Erster Tag: Unterkunft und Hilfe" : "Перший день: ночівля й допомога"].firstMatch.waitForExistence(timeout: 8))
            capture(app, "directory-public-search-" + (german ? "de-light" : "uk-dark"))
            app.terminate()
        }
    }

    func testIndividualInformationReaderAndShareInBothLanguages() {
        for german in [false, true] {
            let app = launch(role: "member", german: german)
            let category = app.buttons["directory.category.first-steps"].firstMatch
            reveal(category, app); category.tap()
            let topic = app.buttons["directory.topic.arrival"].firstMatch
            reveal(topic, app); topic.tap()
            let topicShare = app.buttons["directory.topic.share"].firstMatch
            XCTAssertTrue(topicShare.waitForExistence(timeout: 8)); topicShare.tap()
            let topicCopy = app.cells.matching(NSPredicate(format: "label IN %@", ["Kopieren", "Copy", "Копіювати", "Скопіювати"])).firstMatch
            XCTAssertTrue(topicCopy.waitForExistence(timeout: 8)); tapCopyIcon(topicCopy)
            XCTAssertTrue(topicCopy.waitForNonExistence(timeout: 5))
            let section = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "directory.section.open.")).firstMatch
            reveal(section, app); section.tap()
            let share = app.buttons["detail.header.share"].firstMatch
            XCTAssertTrue(share.waitForExistence(timeout: 8))
            capture(app, "directory-reader-\(german ? "de-dark" : "uk-light")")
            share.tap()
            let copy = app.cells.matching(NSPredicate(format: "label IN %@", ["Kopieren", "Copy", "Копіювати", "Скопіювати"])).firstMatch
            XCTAssertTrue(copy.waitForExistence(timeout: 8))
            capture(app, "directory-reader-share-\(german)")
            tapCopyIcon(copy)
            XCTAssertTrue(copy.waitForNonExistence(timeout: 5))
            XCTAssertTrue(share.isHittable)
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(section.waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    func testEmergencyInformationReaderAtLargeText() {
        let app = launch(role: "guest", german: true, large: true)
        let category = app.buttons["directory.category.safety"].firstMatch
        reveal(category, app); category.tap()
        let topic = app.buttons["directory.topic.emergency"].firstMatch
        reveal(topic, app); topic.tap()
        let section = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "directory.section.open.")).firstMatch
        reveal(section, app); section.tap()
        XCTAssertTrue(app.buttons["detail.header.share"].waitForExistence(timeout: 8))
        capture(app, "directory-emergency-reader-large-text")
        XCUIDevice.shared.orientation = .landscapeLeft
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.frame.width > app.frame.height }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 8), .completed)
        capture(app, "directory-emergency-reader-landscape")
        XCUIDevice.shared.orientation = .portrait
    }

    func testReaderEntryAcrossEveryDirectoryCategory() {
        let app = launch(role: "member")
        let categories = ["safety", "first-steps", "registration", "housing", "residence", "documents",
            "citizenship", "health", "mental-health", "insurance", "work", "qualifications", "education",
            "family", "transport", "finances", "social-support", "legal", "communication", "digital",
            "community", "leisure", "accessibility", "care", "seniors"]
        for id in categories {
            let category = app.buttons["directory.category." + id].firstMatch
            reveal(category, app); category.tap()
            let topic = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "directory.topic.")).firstMatch
            let section = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "directory.section.open.")).firstMatch
            // One-topic categories intentionally open their article directly.
            let directArticle = section.waitForExistence(timeout: 2)
            if !directArticle { reveal(topic, app); topic.tap() }
            reveal(section, app)
            capture(app, "directory-topic-" + id)
            section.tap()
            XCTAssertTrue(app.buttons["detail.header.share"].waitForExistence(timeout: 8), id)
            capture(app, "directory-reader-" + id)
            for _ in 0..<(directArticle ? 2 : 3) { app.navigationBars.buttons.element(boundBy: 0).tap() }
            XCTAssertTrue(app.buttons["directory.category." + id].waitForExistence(timeout: 8))
        }
    }

    func testLongestInformationReaderRetainsFullTextAndSource() {
        let app = launch(role: "member", german: true)
        let category = app.buttons["directory.category.insurance"].firstMatch
        reveal(category, app); category.tap()
        let topic = app.buttons["directory.topic.health-cover"].firstMatch
        reveal(topic, app); topic.tap()
        let section = app.buttons["directory.section.open.self"].firstMatch
        reveal(section, app); section.tap()
        XCTAssertTrue(app.buttons["detail.header.share"].waitForExistence(timeout: 8))
        capture(app, "directory-longest-reader-top")
        let source = app.links["directory.reader.source"].firstMatch
        reveal(source, app)
        capture(app, "directory-longest-reader-bottom")
        XCTAssertTrue(source.isHittable)
        XCTAssertGreaterThanOrEqual(source.frame.height, 44)
    }

    private func tapCopyIcon(_ cell: XCUIElement) {
        // iOS 27's action-group cell extends below its icon; its centre can miss the action on iPad.
        let icon = cell.images["activityImageView"].firstMatch
        if icon.exists { icon.tap() } else { cell.tap() }
    }

    private func launch(role: String = "owner", german: Bool = false, large: Bool = false, alternateTheme: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-UIPreferredContentSizeCategoryName", large ? "UICTContentSizeCategoryAccessibilityM" : "UICTContentSizeCategoryL"]
        app.launchEnvironment = ["UITestResetUserSettings":"1", "UITestResetAppLock":"1", "UITestDirectoryRecentPreview":"1", "UITestAppLanguage":german ? "de":"uk", "UITestAppAppearance":(german != alternateTheme) ? "dark":"light"]
        if role == "owner" { app.launchEnvironment["UITestForceOwnerSession"] = "1" }
        else if role == "guest" { app.launchEnvironment["UITestForceGuestSession"] = "1" }
        else { app.launchEnvironment["UITestProfileRole"] = role == "directoryEditor" ? "member" : role }
        if role == "directoryEditor" { app.launchEnvironment["UITestDirectoryEditor"] = "1" }
        app.launch()
        let tab = app.tabBars.buttons.element(boundBy: 3)
        if tab.waitForExistence(timeout: 5) { tab.tap() }
        else {
            let tabletTab = app.buttons["tab.directory"].firstMatch
            XCTAssertTrue(tabletTab.waitForExistence(timeout: 20)); tabletTab.tap()
        }
        return app
    }
    private func openCategoryEditor(_ app: XCUIApplication) {
        let manage = app.buttons["directory.manage"].firstMatch
        reveal(manage, app); manage.tap()
        let category = app.buttons["directory.category.manage.first-steps"].firstMatch
        reveal(category, app); category.tap()
    }
    private func keyboardDown(_ app: XCUIApplication) {
        if app.keyboards.firstMatch.exists {
            app.coordinate(withNormalizedOffset: .init(dx: 0.75, dy: 0.10)).tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        }
    }
    private func reveal(_ item: XCUIElement, _ app: XCUIApplication) {
        _ = item.waitForExistence(timeout: 8)
        for _ in 0..<40 {
            if item.exists && item.isHittable && item.frame.midY > 70 && item.frame.midY < app.frame.height - 100 { return }
            let down = item.exists && item.frame.midY < 70
            app.coordinate(withNormalizedOffset: .init(dx:0.5,dy:down ? 0.35:0.65)).press(forDuration:0.05,
                thenDragTo:app.coordinate(withNormalizedOffset:.init(dx:0.5,dy:down ? 0.65:0.35)))
        }
        XCTAssertTrue(item.isHittable)
    }
    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
