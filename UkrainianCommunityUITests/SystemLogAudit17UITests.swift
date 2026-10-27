import XCTest
@MainActor final class SystemLogAudit17UITests: XCTestCase {
 override func setUp() { continueAfterFailure=false }
 func testNestedFiltersDetailTechnicalAndCopy() {
  for lang in ["uk","de"] {
   let app=launch(lang,false); let row=app.buttons["systemLogs.log.analytics"].firstMatch
   XCTAssertTrue(row.waitForExistence(timeout:15));capture(app,"standard-dashboard-"+lang)
   let filters=app.buttons[lang == "uk" ? "Розширені фільтри":"Erweiterte Filter"].firstMatch
   reach(filters,app); XCTAssertTrue(filters.exists)
   if !filters.isHittable { let y=min(app.frame.maxY-100,max(130,filters.frame.midY)); app.coordinate(withNormalizedOffset:CGVector(dx:0.92,dy:y/app.frame.height)).press(forDuration:0.1,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.1,dy:y/app.frame.height))) }
   XCTAssertTrue(filters.isHittable);filters.tap();capture(app,"standard-filter-top-"+lang)
   app.swipeUp();app.swipeUp();capture(app,"standard-filter-bottom-"+lang)
   let done=app.buttons[lang == "uk" ? "Готово":"Fertig"].firstMatch;XCTAssertTrue(done.exists);done.tap()
   reach(row,app);row.tap();let title=app.staticTexts[lang == "uk" ? "Деталі запису":"Eintragsdetails"].firstMatch;XCTAssertTrue(title.waitForExistence(timeout:8));capture(app,"standard-detail-"+lang)
   let copy=app.buttons[lang == "uk" ? "Скопіювати деталі":"Details kopieren"].firstMatch;copy.tap();capture(app,"copy-feedback-"+lang)
   let technical=app.buttons[lang == "uk" ? "Технічні подробиці":"Technische Details"].firstMatch;reach(technical,app);XCTAssertTrue(technical.isHittable);technical.tap();capture(app,"technical-expanded-"+lang)
   app.swipeUp();app.swipeUp();capture(app,"technical-fields-"+lang);app.terminate()
  }
 }
 func testLargestTextDashboardAndRecord() {
  for lang in ["uk","de"] {
   let app=launch(lang,true);XCTAssertTrue(app.staticTexts[lang == "uk" ? "Журнал системи":"Systemprotokoll"].firstMatch.waitForExistence(timeout:12));capture(app,"largest-dashboard-top-"+lang)
   let row=app.buttons["systemLogs.log.analytics"].firstMatch;reach(row,app);XCTAssertTrue(row.exists);capture(app,"largest-row-"+lang)
   let y=max(140,min(app.frame.maxY-110,row.frame.minY+60));app.coordinate(withNormalizedOffset:CGVector(dx:0.6,dy:y/app.frame.height)).tap()
   XCTAssertTrue(app.staticTexts[lang == "uk" ? "Деталі запису":"Eintragsdetails"].firstMatch.waitForExistence(timeout:8));capture(app,"largest-detail-top-"+lang);app.swipeUp();capture(app,"largest-detail-body-"+lang);app.terminate()
  }
 }

 func testOwnerCanCancelClearAndSingleDelete() {
  let app=launch("uk",false);let row=app.buttons["systemLogs.log.analytics"].firstMatch
  XCTAssertTrue(row.waitForExistence(timeout:15));let actions=app.buttons["systemLogs.actions"].firstMatch;actions.tap()
  let clear=app.buttons["Очистити журнал"].firstMatch;XCTAssertTrue(clear.waitForExistence(timeout:5));clear.tap()
  XCTAssertTrue(app.staticTexts["Очистити весь журнал?"].firstMatch.waitForExistence(timeout:5));capture(app,"clear-confirmation")
  dismissConfirmation(app);reach(row,app);XCTAssertTrue(row.exists)
  row.press(forDuration:1);let delete=app.buttons["Видалити"].firstMatch;XCTAssertTrue(delete.waitForExistence(timeout:5));delete.tap();capture(app,"delete-confirmation")
  dismissConfirmation(app);XCTAssertTrue(row.exists);app.terminate()
 }
 private func dismissConfirmation(_ app:XCUIApplication) {
  let cancel=app.buttons["Скасувати"].firstMatch
  if cancel.exists {cancel.tap()}else{app.coordinate(withNormalizedOffset:CGVector(dx:0.05,dy:0.1)).tap()}
  XCTAssertTrue(app.buttons["systemLogs.actions"].firstMatch.exists)
 }

 func testAdminLimitedJournalReviewAndOwnerRowExclusion() {
  let app=XCUIApplication();app.launchArguments=["-ui-testing"]
  app.launchEnvironment=["UITestSystemLogDiagnosis":"1","UITestProfileRole":"admin","UITestAppLanguage":"uk","UITestResetUserSettings":"1"]
  app.launch();let row=app.buttons["systemLogs.log.analytics"].firstMatch;XCTAssertTrue(row.waitForExistence(timeout:15))
  XCTAssertTrue(app.staticTexts["Журнал адміністратора"].firstMatch.exists)
  XCTAssertFalse(app.buttons["systemLogs.log.banner"].exists)
  app.buttons["systemLogs.actions"].tap();XCTAssertFalse(app.buttons["Очистити журнал"].exists)
  app.coordinate(withNormalizedOffset:CGVector(dx:0.05,dy:0.1)).tap();reach(row,app);row.tap()
  let review=app.buttons["Позначити як переглянуте"].firstMatch;reach(review,app);XCTAssertTrue(review.isHittable);review.tap()
  let reviewed=app.staticTexts["Переглянуто"].firstMatch
  for _ in 0..<7 { if reviewed.exists && reviewed.isHittable {break};app.swipeDown() }
  capture(app,"admin-after-review")
  let tree=XCTAttachment(string:app.debugDescription);tree.name="admin-after-review-tree";tree.lifetime = .keepAlways;add(tree)
  XCTAssertTrue(reviewed.waitForExistence(timeout:5))
  XCTAssertFalse(app.buttons["Позначити як переглянуте"].exists);capture(app,"admin-reviewed-exact-read");app.terminate()
 }

 func testLargestAdvancedFilterSelectionPersistsAndResets() {
  for lang in ["uk","de"] {
   let app=launch(lang,true)
   let more=app.buttons[lang == "uk" ? "Розширені фільтри":"Erweiterte Filter"].firstMatch
   reach(more,app);XCTAssertTrue(more.isHittable);more.tap()
   let today=app.buttons[lang == "uk" ? "Сьогодні":"Heute"].firstMatch
   reach(today,app);XCTAssertTrue(today.isHittable);today.tap();capture(app,"largest-filters-selection-"+lang)
   let done=app.navigationBars.buttons[lang == "uk" ? "Готово":"Fertig"].firstMatch
   XCTAssertTrue(done.exists);done.tap();reach(more,app);more.tap();reach(today,app);XCTAssertTrue(today.isSelected)
   let reset=app.navigationBars.buttons[lang == "uk" ? "Скинути":"Zurücksetzen"].firstMatch
   XCTAssertTrue(reset.exists);reset.tap();capture(app,"largest-filters-reset-"+lang);done.tap();app.terminate()
  }
 }
 private func launch(_ lang:String,_ largest:Bool)->XCUIApplication {
  let app=XCUIApplication();app.launchArguments=["-ui-testing","-UIPreferredContentSizeCategoryName",largest ? "UICTContentSizeCategoryAccessibilityXXXL":"UICTContentSizeCategoryL"]
  app.launchEnvironment=["UITestSystemLogDiagnosis":"1","UITestForceOwnerSession":"1","UITestAppLanguage":lang,"UITestAppAppearance":lang == "uk" ? "light":"dark","UITestResetUserSettings":"1"];app.launch();return app
 }
 private func reach(_ el:XCUIElement,_ app:XCUIApplication){
  for _ in 0..<14 { if el.exists && el.frame.maxY>130 && el.frame.minY<app.frame.maxY-90{return};if el.exists && el.frame.maxY<130 {app.swipeDown()}else{app.swipeUp()} }
 }
 private func capture(_ app:XCUIApplication,_ name:String){let a=XCTAttachment(screenshot:app.screenshot());a.name="audit17-"+name;a.lifetime = .keepAlways;add(a)}
}
