import Testing
import UIKit
@testable import UkrainianCommunity

@MainActor struct SeasonalExperienceTests {
    @Test func quickSelectionIsImmediateExclusiveAndRetainsSavedCalendar() async throws {
        let model=SeasonalManagementModel(repository:SeasonalExperienceRepository())
        let owner=MockContentBuilder.ownerUser();await model.load(user:owner)
        let halloween=SeasonalTheme.halloweenScene(),christmas=SeasonalTheme.christmas()
        await model.activate(halloween,user:owner)
        #expect(model.published.manualThemeID==halloween.id)
        await model.activate(christmas,user:owner)
        #expect(model.published.themes.count==1)
        #expect(model.published.manualThemeID==christmas.id)
        #expect(model.savedLibrary.themes.count==2)
        #expect(model.savedLibrary.themes.first{$0.id==christmas.id}?.startsAt==christmas.startsAt)
        #expect(model.published.active(at:Date(timeIntervalSince1970:0),section:.news)?.id==christmas.id)
        #expect(try SeasonalLibrary.decode(model.published.encoded())==model.published)
        await model.save(user:owner,publish:true,disable:true)
        #expect(model.published.themes.isEmpty)
        #expect(model.savedLibrary.themes.count==2)
    }
    @Test func manualChoiceDoesNotDisableFutureScheduledThemes() async {
        let model=SeasonalManagementModel(repository:SeasonalExperienceRepository()),owner=MockContentBuilder.ownerUser()
        await model.load(user:owner)
        var future=SeasonalTheme.christmas();future.isEnabled=true
        model.library.themes=[future];await model.save(user:owner)
        await model.activate(.halloweenScene(),user:owner)
        #expect(model.savedLibrary.themes.first{$0.id==future.id}?.isEnabled==true)
        #expect(model.savedLibrary.manualThemeID==nil)
        #expect(model.published.themes.count==1)
        await model.save(user:owner,publish:true)
        #expect(model.published.manualThemeID==nil)
        #expect(model.published.themes.first?.id==future.id)
    }
    @Test func ambiguousSecondWriteDoesNotClaimSceneChanged() async {
        let repository=SeasonalExperienceRepository()
        let sut=SeasonalManagementModel(repository:repository),owner=MockContentBuilder.ownerUser()
        await sut.load(user:owner)
        let first=SeasonalTheme.halloweenScene();await sut.activate(first,user:owner)
        repository.rejectPublic=true
        await sut.activate(.christmas(),user:owner)
        #expect(sut.published.manualThemeID==first.id)
        #expect(sut.savedLibrary.themes.count==2)
        #expect(sut.message==SeasonalText.unavailable)
        repository.rejectPublic=false
        await sut.activate(sut.savedLibrary.themes[1],user:owner)
        #expect(sut.published.manualThemeID==sut.savedLibrary.themes[1].id)
    }
    @Test func editedSceneSavesAndEnablesInOneActionWithoutDestroyingCalendar() async throws {
        let repository = SeasonalExperienceRepository()
        let model = SeasonalManagementModel(repository: repository), owner = MockContentBuilder.ownerUser()
        await model.load(user: owner)
        let halloween = SeasonalTheme.halloweenScene()
        #expect(await model.activate(halloween, user: owner))
        var scheduled = SeasonalTheme.christmas(); scheduled.isEnabled = true
        model.library.themes.append(scheduled)
        var edited = model.library.themes[0]; edited.name += " edited"
        model.library.themes[0] = edited
        #expect(model.hasChanges)
        #expect(await model.saveAndActivate(edited, user: owner))
        #expect(!model.hasChanges && !model.publicStateUnconfirmed)
        #expect(model.published.themes.count == 1 && model.published.manualThemeID == edited.id)
        #expect(model.published.themes[0].name == edited.name)
        #expect(model.savedLibrary.themes.first { $0.id == scheduled.id }?.isEnabled == true)
    }
    @Test func failedPublicChangeIsUnknownUntilServerReadConfirmsState() async {
        let repository = SeasonalExperienceRepository()
        let model = SeasonalManagementModel(repository: repository), owner = MockContentBuilder.ownerUser()
        await model.load(user: owner)
        let original = SeasonalTheme.halloweenScene()
        #expect(await model.activate(original, user: owner))
        repository.rejectPublic = true
        #expect(!(await model.activate(.christmas(), user: owner)))
        #expect(model.publicStateUnconfirmed)
        #expect(model.published.manualThemeID == original.id) // Last verified snapshot only.
        await model.load(user: owner)
        #expect(!model.publicStateUnconfirmed && model.published.manualThemeID == original.id)
        repository.rejectPublic = false
        #expect(await model.activate(.christmas(), user: owner))
        #expect(!model.publicStateUnconfirmed)
    }
    @Test func failedPrivateSaveCannotClaimAlreadyActiveSceneWasUpdated() async {
        let repository = SeasonalExperienceRepository()
        let model = SeasonalManagementModel(repository: repository), owner = MockContentBuilder.ownerUser()
        await model.load(user: owner)
        #expect(await model.activate(.halloweenScene(), user: owner))
        let original = model.published
        var edited = model.library.themes[0]; edited.name += " unsaved"
        model.library.themes[0] = edited; repository.rejectLibrary = true
        #expect(!(await model.saveAndActivate(edited, user: owner)))
        #expect(model.hasChanges && model.published == original && !model.publicStateUnconfirmed)
    }
    @Test func loadingHasABoundedFailureAndCanBeRetried() async {
        let repository=SeasonalExperienceRepository()
        repository.suspendedReads=true
        let model=SeasonalManagementModel(repository:repository,readDeadline:{_ in try await Task.sleep(for:.milliseconds(100))})
        await model.load(user:MockContentBuilder.ownerUser())
        #expect(!model.isLoading)
        #expect(!model.hasLoaded && model.message==SeasonalText.unavailable)
        repository.suspendedReads=false
        await model.load(user:MockContentBuilder.ownerUser())
        #expect(model.hasLoaded && model.message==nil)
    }
    @Test func oneGlobalWinnerNeverFallsBackToAnotherSceneOnOtherTabs() {
        var first=SeasonalTheme.halloweenScene();first.isEnabled=true;first.sections=[.news];first.priority=10
        var second=first;second.id="second";second.priority=0;second.sections=[.events]
        let package=SeasonalLibrary(themes:[first,second])
        #expect(package.active(at:first.startsAt,section:.news)?.id==first.id)
        #expect(package.active(at:first.startsAt,section:.events)==nil)
    }
    @Test func manualFormatCannotBeDisguisedAsOldFormatOrSelectTwoScenes() throws {
        var theme=SeasonalTheme.christmas();theme.isEnabled=true
        var package=SeasonalLibrary(themes:[theme],manualThemeID:theme.id)
        #expect(package.schemaVersion==3)
        package.schemaVersion=2
        #expect(throws:(any Error).self) { try package.encoded() }
        package.schemaVersion=3;var other=SeasonalTheme.halloweenScene();other.isEnabled=true;package.themes.append(other)
        #expect(throws:(any Error).self) { try package.encoded() }
    }
    @Test func sharedAtmosphereKeepsParticlesWhileChromeAndNavigationChange() throws {
        let window=UIWindow(frame:CGRect(x:0,y:0,width:430,height:932))
        let view=SeasonalAmbientView(frame:window.bounds);window.addSubview(view)
        let theme=SeasonalTheme.christmas()
        view.configure(elements:theme.elements,animated:true,intensity:0.8,preview:true);view.layoutIfNeeded()
        let generation=view.snowGeneration
        let particles=(view.layer.sublayers ?? []).filter{$0.name=="seasonal.snow"}
        #expect(particles.count>=30 && particles.count<=48)
        for _ in 0..<20 {
            view.setVisibility(chrome:false,navigation:false);view.layoutIfNeeded()
            view.setVisibility(chrome:true,navigation:true);view.layoutIfNeeded()
        }
        #expect(view.snowGeneration==generation)
        let after=(view.layer.sublayers ?? []).filter{$0.name=="seasonal.snow"}
        #expect(after.first===particles.first)
        #expect(after.allSatisfy{$0.animation(forKey:"seasonal.fall") != nil})
        view.stop();view.removeFromSuperview()
    }
    @Test func choosingGarlandAnimationEnablesItsLightsAndStillRemainsStill() {
        var element=SeasonalElement.scene(.christmasTree,.brand,motion:.still,glow:false)
        #expect(!element.needsAnimation)
        element.selectMotion(.twinkle)
        #expect(element.glow && element.needsAnimation)
        element.selectMotion(.still)
        #expect(!element.needsAnimation)
        let rim=SeasonalElement.scene(.snowLedge,.navigation)
        #expect(rim.needsAnimation)
    }
    @Test func switchingAppearanceRecolorsExistingSnowWithoutRestartingItsFall() throws {
        let window=UIWindow(frame:CGRect(x:0,y:0,width:430,height:932))
        let view=SeasonalAmbientView(frame:window.bounds);window.addSubview(view)
        view.traitOverrides.userInterfaceStyle = .light;view.updateTraitsIfNeeded()
        view.configure(elements:SeasonalTheme.christmas().elements,animated:true,intensity:0.8,preview:true);view.layoutIfNeeded()
        let particle=try #require((view.layer.sublayers ?? []).first{$0.name=="seasonal.snow"})
        let light=try #require(particle.contents) as AnyObject
        let generation=view.snowGeneration
        view.traitOverrides.userInterfaceStyle = .dark;view.updateTraitsIfNeeded()
        let dark=try #require(particle.contents) as AnyObject
        let lightTexture=try #require(SeasonalAmbientView.lightSnowTexture)
        let darkTexture=try #require(SeasonalAmbientView.snowTexture)
        #expect(light === lightTexture)
        #expect(dark === darkTexture)
        #expect(light !== dark && view.snowGeneration==generation)
        #expect(particle.animation(forKey:"seasonal.fall") != nil)
        view.stop();view.removeFromSuperview()
    }
    @Test func treeGarlandHasNineLightsAndStopsEveryAnimation() {
        let view=SeasonalHeaderImageView(frame:CGRect(x:0,y:0,width:38,height:56))
        let element=SeasonalElement.scene(.christmasTree,.brand,size:44,motion:.twinkle,glow:true)
        view.configure(element,animated:true,intensity:0.7);view.layoutIfNeeded()
        let lights=(view.layer.sublayers ?? []).filter{$0.name=="seasonal.garland"}
        #expect(lights.count==9)
        #expect(lights.allSatisfy{$0.animation(forKey:"seasonal.garland") != nil})
        view.configure(element,animated:false,intensity:0.7)
        #expect((view.layer.sublayers ?? []).allSatisfy{($0.animationKeys() ?? []).isEmpty})
    }
    @Test func nestedPreviewWakeOwnershipRestoresOriginalOnlyAfterLastPreview() {
        let manager=SeasonalScreenAwakeLease.shared
        let original=UIApplication.shared.isIdleTimerDisabled
        let first=UUID(),second=UUID()
        defer { manager.release(first);manager.release(second) }
        manager.acquire(first);manager.acquire(second);manager.acquire(second)
        #expect(manager.count==2 && UIApplication.shared.isIdleTimerDisabled)
        manager.release(first)
        #expect(manager.count==1 && UIApplication.shared.isIdleTimerDisabled)
        manager.release(second)
        #expect(manager.count==0 && UIApplication.shared.isIdleTimerDisabled==original)
    }
    @Test func photographicSnowHasTransparentPaddingAndDistinctNaturalCrystals() throws {
        #expect(SeasonalSnowCrystals.light.count==6 && SeasonalSnowCrystals.dark.count==6)
        var payloads:Set<Data>=[]
        for texture in SeasonalSnowCrystals.light+SeasonalSnowCrystals.dark {
            let image=try #require(texture)
            var bytes=[UInt8](repeating:0,count:image.width*image.height*4)
            bytes.withUnsafeMutableBytes { buffer in
                let c=CGContext(data:buffer.baseAddress,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
                c.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
            }
            let opaque=stride(from:3,to:bytes.count,by:4).filter{bytes[$0]>100}.count
            #expect(opaque>30 && opaque<image.width*image.height/2,"Snow must remain a delicate ice crystal, without a rectangular backdrop")
            #expect(bytes[3]<5)
            payloads.insert(Data(bytes))
        }
        #expect(payloads.count>=6)
    }

}

@MainActor private final class SeasonalExperienceRepository:SeasonalRepositoryProtocol {
    var docs:[String:SeasonalDocument]=[:];var rejectPublic=false;var rejectLibrary=false;var suspendedReads=false
    func fetch(path:String) async throws -> SeasonalDocument { if suspendedReads { try await Task.sleep(for:.seconds(60)) };return docs[path] ?? SeasonalDocument() }
    func save(_ library:SeasonalLibrary,path:String,expectedRevision:String?,userID:String) async throws -> SeasonalDocument {
        if rejectPublic && path==SeasonalRepository.presentationPath { throw SeasonalError.unavailable }
        if rejectLibrary && path==SeasonalRepository.libraryPath { throw SeasonalError.unavailable }
        guard docs[path]?.revision==expectedRevision else { throw SeasonalError.conflict }
        let document=SeasonalDocument(library:try library.validated(),revision:UUID().uuidString);docs[path]=document;return document
    }
}
