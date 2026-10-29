import FirebaseFirestore
import Testing
import UIKit
@testable import UkrainianCommunity

@MainActor struct SeasonalDeviceRegressionTests {
    @Test func glassControlCopiesResolveToOneFloatingCapsule() throws {
        // Actual native landscape geometry: selected and ordinary content each
        // contain the same five controls; the full UITabBar is much wider.
        let bar=CGRect(x:-62,y:338,width:874,height:64)
        let frames=[CGRect(x:125.333333,y:342,width:93.666667,height:36),CGRect(x:223,y:342,width:76.666667,height:36),CGRect(x:303.666667,y:342,width:113,height:36),CGRect(x:420.666667,y:342,width:105.333333,height:36),CGRect(x:530,y:342,width:94.666667,height:36)]
        let result=try #require(SeasonalDecorationGeometry.navigationCapsule(bar:bar,itemFrames:frames+frames,expectedCount:5))
        #expect(abs(result.minX-121.333333)<0.01 && abs(result.width-507.333334)<0.01)
        #expect(result.minY==338 && result.height==44)
        #expect(SeasonalDecorationGeometry.navigationCapsule(bar:bar,itemFrames:Array(frames.dropLast()),expectedCount:5)==nil)
    }
    @Test func rotationKeepsEverySceneSelectedAndPreservesUserOptOut() {
        let date=Date(timeIntervalSince1970:1_800_000_000)
        for var theme in presets() {
            theme.isEnabled=true;theme.repeatsYearly=false
            theme.startsAt=date.addingTimeInterval(-60);theme.endsAt=date.addingTimeInterval(60)
            let library=SeasonalLibrary(themes:[theme])
            for compact in [false,true] {
                let active=SeasonalSelectionInput(library:library,preview:nil,section:.news,enabled:true,eligible:true,compact:compact,accessible:false)
                #expect(active.theme(at:date)?.id==theme.id)
                let off=SeasonalSelectionInput(library:library,preview:nil,section:.news,enabled:false,eligible:true,compact:compact,accessible:false)
                #expect(off.theme(at:date)==nil)
                let preview=SeasonalSelectionInput(library:library,preview:theme,section:.news,enabled:false,eligible:true,compact:compact,accessible:false)
                #expect(preview.theme(at:date)?.id==theme.id)
                let accessible=SeasonalSelectionInput(library:library,preview:theme,section:.news,enabled:true,eligible:true,compact:compact,accessible:true)
                #expect(accessible.theme(at:date)==nil)
            }
        }
    }
    @Test func uprightLandscapeMotionHasNoFalseHorizontalGravity() {
        for (orientation,gravity) in [(UIInterfaceOrientation.portrait,(0.0,-1.0)),(.landscapeLeft,(1.0,0.0)),(.landscapeRight,(-1.0,0.0)),(.portraitUpsideDown,(0.0,1.0))] {
            let value=SeasonalMotion.screenVector(x:gravity.0,y:gravity.1,orientation:orientation)
            #expect(value.x==0 && value.y == -1)
        }
        let left=SeasonalMotion.screenVector(x:0.8,y:0.2,orientation:.landscapeLeft)
        let right=SeasonalMotion.screenVector(x:-0.8,y:-0.2,orientation:.landscapeRight)
        #expect(left.x==right.x && left.y==right.y)
    }
    private func presets()->[SeasonalTheme] {
        zip(SeasonalPresetKind.allCases,[SeasonalTheme.halloweenScene(),.gtaVI(),.christmas(),.newYear()]).map { kind,item in
            var item=item;item.id=kind.controlID;item.name=kind.title;return item
        }
    }
    @Test func oldLocalizedAndEnglishCopiesProduceFourQuickCardsAndKeepLiveIdentity() {
        let defaults=presets()
        let old=[SeasonalTheme.halloweenScene(),.gtaVI(),.christmas(),.newYear()]
        var localized=defaults
        for i in localized.indices { localized[i].id="old-localized-\(i)" }
        var active=old[2];active.isEnabled=true
        let source=old+localized
        let result=SeasonalPresetKind.quickScenes(defaults:defaults,saved:source,published:SeasonalLibrary(themes:[active],manualThemeID:active.id))
        #expect(result.count==4 && result[2].id==active.id)
        #expect(Set(result.map(\.quickControlID)).count==4)
        #expect(source.count==8 && old[2].name=="Christmas · Warm Evergreen")
    }
    @Test func customNamesAndCanonicalRenamesArePreservedWithoutDuplicateIdentity() {
        let defaults=presets();var custom=SeasonalTheme.christmas();custom.name="Моя зимова сцена"
        var renamed=defaults[2];renamed.name="New Year"
        let options=SeasonalPresetKind.quickScenes(defaults:defaults,saved:[custom,renamed],published:SeasonalLibrary())
        #expect(options.count==5 && Set(options.map(\.id)).count==5)
        #expect(options[2].id==renamed.id && renamed.localizedSceneName=="New Year")
        #expect(options.last?.name==custom.name)
    }
    @Test func scheduleResolutionRemainsStableUntilActualBoundaryAndHonorsOptOut() {
        let start=Date(timeIntervalSince1970:1_800_000_000)
        var theme=SeasonalTheme.christmas(now:start);theme.isEnabled=true;theme.repeatsYearly=false;theme.startsAt=start;theme.endsAt=start.addingTimeInterval(10)
        let input=SeasonalSelectionInput(library:SeasonalLibrary(themes:[theme]),preview:nil,section:.news,enabled:true,eligible:true,compact:false,accessible:false)
        #expect(input.theme(at:start.addingTimeInterval(1))==input.theme(at:start.addingTimeInterval(9)))
        #expect(input.theme(at:start.addingTimeInterval(11))==nil)
        let off=SeasonalSelectionInput(library:input.library,preview:nil,section:.news,enabled:false,eligible:true,compact:false,accessible:false)
        #expect(off.theme(at:start)==nil)
    }
    @Test func aiDisclosureUsesOneLanguageAndPreservesRealCredits() {
        let dual="Тематична ШІ-ілюстрація / KI-generierte Themenillustration"
        #expect(ContentPublishingStrings.mediaCaption(caption:dual,credit:nil,language:.ukrainian)=="Тематична ШІ-ілюстрація")
        #expect(ContentPublishingStrings.mediaCaption(caption:nil,credit:dual,language:.german)=="KI-generierte Themenillustration")
        #expect(ContentPublishingStrings.mediaCaption(caption:dual,credit:dual,language:.ukrainian)=="Тематична ШІ-ілюстрація")
        #expect(ContentPublishingStrings.mediaCaption(caption:dual,credit:"© Fotograf / Agentur",language:.ukrainian)=="Тематична ШІ-ілюстрація · © Fotograf / Agentur")
    }
    @Test func snowBankFollowsCapsuleShouldersWithoutClippingMask() throws {
        let view=SeasonalAmbientView(frame:CGRect(x:0,y:0,width:430,height:932))
        view.configure(elements:SeasonalTheme.christmas().elements,animated:false,intensity:0.6,preview:true);view.layoutIfNeeded()
        let rim=try #require(view.subviews.compactMap{$0 as? SeasonalSnowRim}.first);rim.layoutIfNeeded()
        #expect(rim.bounds.height>12 && rim.image != nil && !rim.isHidden)
        #expect(rim.layer.mask==nil)
        #expect(SeasonalSnowRim.contour(x:0,width:398,radius:31)==49)
        #expect(SeasonalSnowRim.contour(x:199,width:398,radius:31)==18)
        #expect(SeasonalSnowRim.contour(x:398,width:398,radius:31)==49)
        let first=rim.image
        for _ in 0..<5 { view.setNeedsLayout();view.layoutIfNeeded();rim.layoutIfNeeded() }
        #expect(rim.image === first)
    }
    @Test func smallPhotographicHangersUseBoundedViewportAndBatsKeepFullFlightArea() {
        let frame=CGRect(x:0,y:0,width:430,height:932)
        let view=SeasonalSceneView(frame:frame)
        var theme=SeasonalTheme.christmas();theme.elements=theme.elements.filter{$0.zone == .hanging}
        view.configure(theme:theme,placement:SeasonalScenePlacement(),animated:false,dark:false,preview:false);view.layoutIfNeeded()
        #expect(view.renderingViewportSize.width==430 && view.renderingViewportSize.height<=300)
        view.configure(theme:SeasonalTheme.halloweenScene(),placement:SeasonalScenePlacement(),animated:false,dark:false,preview:false);view.layoutIfNeeded()
        #expect(view.renderingViewportSize==frame.size)
        view.stop()
    }
    @Test func legacyChristmasGetsTreeAndSantaWithoutMutatingStoredRecordAndExplicitOffSurvives() throws {
        var old=SeasonalTheme.christmas();old.sceneEdition=nil;old.celebration=nil
        old.elements[0].artwork = .christmasGlobe
        let prepared=old.preparedForCurrentRenderer
        var uncomposed=old;uncomposed.elements=Array(old.elements.prefix(2))
        for i in uncomposed.elements.indices { uncomposed.elements[i].zone=nil }
        #expect(uncomposed.preparedForCurrentRenderer==uncomposed.preparedForCurrentRenderer,"Derived upgrades must keep stable element IDs across clock ticks")
        #expect(old.elements[0].artwork == .christmasGlobe)
        #expect(prepared.id==old.id && prepared.startsAt==old.startsAt && prepared.sections==old.sections)
        #expect(prepared.elements[0].artwork == .christmasTree && prepared.elements[0].effectiveMotion == .twinkle)
        #expect(prepared.celebration == .santaFlight && prepared.sceneEdition==2)
        var off=prepared;off.celebration=nil
        #expect(off.preparedForCurrentRenderer.celebration==nil)
        let roundtrip=try SeasonalLibrary.decode(SeasonalLibrary(themes:[off]).encoded())
        #expect(roundtrip.themes.first==off)
    }
    @Test func transientFirstReadRecoversAndPermissionFailureDoesNotRetry() async throws {
        var attempts=0
        let value:Int=try await SeasonalRepository.retryTransientRead {
            attempts += 1
            if attempts==1 { throw NSError(domain:FirestoreErrorDomain,code:FirestoreErrorCode.Code.unavailable.rawValue) }
            return 42
        }
        #expect(value==42 && attempts==2)
        attempts=0
        do {
            let _:Int=try await SeasonalRepository.retryTransientRead {
                attempts += 1
                throw NSError(domain:FirestoreErrorDomain,code:FirestoreErrorCode.Code.permissionDenied.rawValue)
            }
            Issue.record("Permission failure was swallowed")
        } catch { #expect(attempts==1) }
    }
    @Test func festivitiesHaveBoundedLayersAndRespectMotionStop() {
        let view=SeasonalFestivitiesView(frame:CGRect(x:0,y:0,width:430,height:932))
        view.configure(.fireworks,animated:true,intensity:1,preview:true);view.layoutIfNeeded()
        #expect(view.effectLayers.count==54)
        view.configure(.santaFlight,animated:true,intensity:1,preview:true);view.layoutIfNeeded()
        #expect(view.effectLayers.count==1 && view.effectLayers.first?.contents != nil)
        view.configure(.santaFlight,animated:false,intensity:1,preview:true);view.layoutIfNeeded()
        #expect(view.effectLayers.isEmpty)
    }

    @Test func photographicHangersUseOnlySmallNativeLayersAndKeepTheirIdentity() throws {
        let view=SeasonalPhotoHangersView(frame:CGRect(x:0,y:0,width:430,height:932))
        let element=try #require(SeasonalTheme.christmas().elements.first{$0.artwork == .glassBauble})
        view.configure(element,animated:false,reactsToTilt:true,intensity:0.6,preview:true);view.layoutIfNeeded()
        #expect(view.partCount==2 && view.subviews.isEmpty)
        let images=(view.layer.sublayers ?? []).filter{$0.contents != nil}
        #expect(images.count==2 && images.allSatisfy{$0.bounds.height<80})
        view.configure(element,animated:false,reactsToTilt:true,intensity:0.6,preview:true);view.layoutIfNeeded()
        #expect((view.layer.sublayers ?? []).filter{$0.contents != nil}.first === images.first)
        view.stop()
    }
    @Test func santaHasAnActualGaitAndFireworkPixelsHaveMultipleSaturatedColors() throws {
        let view=SeasonalFestivitiesView(frame:CGRect(x:0,y:0,width:430,height:932))
        view.configure(.santaFlight,animated:true,intensity:0.6,preview:true);view.layoutIfNeeded()
        let gait=try #require(view.effectLayers.first?.animation(forKey:"seasonal.santa.gallop") as? CAKeyframeAnimation)
        #expect((gait.values?.count ?? 0)>4 && gait.calculationMode == .discrete)
        #expect(SeasonalSnowCrystals.fireworkTextures.count==6)
        var colors:Set<String>=[]
        for optional in SeasonalSnowCrystals.fireworkTextures {
            let image=try #require(optional)
            var pixel=[UInt8](repeating:0,count:4)
            pixel.withUnsafeMutableBytes { buffer in
                let c=CGContext(data:buffer.baseAddress,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
                c.draw(image,in:CGRect(x:-image.width/2,y:-image.height/2,width:image.width,height:image.height))
            }
            #expect(Int(pixel.max() ?? 0)-Int(pixel.prefix(3).min() ?? 0)>35,"A white texture must not cover the spark colour")
            colors.insert(pixel.prefix(3).map(String.init).joined(separator:","))
        }
        #expect(colors.count==6)
        view.stop()
    }

    @Test func ornamentWorkBudgetsDoNotConstrainTheSystemDisplayClock() throws {
        let element=try #require(SeasonalTheme.christmas().elements.first{$0.artwork == .glassBauble})
        let photo=SeasonalPhotoHangersView(frame:CGRect(x:0,y:0,width:430,height:932))
        photo.configure(element,animated:true,reactsToTilt:false,intensity:0.6,preview:true)
        #expect(photo.displayClockRange==CAFrameRateRange.default)
        photo.stop()
        let native=SeasonalSceneView(frame:CGRect(x:0,y:0,width:430,height:932))
        native.configure(theme:.halloweenScene(),placement:SeasonalScenePlacement(),animated:true,dark:false,preview:true)
        #expect(native.displayClockRange==CAFrameRateRange.default)
        native.stop()
    }

}
