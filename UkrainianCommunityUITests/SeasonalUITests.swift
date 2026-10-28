import XCTest
import UIKit

@MainActor final class SeasonalUITests: XCTestCase {
    private func launch(scope: String, appearance: String = "light", language: String = "uk", maximum: Bool = false, effects:Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launchEnvironment = ["UITestSeasonal":"1", "UITestSeasonalScope":scope == "custom" ? "home" : scope, "UITestSeasonalCustomArtwork":scope == "custom" ? "1" : "0",
            "UITestForceOwnerSession":"1", "UITestAppLanguage":language,
            "UITestAppAppearance":appearance, "UITestSeasonalMaximum":maximum ? "1":"0", "UITestSeasonalEffects":effects ? "1":"0"]
        app.launch(); return app
    }
    private func shot(_ name: String) {
        let attachment=XCTAttachment(screenshot:XCUIApplication().screenshot());attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)
    }
    func testScenePreservesHeaderPositionAndShowsDescent() throws {
        let off=launch(scope:"home",effects:false)
        let original=off.buttons["seasonal.fixture.bell"]
        XCTAssertTrue(original.waitForExistence(timeout:15));let baseline=original.frame.minY
        off.terminate()
        let on=launch(scope:"home")
        let bell=on.buttons["seasonal.fixture.bell"]
        XCTAssertTrue(bell.waitForExistence(timeout:15))
        XCTAssertEqual(bell.frame.minY,baseline,accuracy:1)
        XCTAssertTrue(bell.isHittable)
        let image=try XCTUnwrap(on.screenshot().image.cgImage)
        let width=image.width,height=image.height,ratio=CGFloat(width)/on.frame.width
        var pixels=[UInt8](repeating:0,count:width*height*4)
        pixels.withUnsafeMutableBytes { buffer in
            let context=CGContext(data:buffer.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,
                space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
        }
        let startY=max(0,Int((bell.frame.midY-28)*ratio)),endY=min(height,Int((bell.frame.midY+28)*ratio))
        var pumpkinPixels=0
        for y in startY..<endY { for x in Int(Double(width)*0.35)..<Int(Double(width)*0.8) {
            let i=(y*width+x)*4
            if pixels[i]>140 && pixels[i+1]>35 && pixels[i+1]<160 && pixels[i+2]<90 { pumpkinPixels += 1 }
        } }
        XCTAssertGreaterThan(pumpkinPixels,60,"Native 3D pumpkin must actually render beside the logo")
        shot("SeasonalDepth-Root-Initial")
        // Observe the native scene at the bottom of the spider's descent.
        Thread.sleep(forTimeInterval:6)
        shot("SeasonalDepth-Root-Spider")
        XCUIDevice.shared.press(.home);on.activate()
        XCTAssertTrue(bell.waitForExistence(timeout:10));XCTAssertEqual(bell.frame.minY,baseline,accuracy:1)
        on.terminate()
    }
    func testTwoSpidersStayVisibleAfterFormerDisappearance() throws {
        let app=launch(scope:"home")
        let bell=app.buttons["seasonal.fixture.bell"]
        XCTAssertTrue(bell.waitForExistence(timeout:15))
        Thread.sleep(forTimeInterval:18)
        XCTAssertTrue(bell.isHittable)
        shot("SeasonalPair-AfterFormer16SecondCutoff")
        Thread.sleep(forTimeInterval:17)
        XCTAssertTrue(bell.isHittable)
        shot("SeasonalPair-DuringBatGroup")
        app.terminate()
    }
    func testLightAndDarkActualArtworkAndEditor() throws {
        for appearance in ["light","dark"] {
            let app=launch(scope:"home",appearance:appearance)
            XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout:15));shot("SeasonalHome-\(appearance)")
            app.terminate()
            let editor=launch(scope:"editor",appearance:appearance)
            XCTAssertTrue(editor.buttons["seasonal.editor.apply"].waitForExistence(timeout:15));shot("SeasonalEditor-\(appearance)")
            XCTAssertTrue(editor.buttons["seasonal.editor.apply"].isEnabled)
            editor.terminate()
        }
    }
    func testCustomPNGFramesAreActuallyRendered() throws {
        let app=launch(scope:"custom")
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout:15))
        let screenshot=app.screenshot()
        let image=try XCTUnwrap(screenshot.image.cgImage)
        let width=image.width,height=image.height
        var pixels=[UInt8](repeating:0,count:width*height*4)
        pixels.withUnsafeMutableBytes { buffer in
            let context=CGContext(data:buffer.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,
                space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
        }
        var customPixels=0
        for y in 0..<height {
            for x in 0..<width {
                let offset=(y*width+x)*4
                if pixels[offset]>200 && pixels[offset+1]<90 && pixels[offset+2]>200 { customPixels += 1 }
            }
        }
        XCTAssertGreaterThan(customPixels,20,"The custom PNG must appear, not just the built-in ornaments")
        let attachment=XCTAttachment(screenshot:screenshot);attachment.name="Seasonal-Custom-PNG-Frames";attachment.lifetime = .keepAlways;add(attachment)
        app.terminate()
    }
    func testMaximumGermanEditorAndLocalKeyboard() throws {
        let app=launch(scope:"editor",language:"de",maximum:true)
        let name=app.textFields["seasonal.editor.name"]
        XCTAssertTrue(app.buttons["seasonal.editor.apply"].waitForExistence(timeout:15))
        for _ in 0..<8 where !name.exists || !name.isHittable { app.swipeUp() }
        XCTAssertTrue(name.exists && name.isHittable)
        name.tap(); name.typeText(" TEST")
        XCTAssertTrue((name.value as? String)?.contains("TEST") == true)
        shot("SeasonalEditor-DE-Maximum-Keyboard")
        let keyboardDone=app.buttons["Fertig"].firstMatch
        if keyboardDone.exists && keyboardDone.isHittable { keyboardDone.tap() }
        let date=app.buttons["seasonal.editor.date.start"]
        for _ in 0..<12 {
            if date.exists && date.isHittable { break }
            app.coordinate(withNormalizedOffset:CGVector(dx:0.96,dy:0.75))
                .press(forDuration:0.05,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.96,dy:0.3)))
        }
        XCTAssertTrue(date.exists && date.isHittable)
        let originalDate=date.label
        date.tap()
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout:10))
        shot("SeasonalEditor-DE-Maximum-DateSheet")
        let done=app.buttons["Fertig"].firstMatch
        XCTAssertTrue(done.isHittable);done.tap()
        XCTAssertTrue(date.waitForExistence(timeout:5));XCTAssertEqual(date.label,originalDate)
        app.terminate()
    }
    func testEnabledThemePublishesOnlyAfterExplicitConfirmation() throws {
        let app=launch(scope:"management")
        let add=app.buttons["Додати Хелловін"]
        XCTAssertTrue(add.waitForExistence(timeout:15));add.tap()
        let toggle=app.switches["Додати до розкладу"]
        for _ in 0..<8 where !toggle.exists || !toggle.isHittable { app.swipeUp() }
        XCTAssertTrue(toggle.exists && toggle.isHittable)
        shot("SeasonalEditor-BeforeEnable")
        toggle.coordinate(withNormalizedOffset:CGVector(dx:0.92,dy:0.5)).tap()
        XCTAssertEqual(toggle.value as? String,"1")
        app.buttons["seasonal.editor.apply"].tap()
        let save=app.buttons["seasonal.saveLibrary"]
        for _ in 0..<8 where !save.isHittable { app.swipeUp() }
        XCTAssertTrue(save.isEnabled);save.tap()
        let publish=app.buttons["seasonal.publish"]
        for _ in 0..<8 where !publish.isHittable { app.swipeUp() }
        XCTAssertTrue(publish.isEnabled);publish.tap()
        // The sheet's action uses the same explicit label as the originating button.
        let confirm=app.sheets.buttons["Опублікувати розклад"]
        XCTAssertTrue(confirm.waitForExistence(timeout:5));confirm.tap()
        let published=app.staticTexts["Розклад опубліковано."]
        XCTAssertTrue(published.waitForExistence(timeout:10))
        shot("SeasonalLibrary-Published-Explicitly")
        app.terminate()
    }
    func testLibrarySaveAndPublishAreSeparate() throws {
        let app=launch(scope:"management")
        XCTAssertTrue(app.otherElements["seasonal.management"].waitForExistence(timeout:15))
        let add=app.buttons["Додати Хелловін"]
        for _ in 0..<8 where !add.isHittable { app.swipeUp() }
        XCTAssertTrue(add.waitForExistence(timeout:10));add.tap()
        let apply=app.buttons["seasonal.editor.apply"]
        XCTAssertTrue(apply.waitForExistence(timeout:10));apply.tap()
        let save=app.buttons["seasonal.saveLibrary"]
        for _ in 0..<8 where !save.isHittable { app.swipeUp() }
        XCTAssertTrue(save.isEnabled);save.tap()
        let status=app.staticTexts["seasonal.status"]
        XCTAssertTrue(status.waitForExistence(timeout:10));shot("SeasonalLibrary-Saved-NotPublished")
        let publish=app.buttons["seasonal.publish"]
        for _ in 0..<6 where !publish.isHittable { app.swipeUp() }
        // The newly added Halloween theme is disabled, so no public presentation changed.
        XCTAssertFalse(publish.isEnabled)
        app.terminate()
    }
}
