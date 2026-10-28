import XCTest

/// Named read-only checks against the signed app and the controlled real owner.
@MainActor
final class PhysicalAnalyticsFollowupUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        #if targetEnvironment(simulator)
        throw XCTSkip("Physical iPhone required")
        #else
        guard ProcessInfo.processInfo.environment["UACPhysicalClosureAudit"] == "1" else {
            throw XCTSkip("Explicit controlled-account acceptance required")
        }
        XCUIDevice.shared.orientation = .portrait
        #endif
    }

    override func tearDownWithError() throws {
        #if !targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["UACPhysicalClosureAudit"] == "1" {
            XCUIDevice.shared.orientation = .portrait
            if name.contains("testActualLegalEditorKeyboardPreviewAndLeaveWithoutSaving")
                || name.contains("testActualLegalEditorLandscapeLocalKeyboard")
                || name.contains("testActualSupportLocalMessageKeyboardAndDiscard")
                || name.contains("testActualSupportLandscapeLocalKeyboard") {
                // This named case edits only disposable in-memory text. Also
                // clear that local presentation after an assertion abort so
                // subsequent preference restoration cannot hit its close sheet.
                let app = XCUIApplication(); app.terminate(); app.activate()
            }
        }
        #endif
    }

    func testActualRankingExpansionOrganizationSearchAndChildren() {
        let app = XCUIApplication(); openAnalytics(app)
        let thirty = app.buttons["30 днів"].firstMatch
        reveal(thirty, app); thirty.tap()
        XCTAssertTrue(app.descendants(matching: .any)["ownerAnalytics.updatedAt"].firstMatch.waitForExistence(timeout: 30))
        for type in ["news", "event", "organization"] {
            let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ownerAnalytics.content." + type + "."))
            let before = rows.count
            XCTAssertGreaterThan(before, 0)
            let last = rows.element(boundBy: before - 1)
            reveal(last, app)
            let more = app.buttons.matching(NSPredicate(format: "label == %@", "Показати більше"))
                .allElementsBoundByIndex.first {
                    $0.frame.minY >= last.frame.maxY - 2 && $0.frame.minY < last.frame.maxY + 150
                }
            if let more {
                reveal(more, app); more.tap()
                XCTAssertGreaterThan(rows.count, before)
                XCTAssertLessThanOrEqual(rows.count, 20, "Actual declared top20 limit")
                capture(app, "physical-p15-actual-expanded-ranking-" + type)
                let less = app.buttons["Показати менше"].firstMatch
                reveal(less, app); less.tap()
                XCTAssertEqual(rows.count, before)
            } else {
                let note = XCTAttachment(string: "Actual " + type + " ranking has " + String(before) + " rows and no next expansion control")
                note.name = "physical-p15-no-manufactured-ranking-" + type; note.lifetime = .keepAlways; add(note)
            }
        }
        let organization = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ownerAnalytics.content.organization.")).firstMatch
        reveal(organization, app); organization.tap()
        let search = app.textFields["ownerAnalytics.detail.search"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 20)); reveal(search, app)
        search.tap(); search.typeText("UAC-NO-MATCH-20261028\n")
        let empty = app.descendants(matching: .any)["ownerAnalytics.detail.search.empty"].firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 15)); capture(app, "physical-p15-organization-search-empty")
        let clear = app.buttons["ownerAnalytics.detail.search.clear"].firstMatch
        reveal(clear, app); clear.tap(); search.typeText("\n")
        XCTAssertTrue(empty.waitForNonExistence(timeout: 10))
        for type in ["news", "event"] {
            let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ownerAnalytics.detail.content." + type + ".")).firstMatch
            reveal(row, app); row.tap()
            let detail = app.descendants(matching: .any)["screen.ownerAnalytics.contentDetail"].firstMatch
            XCTAssertTrue(detail.waitForExistence(timeout: 20))
            waitForForegroundMetric("ownerAnalytics.metric.eye", app)
            capture(app, "physical-p15-organization-child-" + type)
            popOne(app)
            XCTAssertTrue(detail.waitForNonExistence(timeout: 10))
            XCTAssertTrue(app.descendants(matching: .any)["screen.ownerAnalytics.organizationDetail"].firstMatch.exists)
        }
        profileRoot(app)
    }

    func testActualAnalyticsChartAtApprovedVisualPreferences() throws {
        guard ProcessInfo.processInfo.environment["UACPhysicalVisualPreferencesApproved"] == "2026-10-27",
              let marker = ProcessInfo.processInfo.environment["UACPhysicalVisualLabel"],
              ["de-light-maximum-opaque", "de-dark-maximum-opaque", "de-dark-normal", "uk-light-normal"].contains(marker) else {
            throw XCTSkip("Exact approved visual variant required")
        }
        let app = XCUIApplication(); openAnalytics(app)
        let german = marker.hasPrefix("de")
        let title = german ? "30 Tage" : "30 днів"
        if marker.contains("maximum") {
            let period = app.buttons["ownerAnalytics.periodPicker"].firstMatch
            reveal(period, app); period.tap()
            let choice = app.buttons[title].firstMatch
            XCTAssertTrue(choice.waitForExistence(timeout: 10)); choice.tap()
        } else {
            let period = app.buttons[title].firstMatch
            reveal(period, app); period.tap()
        }
        XCTAssertTrue(app.descendants(matching: .any)["ownerAnalytics.updatedAt"].firstMatch.waitForExistence(timeout: 30))
        let account = app.descendants(matching: .any)["ownerAnalytics.metric.person.3"].firstMatch
        reveal(account, app); capture(app, "physical-p15-" + marker + "-current-accounts")
        app.swipeUp(); capture(app, "physical-p15-" + marker + "-overview-values")
        let picker = app.buttons["ownerAnalytics.trendMetricPicker"].firstMatch
        reveal(picker, app); picker.tap()
        let metricTitle = german ? "Nachrichtenaufrufe" : "Перегляди новин"
        let choice = app.buttons[metricTitle].firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 10)); choice.tap()
        capture(app, "physical-p15-" + marker + "-long-chart-picker")
        let chart = app.descendants(matching: .any)["ownerAnalytics.trendChart"].firstMatch
        reveal(chart, app)
        for _ in 0..<12 {
            let frame = chart.frame
            if frame.minY > (marker.contains("maximum") ? 100 : 180) && frame.maxY < app.frame.height - 50 { break }
            let delta = max(-140, min(140, app.frame.height * 0.53 - frame.midY))
            let from = app.coordinate(withNormalizedOffset: .init(dx: app.frame.width > app.frame.height ? 0.5 : 0.97, dy: 0.55))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(.init(dx: 0, dy: delta)))
        }
        XCTAssertGreaterThan(chart.frame.minY, marker.contains("maximum") ? 100 : 180)
        XCTAssertLessThan(chart.frame.maxY, app.frame.height - 50)
        XCTAssertTrue((chart.value as? String ?? "").contains(metricTitle))
        capture(app, "physical-p15-" + marker + "-whole-chart")
        chart.coordinate(withNormalizedOffset: .init(dx: 0.6, dy: 0.5)).tap()
        let selected = app.descendants(matching: .any)["ownerAnalytics.trendSelection"].firstMatch
        XCTAssertTrue(selected.waitForExistence(timeout: 10)); reveal(selected, app, towardTop: true)
        capture(app, "physical-p15-" + marker + "-selected-day")
        profileRoot(app)
    }

    func testActualNestedAnalyticsAtApprovedMaximumText() throws {
        guard ProcessInfo.processInfo.environment["UACPhysicalVisualPreferencesApproved"] == "2026-10-27",
              let marker = ProcessInfo.processInfo.environment["UACPhysicalVisualLabel"],
              ["de-light-maximum-opaque", "de-dark-maximum-opaque"].contains(marker) else {
            throw XCTSkip("Exact approved maximum-text variant required")
        }
        let app = XCUIApplication(); openAnalytics(app)
        let period = app.buttons["ownerAnalytics.periodPicker"].firstMatch
        reveal(period, app); period.tap()
        let thirty = app.buttons["30 Tage"].firstMatch
        XCTAssertTrue(thirty.waitForExistence(timeout: 10)); thirty.tap()
        XCTAssertTrue(app.descendants(matching: .any)["ownerAnalytics.updatedAt"].firstMatch.waitForExistence(timeout: 30))
        for type in ["news", "event", "organization"] {
            let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "ownerAnalytics.content." + type + ".")).firstMatch
            reveal(row, app); row.tap()
            let detailPeriod = app.buttons["ownerAnalytics.detail.periodPicker"].firstMatch
            XCTAssertTrue(detailPeriod.waitForExistence(timeout: 20))
            reveal(detailPeriod, app); capture(app, "physical-p15-" + marker + "-" + type + "-detail-header")
            detailPeriod.tap()
            let seven = app.buttons["7 Tage"].firstMatch
            XCTAssertTrue(seven.waitForExistence(timeout: 10)); seven.tap()
            reveal(detailPeriod, app); detailPeriod.tap()
            let thirty = app.buttons["30 Tage"].firstMatch
            XCTAssertTrue(thirty.waitForExistence(timeout: 10)); thirty.tap()
            let metricID = type == "organization" ? "ownerAnalytics.metric.person.crop.rectangle" : "ownerAnalytics.metric.eye"
            for _ in 0..<48 {
                if app.descendants(matching: .any).matching(identifier: metricID).allElementsBoundByIndex.contains(where: { $0.isHittable }) { break }
                app.swipeUp()
            }
            waitForForegroundMetric(metricID, app)
            capture(app, "physical-p15-" + marker + "-" + type + "-detail-metrics")
            let region = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", "ownerAnalytics.detail.region.")).firstMatch
            if region.exists { reveal(region, app); capture(app, "physical-p15-" + marker + "-" + type + "-detail-regions") }
            popOne(app)
            XCTAssertTrue(app.textFields["ownerAnalytics.search"].firstMatch.exists)
        }
        profileRoot(app)
    }

    func testActualAnalyticsLandscapeAndReturn() {
        let app = XCUIApplication(); openAnalytics(app)
        defer { XCUIDevice.shared.orientation = .portrait }
        let thirty = app.buttons["30 днів"].firstMatch
        reveal(thirty, app); thirty.tap()
        XCTAssertTrue(app.descendants(matching: .any)["ownerAnalytics.updatedAt"].firstMatch.waitForExistence(timeout: 30))
        let daily = app.buttons["ownerAnalytics.bannerOverview"].firstMatch
        reveal(daily, app); daily.tap()
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "label MATCHES %@", "[0-9]{4}-[0-9]{2}-[0-9]{2}.*"))
        XCTAssertGreaterThan(rows.count, 0, "Actual UTC day rows expand")
        reveal(rows.firstMatch, app); capture(app, "physical-p15-actual-banner-utc-day-rows")
        reveal(daily, app, towardTop: true); daily.tap()
        XCTAssertEqual(rows.count, 0, "UTC day disclosure collapses")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.frame.width > app.frame.height }, object: nil)], timeout: 15), .completed)
        let chart = app.descendants(matching: .any)["ownerAnalytics.trendChart"].firstMatch
        reveal(chart, app)
        let geometry = XCTAttachment(string: "Window: \(app.frame); chart: \(chart.frame)")
        geometry.name = "physical-p15-landscape-chart-initial-geometry"; geometry.lifetime = .keepAlways; add(geometry)
        for _ in 0..<12 {
            let frame = chart.frame
            if frame.minY > 80 && frame.maxY < app.frame.height - 60 { break }
            let targetTop = min(max(frame.minY, 100), app.frame.height - 80 - frame.height)
            let delta = max(-80, min(80, targetTop - frame.minY))
            // Drag in the card padding beside the interactive chart, while
            // remaining inside the actual centred report scroll column.
            let from = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(.init(dx: max(8, frame.minX - 8), dy: app.frame.height * 0.55))
            from.press(forDuration: 0.05, thenDragTo: from.withOffset(.init(dx: 0, dy: delta)), withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        let finalGeometry = XCTAttachment(string: "Window: \(app.frame); chart: \(chart.frame)")
        finalGeometry.name = "physical-p15-landscape-chart-final-geometry"; finalGeometry.lifetime = .keepAlways; add(finalGeometry)
        XCTAssertGreaterThan(chart.frame.minY, 80)
        XCTAssertLessThan(chart.frame.maxY, app.frame.height - 60)
        capture(app, "physical-p15-actual-landscape-chart")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.frame.height > app.frame.width }, object: nil)], timeout: 15), .completed)
        capture(app, "physical-p15-actual-restored-portrait")
        profileRoot(app)
    }

    func testActualPublicationControlReadOnlyTabsAndSheets() {
        let app = XCUIApplication(); profileRoot(app)
        let entry = app.buttons["profile.contentPlanning"].firstMatch
        reveal(entry, app); entry.tap()
        let day = app.buttons["publicationControl.day"].firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 40))
        reveal(day, app); capture(app, "physical-p16-actual-overview")
        let originalDay = day.label
        day.tap()
        XCTAssertTrue(app.descendants(matching: .any)["publicationControl.calendar"].firstMatch.waitForExistence(timeout: 10))
        capture(app, "physical-p16-actual-calendar")
        let cancel = app.buttons.matching(NSPredicate(format: "label IN %@", ["Скасувати", "Abbrechen", "Cancel"])).firstMatch
        XCTAssertTrue(cancel.exists); cancel.tap()
        XCTAssertEqual(day.label, originalDay)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Vienna")!
        let today = calendar.component(.day, from: Date())
        func chooseDay(_ number: Int) {
            day.tap()
            XCTAssertTrue(app.buttons["publicationControl.calendar.done"].waitForExistence(timeout: 10))
            let cell = app.buttons.matching(NSPredicate(format: "label MATCHES %@", ".*(?<![0-9])\(number)(?![0-9]).*")).firstMatch
            XCTAssertTrue(cell.waitForExistence(timeout: 10)); cell.tap()
            app.buttons["publicationControl.calendar.done"].tap()
        }
        chooseDay(max(1, today - 1))
        if today > 1 { XCTAssertNotEqual(day.label, originalDay) }
        capture(app, "physical-p16-actual-confirmed-previous-day")
        for (kind, title) in [("news", "Новини"), ("event", "Події")] {
            let loading = app.descendants(matching: .any)["publicationControl.loading.items"].firstMatch
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: loading)], timeout: 40), .completed)
            let items = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "publicationControl.item.", title)).allElementsBoundByIndex
            if let item = items.first(where: { $0.isEnabled }) {
                let contentID = String(item.identifier.dropFirst("publicationControl.item.".count))
                reveal(item, app); item.tap()
                let marker = kind == "news" ? "news.like." + contentID : "event.schedule.header"
                XCTAssertTrue(app.descendants(matching: .any)[marker].firstMatch.waitForExistence(timeout: 30))
                capture(app, "physical-p16-actual-opened-" + kind + "-" + contentID)
                popOne(app)
                XCTAssertTrue(day.exists)
            } else {
                let note = XCTAttachment(string: "No enabled real " + kind + " item in this actual day page; no synthetic production content created.")
                note.name = "physical-p16-no-real-" + kind + "-in-day-page"; note.lifetime = .keepAlways; add(note)
            }
        }
        for section in ["items", "regions", "issues", "history"] {
            let tab = app.buttons["publicationControl.tab." + section].firstMatch
            reveal(tab, app); tab.tap()
            let loading = app.descendants(matching: .any)["publicationControl.loading." + (section == "history" ? "runs" : "items")].firstMatch
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: loading)], timeout: 40), .completed)
            capture(app, "physical-p16-actual-tab-" + section)
            let tree = XCTAttachment(string: app.debugDescription); tree.name = "physical-p16-actual-hierarchy-" + section; tree.lifetime = .keepAlways; add(tree)
        }
        let region = app.buttons["publicationControl.region"].firstMatch
        reveal(region, app); region.tap()
        let tirol = app.buttons["publicationControl.region.tirol"].firstMatch
        XCTAssertTrue(tirol.waitForExistence(timeout: 10)); reveal(tirol, app); tirol.tap()
        reveal(region, app); capture(app, "physical-p16-actual-tirol-history")
        region.tap()
        let all = app.buttons["publicationControl.region.all"].firstMatch
        reveal(all, app, towardTop: true); all.tap()
        reveal(region, app); capture(app, "physical-p16-actual-all-regions-restored")
        let itemsTab = app.buttons["publicationControl.tab.items"].firstMatch
        reveal(itemsTab, app); itemsTab.tap()
        reveal(day, app, towardTop: true); chooseDay(today)
        XCTAssertEqual(day.label, originalDay)
        profileRoot(app)
    }

    func testActualPublicationSecondPageEventAndReportDisclosures() throws {
        let app = XCUIApplication(); profileRoot(app)
        let entry = app.buttons["profile.contentPlanning"].firstMatch
        reveal(entry, app); entry.tap()
        let day = app.buttons["publicationControl.day"].firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 40))
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/Vienna")!
        let today = calendar.component(.day, from: Date())
        XCTAssertGreaterThan(today, 1, "Named actual month-day acceptance")
        day.tap()
        let previous = app.buttons.matching(NSPredicate(format: "label MATCHES %@", ".*(?<![0-9])\(today - 1)(?![0-9]).*")).firstMatch
        XCTAssertTrue(previous.waitForExistence(timeout: 10)); previous.tap()
        app.buttons["publicationControl.calendar.done"].tap()
        let more = app.buttons["Показати ще"].firstMatch
        reveal(more, app); more.tap()
        let loading = app.descendants(matching: .any)["publicationControl.loading.items"].firstMatch
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: loading)], timeout: 40), .completed)
        let eventQuery = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "publicationControl.item.", "Події"))
        var availableEvent: XCUIElement?
        // Lazy rows appear in AX as they enter the viewport; absence from the
        // current snapshot does not mean an appended page has no event data.
        for page in 0..<3 {
            for _ in 0..<32 {
                if let candidate = eventQuery.allElementsBoundByIndex.first(where: { $0.isEnabled }) { availableEvent = candidate; break }
                app.swipeUp()
            }
            if availableEvent != nil { break }
            guard page < 2, more.exists, more.isEnabled else { break }
            reveal(more, app); more.tap()
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: loading)], timeout: 40), .completed)
        }
        let event = try XCTUnwrap(availableEvent, "An available actual event must be found after traversing bounded day pages")
        reveal(event, app); capture(app, "physical-p16-actual-second-page-event-row"); event.tap()
        waitForActualEventSchedule(app)
        capture(app, "physical-p16-actual-second-page-event-detail"); popOne(app)
        for (section, prefix) in [("issues", "Технічні подробиці"), ("history", "Подробиці проходу")] {
            let tab = app.buttons["publicationControl.tab." + section].firstMatch
            reveal(tab, app, towardTop: true); tab.tap()
            let disclosure = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
            reveal(disclosure, app); disclosure.tap()
            capture(app, "physical-p16-actual-expanded-" + section)
            disclosure.tap()
        }
        profileRoot(app)
    }

    func testActualOpenMultisessionEventAndReportDisclosures() {
        let app = XCUIApplication(); app.activate()
        let actualTitle = app.staticTexts["Spooky Halloween Days у Sonnentherme"].firstMatch
        XCTAssertTrue(actualTitle.waitForExistence(timeout: 10)); XCTAssertTrue(actualTitle.isHittable)
        waitForActualEventSchedule(app)
        capture(app, "physical-p16-actual-loaded-multisession-event")
        popOne(app)
        XCTAssertTrue(app.buttons["publicationControl.day"].firstMatch.waitForExistence(timeout: 10))
        for (section, prefix) in [("issues", "Технічні подробиці"), ("history", "Подробиці проходу")] {
            let tab = app.buttons["publicationControl.tab." + section].firstMatch
            reveal(tab, app, towardTop: true); tab.tap()
            let disclosure = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
            reveal(disclosure, app); disclosure.tap()
            capture(app, "physical-p16-actual-confirmed-expanded-" + section)
            disclosure.tap()
        }
        profileRoot(app)
    }

    private func waitForActualEventSchedule(_ app: XCUIApplication) {
        let ready = NSPredicate { _, _ in
            app.descendants(matching: .any)["event.schedule.header"].firstMatch.exists
                || app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Дати та сеанси")).firstMatch.exists
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 30), .completed)
    }

    func testActualPublicationAtApprovedMaximumText() throws {
        guard ProcessInfo.processInfo.environment["UACPhysicalVisualPreferencesApproved"] == "2026-10-27",
              ProcessInfo.processInfo.environment["UACPhysicalVisualLabel"] == "de-light-maximum-opaque" else {
            throw XCTSkip("Approved German/light/max/opaque variant required")
        }
        let app = XCUIApplication(); profileRoot(app)
        let entry = app.buttons["profile.contentPlanning"].firstMatch
        reveal(entry, app); entry.tap()
        let day = app.buttons["publicationControl.day"].firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 40)); reveal(day, app)
        capture(app, "physical-p16-de-light-maximum-date-overview")
        day.tap()
        let done = app.buttons["publicationControl.calendar.done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 10)); capture(app, "physical-p16-de-light-maximum-calendar"); done.tap()
        for section in ["items", "regions", "issues", "history"] {
            let tab = app.buttons["publicationControl.tab." + section].firstMatch
            reveal(tab, app); tab.tap()
            capture(app, "physical-p16-de-light-maximum-tab-" + section)
            app.swipeUp(); capture(app, "physical-p16-de-light-maximum-body-" + section)
        }
        let region = app.buttons["publicationControl.region"].firstMatch
        reveal(region, app, towardTop: true); region.tap()
        let lowerAustria = app.buttons["publicationControl.region.niederoesterreich"].firstMatch
        XCTAssertTrue(lowerAustria.waitForExistence(timeout: 10)); reveal(lowerAustria, app)
        capture(app, "physical-p16-de-light-maximum-long-region-option"); lowerAustria.tap()
        reveal(region, app); capture(app, "physical-p16-de-light-maximum-selected-long-region")
        region.tap()
        let all = app.buttons["publicationControl.region.all"].firstMatch
        reveal(all, app, towardTop: true); all.tap()
        profileRoot(app)
    }

    func testActualPublicationSettledDisclosures() {
        let app = XCUIApplication(); profileRoot(app)
        let entry = app.buttons["profile.contentPlanning"].firstMatch
        reveal(entry, app); entry.tap()
        XCTAssertTrue(app.buttons["publicationControl.day"].firstMatch.waitForExistence(timeout: 30))
        for (section, prefix) in [("issues", "Технічні подробиці"), ("history", "Подробиці проходу")] {
            let tab = app.buttons["publicationControl.tab." + section].firstMatch
            reveal(tab, app, towardTop: true); tab.tap()
            let disclosure = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
            reveal(disclosure, app); disclosure.tap()
            // Record the settled layout separately from the immediate transition frame.
            Thread.sleep(forTimeInterval: 1.5)
            capture(app, "physical-p16-settled-expanded-" + section)
            app.swipeUp()
            capture(app, "physical-p16-settled-expanded-scrolled-" + section)
            reveal(disclosure, app, towardTop: true); disclosure.tap()
        }
        profileRoot(app)
    }

    func testActualOwnerJournalReadOnlyNavigation() {
        let app = XCUIApplication(); profileRoot(app)
        let entry = app.buttons["profile.owner.systemLogs"].firstMatch
        reveal(entry, app); entry.tap()
        let search = app.textFields["Пошук у журналі"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 30))
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "systemLogs.log."))
        capture(app, "physical-p17-actual-owner-journal-overview")
        reveal(rows.firstMatch, app)
        capture(app, "physical-p17-actual-owner-journal-loaded")
        let row = rows.firstMatch
        reveal(row, app); row.tap()
        XCTAssertTrue(app.staticTexts["Деталі запису"].firstMatch.waitForExistence(timeout: 15))
        capture(app, "physical-p17-actual-existing-record-detail")
        let technical = app.buttons["Технічні подробиці"].firstMatch
        reveal(technical, app); technical.tap()
        Thread.sleep(forTimeInterval: 1.5)
        capture(app, "physical-p17-actual-existing-record-technical")
        popOne(app)
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        profileRoot(app)
    }

    func testActualControlledJournalPushTargetAndReview() {
        let app = XCUIApplication(); app.activate()
        XCTAssertTrue(app.staticTexts["Деталі запису"].firstMatch.waitForExistence(timeout: 20))
        let target = app.staticTexts["uac-test-p17-physical-20261028"].firstMatch
        reveal(target, app)
        XCTAssertTrue(target.isHittable)
        let title = app.staticTexts["UAC TEST P17 — контрольна перевірка сповіщення"].firstMatch
        reveal(title, app, towardTop: true)
        XCTAssertTrue(title.isHittable, "Only the explicitly controlled synthetic entry may be reviewed")
        capture(app, "physical-p17-exact-controlled-push-target")
        let mark = app.buttons["Позначити як переглянуте"].firstMatch
        reveal(mark, app, towardTop: true)
        XCTAssertTrue(mark.isEnabled); mark.tap()
        XCTAssertTrue(mark.waitForNonExistence(timeout: 20))
        let reviewed = app.staticTexts["Переглянуто"].firstMatch
        reveal(reviewed, app, towardTop: true)
        capture(app, "physical-p17-controlled-entry-marked-reviewed")
    }

    func testActualLegalManagementReadersAndHistoryReadOnly() {
        let app = XCUIApplication(); profileRoot(app)
        let entry = app.buttons["profile.owner.legalDocuments"].firstMatch
        reveal(entry, app); entry.tap()
        for type in ["terms", "privacy", "organizationRules"] {
            let version = app.descendants(matching: .any)["legal.manage.version." + type].firstMatch
            XCTAssertTrue(version.waitForExistence(timeout: 30)); reveal(version, app)
            capture(app, "physical-p18-actual-management-" + type)
            let active = app.buttons["legal.manage.active." + type].firstMatch
            reveal(active, app); active.tap()
            let languages = app.segmentedControls.firstMatch
            XCTAssertTrue(languages.waitForExistence(timeout: 15))
            for index in 0..<2 {
                let choice = languages.buttons.element(boundBy: index)
                reveal(choice, app, towardTop: true); choice.tap()
                Thread.sleep(forTimeInterval: 0.6)
                capture(app, "physical-p18-actual-reader-" + type + "-locale-" + String(index))
                app.swipeUp()
                capture(app, "physical-p18-actual-reader-body-" + type + "-locale-" + String(index))
            }
            popOne(app)
            let history = app.buttons["legal.manage.history." + type].firstMatch
            reveal(history, app); history.tap()
            let read = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "legal.history.read.")).firstMatch
            XCTAssertTrue(read.waitForExistence(timeout: 30)); reveal(read, app)
            capture(app, "physical-p18-actual-history-" + type)
            read.tap()
            XCTAssertTrue(app.segmentedControls.firstMatch.waitForExistence(timeout: 15))
            capture(app, "physical-p18-actual-history-reader-" + type)
            popOne(app); popOne(app)
        }
        profileRoot(app)
    }

    func testActualLegacyLegalVersionAndComparison() {
        let app = XCUIApplication(); profileRoot(app)
        let entry = app.buttons["profile.owner.legalDocuments"].firstMatch
        reveal(entry, app); entry.tap()
        let history = app.buttons["legal.manage.history.terms"].firstMatch
        XCTAssertTrue(history.waitForExistence(timeout: 30)); reveal(history, app); history.tap()
        let latest = app.buttons["legal.history.read.2026.15"].firstMatch
        XCTAssertTrue(latest.waitForExistence(timeout: 30))
        let legacy = app.buttons["legal.history.read.2026.202604"].firstMatch
        reveal(legacy, app); legacy.tap()
        XCTAssertTrue(app.segmentedControls.firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "2026.202604")).firstMatch.exists)
        capture(app, "physical-p18-actual-immutable-legacy-version-reader")
        app.swipeUp(); capture(app, "physical-p18-actual-legacy-version-body")
        popOne(app)
        let compare = app.buttons["legal.history.compare.2026.202604"].firstMatch
        reveal(compare, app); compare.tap()
        XCTAssertTrue(app.segmentedControls.firstMatch.waitForExistence(timeout: 15))
        capture(app, "physical-p18-actual-legacy-to-current-comparison")
        popOne(app); popOne(app); profileRoot(app)
    }

    func testActualLegalEditorLandscapeLocalKeyboard() {
        let app = XCUIApplication(); app.activate()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.frame.width > app.frame.height }, object: nil)], timeout: 10), .completed)
        testActualLegalEditorKeyboardPreviewAndLeaveWithoutSaving()
    }

    func testActualLegalEditorKeyboardPreviewAndLeaveWithoutSaving() {
        let app = XCUIApplication(); profileRoot(app)
        let entry = app.buttons["profile.owner.legalDocuments"].firstMatch
        reveal(entry, app); entry.tap()
        let edit = app.buttons["legal.manage.edit.terms"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 30)); reveal(edit, app); edit.tap()
        let title = app.textFields["legal.edit.title"].firstMatch
        reveal(title, app); title.tap(); title.typeText(" UAC TEST18")
        XCTAssertTrue((title.value as? String ?? "").contains("UAC TEST18"))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        XCTAssertLessThan(title.frame.maxY, app.keyboards.firstMatch.frame.minY)
        capture(app, "physical-p18-actual-local-title-keyboard")
        app.coordinate(withNormalizedOffset: .init(dx: 0.02, dy: 0.35)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 10))
        let locale = app.segmentedControls.firstMatch
        reveal(locale, app, towardTop: true); locale.buttons.element(boundBy: 1).tap()
        reveal(title, app)
        XCTAssertFalse((title.value as? String ?? "").contains("UAC TEST18"), "German edit must not leak into Ukrainian")
        title.tap(); title.typeText(" UAC TEST18UK")
        XCTAssertTrue((title.value as? String ?? "").contains("UAC TEST18UK"))
        app.coordinate(withNormalizedOffset: .init(dx: 0.02, dy: 0.35)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 10))
        reveal(locale, app, towardTop: true); locale.buttons.element(boundBy: 0).tap()
        reveal(title, app)
        XCTAssertTrue((title.value as? String ?? "").contains("UAC TEST18"))
        XCTAssertFalse((title.value as? String ?? "").contains("UAC TEST18UK"))
        let body = app.textViews["legal.edit.body"].firstMatch
        reveal(body, app); body.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        let save = app.buttons["legal.edit.save"].firstMatch
        let visibleInput = NSPredicate { _, _ in
            body.frame.maxY < min(save.frame.minY, app.keyboards.firstMatch.frame.minY)
        }
        let visibleResult = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: visibleInput, object: nil)], timeout: 10)
        capture(app, "physical-p18-actual-body-keyboard")
        XCTAssertEqual(visibleResult, .completed)
        XCTAssertGreaterThanOrEqual(body.frame.minY, app.frame.minY)
        app.coordinate(withNormalizedOffset: .init(dx: 0.02, dy: 0.35)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 10))
        let actions = app.buttons["legal.edit.actions"].firstMatch
        // The editor actions live beside Save in the pinned bottom bar.
        XCTAssertTrue(actions.waitForExistence(timeout: 10)); XCTAssertTrue(actions.isHittable); actions.tap()
        let preview = app.buttons["legal.edit.preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 10)); preview.tap()
        let done = app.buttons["Готово"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "UAC TEST18")).firstMatch.exists)
        capture(app, "physical-p18-actual-local-draft-preview"); done.tap()
        popOne(app)
        let leave = app.buttons["legal.edit.leaveUnsaved"].firstMatch
        XCTAssertTrue(leave.waitForExistence(timeout: 10))
        capture(app, "physical-p18-actual-local-close-confirmation")
        let cancel = app.buttons["Скасувати"].firstMatch
        XCTAssertTrue(cancel.exists); cancel.tap()
        XCTAssertTrue(title.exists)
        popOne(app); XCTAssertTrue(leave.waitForExistence(timeout: 10)); leave.tap()
        XCTAssertTrue(app.buttons["legal.manage.active.terms"].firstMatch.waitForExistence(timeout: 15))
        profileRoot(app)
    }

    func testActualOwnerOwnLegalEvidenceReadOnly() {
        let app = XCUIApplication(); profileRoot(app)
        let entry = app.buttons["profile.owner.legalEvidence"].firstMatch
        reveal(entry, app); entry.tap()
        let search = app.textFields["legalEvidence.accountSearch"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 20)); reveal(search, app)
        search.tap(); search.typeText("4jk3piOYIWMNsBf5gUAaOMpaQc83\n")
        let owner = app.buttons["legalEvidence.account.4jk3piOYIWMNsBf5gUAaOMpaQc83"].firstMatch
        reveal(owner, app); capture(app, "physical-p18-actual-exact-owner-evidence-search"); owner.tap()
        let summary = app.descendants(matching: .any)["legalEvidence.summary"].firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 30)); reveal(summary, app)
        capture(app, "physical-p18-actual-own-legal-evidence-summary")
        let version = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "legalEvidence.readVersion.")).firstMatch
        reveal(version, app); version.tap()
        XCTAssertTrue(app.segmentedControls.firstMatch.waitForExistence(timeout: 30))
        capture(app, "physical-p18-actual-own-evidence-exact-version")
        popOne(app); popOne(app); profileRoot(app)
    }

    func testActualOwnerJournalSearchAndFiltersReadOnly() {
        let app = XCUIApplication(); profileRoot(app)
        let entry = app.buttons["profile.owner.systemLogs"].firstMatch
        reveal(entry, app); entry.tap()
        let search = app.textFields["Пошук у журналі"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 30))
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "systemLogs.log."))
        reveal(rows.firstMatch, app)
        reveal(search, app, towardTop: true); search.tap(); search.typeText("UAC-P17-NO-MATCH-20261028\n")
        let empty = app.staticTexts["Немає записів за вибраними фільтрами"].firstMatch
        reveal(empty, app)
        XCTAssertTrue(rows.firstMatch.waitForNonExistence(timeout: 30))
        capture(app, "physical-p17-actual-no-match-query")
        let reset = app.buttons["Скинути"].firstMatch
        XCTAssertTrue(reset.waitForExistence(timeout: 15)); reveal(reset, app, towardTop: true); reset.tap()
        reveal(rows.firstMatch, app)
        let advanced = app.buttons["Розширені фільтри"].firstMatch
        reveal(advanced, app, towardTop: true); advanced.tap()
        let done = app.buttons["Готово"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        capture(app, "physical-p17-actual-advanced-filter-sheet")
        done.tap()
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        capture(app, "physical-p17-actual-reset-restored-records")
        profileRoot(app)
    }

    func testActualSupportLandscapeLocalKeyboard() {
        let app = XCUIApplication(); app.activate()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.frame.width > app.frame.height }, object: nil)], timeout: 10), .completed)
        testActualSupportLocalMessageKeyboardAndDiscard()
    }

    func testActualSupportLandscapeURLKeyboardReadOnly() {
        let app = XCUIApplication(); profileRoot(app)
        let entry = app.buttons["profile.owner.donationSettings"].firstMatch
        reveal(entry, app); entry.tap()
        let url = app.textFields["donation.edit.url"].firstMatch
        XCTAssertTrue(url.waitForExistence(timeout: 30))
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.frame.width > app.frame.height }, object: nil)], timeout: 10), .completed)
        reveal(url, app); url.tap()
        let visible = NSPredicate { _, _ in app.keyboards.firstMatch.exists && app.keyboards.firstMatch.frame.intersection(app.frame).height > 100 }
        let result = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: visible, object: nil)], timeout: 10)
        capture(app, "physical-p19-landscape-url-keyboard")
        XCTAssertEqual(result, .completed)
        app.coordinate(withNormalizedOffset: .init(dx: 0.02, dy: 0.35)).tap()
        profileRoot(app)
    }

    func testActualSupportExternalLinkReturn() throws {
        let app = XCUIApplication(); profileRoot(app)
        let entry = app.buttons["profile.owner.donationSettings"].firstMatch
        reveal(entry, app); entry.tap()
        let url = app.textFields["donation.edit.url"].firstMatch
        XCTAssertTrue(url.waitForExistence(timeout: 30)); reveal(url, app)
        let original = url.value as? String ?? ""
        XCTAssertTrue(original.hasPrefix("https://www.paypal.me/"))
        let merchant = String(original.split(separator: "/").last ?? "").lowercased()
        XCTAssertFalse(merchant.isEmpty)
        let link = app.buttons["donation.edit.checkLink"].firstMatch
        reveal(link, app); link.tap()
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        // Bundle verified from the installed app inventory. A Universal Link
        // may enter this app's authentication gate instead of Safari.
        let paypal = XCUIApplication(bundleIdentifier: "com.yourcompany.PPClient")
        let external = NSPredicate { _, _ in safari.state == .runningForeground || paypal.state == .runningForeground }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: external, object: nil)], timeout: 15), .completed)
        if paypal.state == .runningForeground {
            // Never act on financial authentication or payment controls.
            app.activate()
            XCTAssertTrue(url.waitForExistence(timeout: 15)); reveal(url, app)
            XCTAssertEqual(url.value as? String, original)
            XCTAssertFalse(app.buttons["donation.edit.save"].firstMatch.isEnabled)
            capture(app, "physical-p19-native-handler-return-preserves-editor")
            profileRoot(app)
            throw XCTSkip("Native PayPal handoff/return checked; exact merchant screen requires separate human authentication and is not accepted as verified")
        }
        let correctAddress = NSPredicate { _, _ in
            guard safari.state == .runningForeground else { return false }
            return safari.textFields.allElementsBoundByIndex.contains { field in
                let value = (field.value as? String ?? "").lowercased()
                return value.contains("paypal.me/" + merchant) || value.contains("paypal.com/paypalme/" + merchant)
            }
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: correctAddress, object: nil)], timeout: 30), .completed)
        capture(safari, "physical-p19-actual-external-paypal-merchant-address")
        app.activate()
        XCTAssertTrue(url.waitForExistence(timeout: 15)); reveal(url, app)
        XCTAssertEqual(url.value as? String, original)
        XCTAssertFalse(app.buttons["donation.edit.save"].firstMatch.isEnabled)
        capture(app, "physical-p19-actual-return-from-external-link")
        profileRoot(app)
    }

    func testActualSupportPreviewHeaderAndContentReadOnly() {
        let app = XCUIApplication(); profileRoot(app)
        let entry = app.buttons["profile.owner.donationSettings"].firstMatch
        reveal(entry, app); entry.tap()
        XCTAssertTrue(app.textFields["donation.edit.url"].firstMatch.waitForExistence(timeout: 30))
        let preview = app.buttons["donation.preview.toggle"].firstMatch
        reveal(preview, app)
        XCTAssertLessThanOrEqual(preview.frame.maxX, app.frame.maxX)
        XCTAssertGreaterThanOrEqual(preview.frame.minX, app.frame.minX)
        XCTAssertFalse(app.buttons["donation.edit.save"].firstMatch.isEnabled)
        capture(app, "physical-p19-actual-readonly-preview-header-collapsed")
        preview.tap()
        let visibility = app.staticTexts["donation.preview.visibility"].firstMatch
        XCTAssertTrue(visibility.waitForExistence(timeout: 10)); reveal(visibility, app)
        capture(app, "physical-p19-actual-readonly-preview-expanded-visibility")
        let language = app.segmentedControls["donation.preview.language"].firstMatch
        reveal(language, app)
        XCTAssertEqual(language.buttons.count, 2)
        capture(app, "physical-p19-actual-readonly-preview-expanded-language")
        XCTAssertFalse(app.buttons["donation.edit.save"].firstMatch.isEnabled)
        profileRoot(app)
    }

    func testActualSupportLocalMessageKeyboardAndDiscard() {
        let app = XCUIApplication(); profileRoot(app)
        let entry = app.buttons["profile.owner.donationSettings"].firstMatch
        reveal(entry, app); entry.tap()
        let language = app.segmentedControls["donation.edit.language"].firstMatch
        XCTAssertTrue(language.waitForExistence(timeout: 30)); reveal(language, app)
        language.buttons.element(boundBy: 0).tap()
        let title = app.textFields["donation.edit.title.uk"].firstMatch
        let message = app.textViews["donation.edit.message.uk"].firstMatch
        reveal(title, app); let originalTitle = title.value as? String
        reveal(message, app); let originalMessage = message.value as? String
        let save = app.buttons["donation.edit.save"].firstMatch
        message.tap()
        waitForVisibleSoftwareKeyboard(app)
        XCTAssertLessThan(message.frame.maxY, min(save.frame.minY, app.keyboards.firstMatch.frame.minY))
        message.typeText(" UAC TEST19")
        XCTAssertTrue((message.value as? String ?? "").contains("UAC TEST19"))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        capture(app, "physical-p19-actual-local-message-keyboard")
        XCTAssertLessThan(message.frame.maxY, min(save.frame.minY, app.keyboards.firstMatch.frame.minY))
        XCTAssertGreaterThanOrEqual(message.frame.minY, app.frame.minY)
        app.coordinate(withNormalizedOffset: .init(dx: 0.02, dy: 0.35)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 10))
        reveal(title, app, towardTop: true); title.tap()
        waitForVisibleSoftwareKeyboard(app)
        XCTAssertLessThan(title.frame.maxY, min(save.frame.minY, app.keyboards.firstMatch.frame.minY))
        title.typeText(" UAC TEST19")
        XCTAssertTrue((title.value as? String ?? "").contains("UAC TEST19"))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        XCTAssertLessThan(title.frame.maxY, min(save.frame.minY, app.keyboards.firstMatch.frame.minY))
        capture(app, "physical-p19-actual-local-title-keyboard")
        app.coordinate(withNormalizedOffset: .init(dx: 0.02, dy: 0.35)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 10))
        let preview = app.buttons["donation.preview.toggle"].firstMatch
        reveal(preview, app); capture(app, "physical-p19-actual-local-preview-collapsed")
        preview.tap()
        XCTAssertTrue(app.staticTexts["donation.preview.visibility"].firstMatch.waitForExistence(timeout: 10))
        capture(app, "physical-p19-actual-local-preview-expanded")
        popOne(app)
        let discard = app.buttons["donation.confirm.discard"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 10)); capture(app, "physical-p19-actual-local-close-confirmation")
        app.buttons["Скасувати"].firstMatch.tap()
        XCTAssertTrue(title.exists)
        popOne(app); XCTAssertTrue(discard.waitForExistence(timeout: 10)); discard.tap()
        reveal(entry, app); entry.tap()
        XCTAssertTrue(language.waitForExistence(timeout: 30)); reveal(language, app)
        language.buttons.element(boundBy: 0).tap()
        reveal(title, app); XCTAssertEqual(title.value as? String, originalTitle)
        reveal(message, app); XCTAssertEqual(message.value as? String, originalMessage)
        XCTAssertFalse(save.isEnabled)
        capture(app, "physical-p19-actual-local-discard-independent-reopen")
        profileRoot(app)
    }

    func testActualSupportReadOnlyFieldsKeyboardAndPreview() {
        let app = XCUIApplication(); profileRoot(app)
        let entry = app.buttons["profile.owner.donationSettings"].firstMatch
        reveal(entry, app); entry.tap()
        let url = app.textFields["donation.edit.url"].firstMatch
        XCTAssertTrue(url.waitForExistence(timeout: 30)); reveal(url, app)
        let originalURL = url.value as? String
        let enabled = app.switches["donation.edit.enabled"].firstMatch
        let originalEnabled = enabled.value as? String
        let save = app.buttons["donation.edit.save"].firstMatch
        XCTAssertFalse(save.isEnabled)
        capture(app, "physical-p19-actual-confirmed-owner-support")
        url.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        XCTAssertLessThan(url.frame.maxY, app.keyboards.firstMatch.frame.minY)
        capture(app, "physical-p19-actual-url-keyboard")
        app.swipeDown()
        if app.keyboards.firstMatch.exists {
            let title = app.staticTexts["donation.saved.visibility"].firstMatch
            reveal(title, app, towardTop: true); title.tap()
        }
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 10))
        let language = app.segmentedControls["donation.edit.language"].firstMatch
        for (index, code) in [(0, "uk"), (1, "de")] {
            reveal(language, app); language.buttons.element(boundBy: index).tap()
            let title = app.textFields["donation.edit.title." + code].firstMatch
            reveal(title, app); capture(app, "physical-p19-actual-fields-" + code)
        }
        let preview = app.buttons["donation.preview.toggle"].firstMatch
        reveal(preview, app); preview.tap()
        let previewLanguage = app.segmentedControls["donation.preview.language"].firstMatch
        for index in 0..<2 {
            reveal(previewLanguage, app); previewLanguage.buttons.element(boundBy: index).tap()
            app.swipeUp(); capture(app, "physical-p19-actual-preview-" + String(index))
        }
        XCTAssertFalse(save.isEnabled)
        popOne(app)
        reveal(entry, app); entry.tap()
        XCTAssertTrue(url.waitForExistence(timeout: 30))
        XCTAssertEqual(url.value as? String, originalURL)
        XCTAssertEqual(enabled.value as? String, originalEnabled)
        XCTAssertFalse(save.isEnabled)
        capture(app, "physical-p19-actual-support-independent-reopen")
        profileRoot(app)
    }

    private func openAnalytics(_ app: XCUIApplication) {
        profileRoot(app)
        let entry = app.buttons["profile.owner.analytics"].firstMatch
        reveal(entry, app); entry.tap()
        XCTAssertTrue(app.textFields["ownerAnalytics.search"].firstMatch.waitForExistence(timeout: 20))
    }

    private func profileRoot(_ app: XCUIApplication) {
        app.activate()
        for _ in 0..<8 { guard popOne(app, required: false) else { break } }
        let taggedProfile = app.tabBars.buttons["tab.profile"].firstMatch
        let nativeProfile = app.tabBars.buttons.matching(NSPredicate(format: "label IN %@", ["Профіль", "Profil", "Profile"])).firstMatch
        // iOS can recreate native tab items during rotation without retaining
        // the SwiftUI test identifier. Keep the same real tab/selection check.
        let profile = taggedProfile.exists ? taggedProfile : nativeProfile
        XCTAssertTrue(profile.waitForExistence(timeout: 20))
        if profile.isHittable { profile.tap() }
        else {
            let frame = profile.frame.intersection(app.windows.firstMatch.frame)
            XCTAssertGreaterThan(frame.width, 20); XCTAssertGreaterThan(frame.height, 20)
            profile.coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: profile)], timeout: 10), .completed)
        for _ in 0..<8 { guard popOne(app, required: false) else { break } }
        let owner = app.staticTexts["Serlest"].firstMatch
        reveal(owner, app, towardTop: true); XCTAssertTrue(owner.isHittable)
    }

    @discardableResult private func popOne(_ app: XCUIApplication, required: Bool = true) -> Bool {
        let candidates = app.buttons.matching(NSPredicate(format: "label IN %@", ["Назад", "Zurück", "Back"])).allElementsBoundByIndex
        let leadingLimit = app.frame.width > app.frame.height ? app.frame.width * 0.4 : 100
        let back = candidates.first { $0.identifier == "navigation.back" && $0.isHittable }
            ?? candidates.first { $0.isHittable && $0.frame.minX < leadingLimit }
            ?? candidates.first { $0.frame.minX >= 0 && $0.frame.minX < leadingLimit && $0.frame.width > 0 }
        guard let back else { if required { XCTFail("Current read-only screen has no Back control") }; return false }
        // Back belongs to the pinned header, outside the content reveal bounds.
        if !back.isHittable { reveal(back, app, towardTop: true) }
        XCTAssertTrue(back.isHittable); back.tap(); return true
    }

    private func waitForForegroundMetric(_ identifier: String, _ app: XCUIApplication) {
        let ready = NSPredicate { _, _ in
            app.descendants(matching: .any).matching(identifier: identifier).allElementsBoundByIndex.contains { $0.isHittable }
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: ready, object: nil)], timeout: 30), .completed)
    }

    private func reveal(_ element: XCUIElement, _ app: XCUIApplication, towardTop: Bool = false) {
        for _ in 0..<64 {
            if element.exists && element.isHittable && element.frame.midY > 80 && element.frame.midY < app.frame.height - 110 { return }
            let down = towardTop || (element.exists && element.frame.midY < 100)
            // Landscape reports are centred in a readable-width column; the
            // portrait editor gutter is outside that actual scroll surface.
            var x = app.frame.width > app.frame.height ? 0.5 : 0.97
            if app.frame.width > app.frame.height {
                let editor = app.textViews.matching(NSPredicate(format: "identifier == %@ OR identifier BEGINSWITH %@",
                                                               "legal.edit.body", "donation.edit.message.")).firstMatch
                if editor.exists, editor.frame.width > 40, editor.frame.maxX < app.frame.width - 16 {
                    // Drag inside the form card gutter, outside its inner editor.
                    x = (editor.frame.maxX + 8) / app.frame.width
                }
            }
            let compact = app.frame.width > app.frame.height
            app.coordinate(withNormalizedOffset: .init(dx: x, dy: down ? (compact ? 0.44 : 0.35) : (compact ? 0.56 : 0.65)))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: .init(dx: x, dy: down ? (compact ? 0.56 : 0.65) : (compact ? 0.44 : 0.35))), withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTAssertTrue(element.exists && element.isHittable,
                      "Unreached target \(element.identifier), frame \(element.frame), window \(app.frame)")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        XCTAssertEqual(app.state, .runningForeground)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        if self.name.contains("LandscapeLocalKeyboard") {
            XCTAssertGreaterThan(app.frame.width, app.frame.height,
                                 "The physical device must remain landscape throughout the scenario")
        }
        if name.hasSuffix("-keyboard") {
            let geometry = XCTAttachment(string: "app=\(app.frame) keyboard=\(app.keyboards.firstMatch.frame)\n" + app.debugDescription)
            geometry.name = name + "-visible-input-geometry"; geometry.lifetime = .keepAlways; add(geometry)
            let visibleKeyboard = app.keyboards.firstMatch.frame.intersection(app.frame)
            XCTAssertGreaterThan(visibleKeyboard.height, 100,
                                 "An offscreen keyboard AX node is not evidence of visible software input")
            XCTAssertGreaterThan(visibleKeyboard.width, 100)
        }
    }

    private func waitForVisibleSoftwareKeyboard(_ app: XCUIApplication) {
        let visible = NSPredicate { _, _ in
            app.keyboards.firstMatch.exists
                && app.keyboards.firstMatch.frame.intersection(app.frame).height > 100
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: visible, object: nil)], timeout: 10), .completed,
                       "Wait for actual software input and focus scrolling before injecting text")
    }
}
