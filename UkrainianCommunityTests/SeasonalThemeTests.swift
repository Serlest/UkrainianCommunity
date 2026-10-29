import Foundation
import Testing
import UIKit
import FirebaseFirestore
@testable import UkrainianCommunity

@MainActor struct SeasonalThemeTests {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    @Test func legacyStaticWebKeepsSpidersAndExplicitStopSurvivesRoundTrip() throws {
        var theme = SeasonalTheme.halloween()
        let web = try #require(theme.elements.firstIndex { $0.artwork == .web })
        theme.elements[web].sway = 0
        let legacy = try SeasonalLibrary.decode(SeasonalLibrary(themes: [theme]).encoded())
        #expect(legacy.themes[0].elements[web].spiderMotion == nil)
        #expect(legacy.themes[0].elements[web].motionStrength == 0.25)
        theme.elements[web].spiderMotion = 0
        let stopped = try SeasonalLibrary.decode(SeasonalLibrary(themes: [theme]).encoded())
        #expect(stopped.themes[0].elements[web].motionStrength == 0)
        theme.elements[web].spiderMotion = 0.7
        #expect(try SeasonalLibrary.decode(SeasonalLibrary(themes: [theme]).encoded()) == SeasonalLibrary(themes: [theme]))
        theme.elements[web].spiderMotion = .nan
        #expect(throws: (any Error).self) { try theme.validate() }
        theme.elements[web].spiderMotion = -0.1
        #expect(throws: (any Error).self) { try theme.validate() }
        theme.elements[web].spiderMotion = nil
        theme.elements[0].spiderMotion = 0.2
        #expect(throws: (any Error).self) { try theme.validate() }
    }

    @Test func exactBoundariesAndSectionFiltering() throws {
        var theme = SeasonalTheme.halloween(now: date("2026-10-28T12:00:00Z"))
        theme.isEnabled = true; theme.sections = [.news]
        let library = SeasonalLibrary(themes: [theme])
        #expect(library.active(at: theme.startsAt.addingTimeInterval(-1), section: .news) == nil)
        #expect(library.active(at: theme.startsAt, section: .news)?.id == theme.id)
        #expect(library.active(at: theme.endsAt, section: .news) == nil)
        #expect(library.active(at: theme.startsAt, section: .profile) == nil)
        let decoded = try SeasonalLibrary.decode(library.encoded())
        let matches = decoded == library
        #expect(matches)
    }

    @Test func annualChristmasCrossesNewYearAndKeepsViennaLocalTime() throws {
        var theme = SeasonalTheme.halloween()
        theme.startsAt = date("2026-12-20T17:00:00Z"); theme.endsAt = date("2027-01-07T17:00:00Z")
        theme.repeatsYearly = true
        try theme.validate()
        #expect(theme.contains(date("2028-01-01T12:00:00Z")))
        #expect(theme.contains(date("2027-12-20T17:00:00Z")))
        #expect(!theme.contains(date("2027-12-20T16:59:59Z")))
        #expect(!theme.contains(date("2028-01-07T17:00:00Z")))
        #expect(!theme.contains(date("2025-12-25T12:00:00Z")))
    }

    @Test func annualWindowTracksDSTAndHonorsEndWithoutInternet() throws {
        var theme = SeasonalTheme.halloween()
        // Local 10:00 is winter time on Oct 28 2026 and summer time on Oct 28 2027.
        theme.startsAt = date("2026-10-28T09:00:00Z"); theme.endsAt = date("2026-11-02T09:00:00Z")
        theme.repeatsYearly = true
        try theme.validate()
        #expect(!theme.contains(date("2027-10-28T07:59:59Z")))
        #expect(theme.contains(date("2027-10-28T08:00:00Z")))
        #expect(!theme.contains(date("2027-11-02T09:00:00Z")))
    }

    @Test func overlappingThemesHaveDeterministicPriorityAndDisabledNeverWins() {
        var low = SeasonalTheme.halloween(); low.isEnabled = true; low.priority = 1
        var high = low; high.id = "high"; high.priority = 10
        let now = low.startsAt
        #expect(SeasonalLibrary(themes:[low,high]).active(at:now,section:.news)?.id == "high")
        high.isEnabled = false
        #expect(SeasonalLibrary(themes:[high,low]).active(at:now,section:.news)?.id == low.id)
        var equal = low; equal.id = "000-first"
        #expect(SeasonalLibrary(themes:[low,equal]).active(at:now,section:.news)?.id == "000-first")
    }

    @Test func unsafeOrUnsupportedPackagesFailClosed() throws {
        var library = SeasonalLibrary(themes:[.halloween()])
        library.schemaVersion = 4
        #expect(throws:(any Error).self) { try library.encoded() }
        library.schemaVersion = 1
        library.themes[0].elements[0].size = .infinity
        #expect(throws:(any Error).self) { try library.validated() }
        library.themes[0] = .halloween()
        library.themes[0].elements[0].artwork = .image
        library.themes[0].elements[0].pngFrames = [Data("not a PNG".utf8).base64EncodedString()]
        #expect(throws:(any Error).self) { try library.validated() }
        #expect(throws:(any Error).self) { try SeasonalLibrary.decode(Data(repeating:32,count:240001)) }
    }

    @Test func customTransparentPNGArtworkSurvivesPackageRoundTrip() throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 24, height: 24)).image { context in
            UIColor.systemOrange.setFill(); context.cgContext.fillEllipse(in: CGRect(x: 2, y: 2, width: 20, height: 20))
        }
        let frame = try #require(image.pngData()).base64EncodedString()
        var theme = SeasonalTheme.halloween()
        theme.elements = [SeasonalElement(artwork: .image, anchor: .leading, pngFrames: [frame, frame])]
        let package = SeasonalLibrary(themes: [theme])
        let data = try package.encoded()
        let decoded = try SeasonalLibrary.decode(data)
        #expect(decoded.themes[0].elements[0].pngFrames == [frame, frame])
        #expect(try decoded.encoded() == data)
    }

    @Test func oversizedUnicodeNamesAndIdentifiersCannotBypassGraphemeLimits() {
        var theme = SeasonalTheme.halloween()
        theme.name = "A" + String(repeating: "\u{0301}", count: 400)
        #expect(theme.name.count == 1)
        #expect(throws:(any Error).self) { try theme.validate() }
        theme = .halloween(); theme.elements[0].id = "A" + String(repeating: "\u{0301}", count: 100)
        #expect(throws:(any Error).self) { try theme.validate() }
    }

    @Test func invalidSchedulesAndDuplicateIdentitiesAreRejected() {
        var theme = SeasonalTheme.halloween(); theme.endsAt = theme.startsAt
        #expect(throws:(any Error).self) { try theme.validate() }
        theme = .halloween(); theme.sections = []
        #expect(throws:(any Error).self) { try theme.validate() }
        theme = .halloween(); theme.timeZoneID = "not-a-zone"
        #expect(throws:(any Error).self) { try theme.validate() }
        theme = .halloween()
        #expect(throws:(any Error).self) { try SeasonalLibrary(themes:[theme,theme]).validated() }
    }
}

@MainActor struct SeasonalManagementTests {
    @Test func draftSavingPublishingAndEmergencyDisableRemainSeparate() async throws {
        let repository = SeasonalMemoryTestRepository()
        let model = SeasonalManagementModel(repository: repository)
        let owner = MockContentBuilder.ownerUser()
        await model.load(user: owner)
        var theme = SeasonalTheme.halloween(); theme.isEnabled = true
        model.library.themes = [theme]
        await model.save(user: owner)
        #expect(!model.hasChanges)
        #expect(model.published.themes.isEmpty)
        #expect(model.hasPublicationChanges)
        await model.save(user: owner, publish: true)
        #expect(model.published.themes.count == 1)
        model.library.themes[0].name = "Unpublished edit"
        await model.save(user: owner, publish: true, disable: true)
        #expect(model.published.themes.isEmpty)
        #expect(model.library.themes[0].name == "Unpublished edit")
        #expect(model.savedLibrary.themes[0].name == "Halloween")
        #expect(model.hasChanges)
        model.reset()
        await model.load(user: owner)
        #expect(model.library.themes[0].name == "Halloween")
        #expect(model.published.themes.isEmpty)
    }

    @Test func staleOwnerSavePreservesDraftAndDoesNotOverwriteOtherDevice() async throws {
        let repository = SeasonalMemoryTestRepository()
        let first = SeasonalManagementModel(repository: repository), second = SeasonalManagementModel(repository: repository)
        let owner = MockContentBuilder.ownerUser()
        await first.load(user: owner); await second.load(user: owner)
        first.library.themes = [.halloween()]; await first.save(user: owner)
        var another = SeasonalTheme.halloween(); another.name = "Stale draft"
        second.library.themes = [another]; await second.save(user: owner)
        #expect(second.hasChanges)
        #expect(second.library.themes[0].name == "Stale draft")
        #expect(second.message == SeasonalText.conflict)
        let actual = try await repository.fetch(path: SeasonalRepository.libraryPath)
        #expect(actual.library.themes[0].name == "Halloween")
    }

    @Test func nonOwnerAndBlockedOwnerNeverFetchOrWrite() async throws {
        let repository = SeasonalMemoryTestRepository()
        let model = SeasonalManagementModel(repository: repository)
        await model.load(user: nil)
        #expect(!model.hasLoaded)
        #expect(repository.fetchCount == 0)
        #expect(!ProfileAccessPolicy(user: nil).allows(.seasonalManagement))
        #expect(ProfileAccessPolicy(user: MockContentBuilder.ownerUser()).allows(.seasonalManagement))
    }

    @Test func deniedAuthorityIsNotMisreportedAsAnInternetFailure() {
        let denied = NSError(domain: FirestoreErrorDomain, code: FirestoreErrorCode.Code.permissionDenied.rawValue)
        let unauthenticated = NSError(domain: FirestoreErrorDomain, code: FirestoreErrorCode.Code.unauthenticated.rawValue)
        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        #expect(SeasonalManagementModel.failureMessage(denied) == SeasonalText.ownerOnly)
        #expect(SeasonalManagementModel.failureMessage(unauthenticated) == SeasonalText.ownerOnly)
        #expect(SeasonalManagementModel.failureMessage(offline) == SeasonalText.unavailable)
    }

    @Test func cachedPackageCanResolveScheduleWithoutFirestore() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        var theme = SeasonalTheme.halloween(); theme.isEnabled = true
        try SeasonalLibrary(themes: [theme]).encoded().write(to: url)
        let store = SeasonalStore(cacheURL: url)
        #expect(store.library.active(at: theme.startsAt, section: .news)?.id == theme.id)
        #expect(store.library.active(at: theme.endsAt, section: .news) == nil)
    }
}

@MainActor private final class SeasonalMemoryTestRepository: SeasonalRepositoryProtocol {
    private var documents: [String: SeasonalDocument] = [:]
    private(set) var fetchCount = 0
    func fetch(path: String) async throws -> SeasonalDocument { fetchCount += 1; return documents[path] ?? SeasonalDocument() }
    func save(_ library: SeasonalLibrary, path: String, expectedRevision: String?, userID: String) async throws -> SeasonalDocument {
        guard documents[path]?.revision == expectedRevision else { throw SeasonalError.conflict }
        let result = SeasonalDocument(library: try library.validated(), revision: UUID().uuidString)
        documents[path] = result; return result
    }
}

@MainActor struct SeasonalPreparedScenesTests {
    @Test func draftsAreReusableBoundedAndNeverEnableThemselves() throws {
        let themes=[SeasonalTheme.halloweenScene(),.gtaVI(),.christmas(),.newYear()]
        let library=SeasonalLibrary(themes:themes)
        #expect(try SeasonalLibrary.decode(library.encoded()) == library)
        for theme in themes {
            #expect(!theme.isEnabled)
            #expect(theme.sections == SeasonalSection.allCases)
            #expect(theme.elements.count==6)
            #expect(theme.isComposedScene)
            #expect(Set(theme.elements.compactMap(\.zone)) == Set(SeasonalSceneZone.allCases))
            #expect(library.active(at:theme.startsAt,section:.news)==nil)
        }
        #expect(!themes[1].repeatsYearly)
        #expect(themes[2].repeatsYearly && themes[3].repeatsYearly)
        let allHaveHeader=themes.allSatisfy(\.usesHeaderDock)
        #expect(allHaveHeader)
    }
    @Test func annualNewYearKeepsOneWindowAcrossJanuary() throws {
        let now=ISO8601DateFormatter().date(from:"2026-12-31T12:00:00Z")!
        let scene=SeasonalTheme.newYear(now:now)
        #expect(scene.contains(ISO8601DateFormatter().date(from:"2027-01-03T12:00:00Z")!))
        #expect(scene.contains(ISO8601DateFormatter().date(from:"2028-01-03T12:00:00Z")!))
        #expect(!scene.contains(ISO8601DateFormatter().date(from:"2027-07-01T12:00:00Z")!))
        let christmas=SeasonalTheme.christmas(now:now)
        #expect(christmas.contains(ISO8601DateFormatter().date(from:"2027-12-25T12:00:00Z")!))
    }
}

@MainActor struct SeasonalCompositionTests {
    @Test func zoneAndEffectContractsRejectAmbiguousPackages() throws {
        var theme=SeasonalTheme.christmas()
        theme.elements[1].zone = .brand
        #expect(throws:(any Error).self) { try theme.validate() }
        theme = .christmas();theme.elements[0].zone=nil
        #expect(throws:(any Error).self) { try theme.validate() }
        theme = .christmas();theme.elements[0].accentHex="GG11FF"
        #expect(throws:(any Error).self) { try theme.validate() }
        theme = .christmas();theme.elements[1].motionStyle = .snow
        #expect(throws:(any Error).self) { try theme.validate() }
        theme = .christmas();theme.elements[0].zone = .edges;theme.elements[0].artwork = .pine
        #expect(throws:(any Error).self) { try theme.validate() }
    }
    @Test func composedPayloadRequiresRendererTwoAndEnvelopeOneStaysSeparate() throws {
        var library=SeasonalLibrary()
        #expect(library.schemaVersion==1)
        library.themes.append(.christmas())
        #expect(library.schemaVersion==2)
        let encoded=try library.encoded()
        var json=try #require(JSONSerialization.jsonObject(with:encoded) as? [String:Any])
        #expect(json["schemaVersion"] as? Int==2)
        json["schemaVersion"]=1
        let disguised=try JSONSerialization.data(withJSONObject:json)
        #expect(throws:(any Error).self) { try SeasonalLibrary.decode(disguised) }
        let legacy=SeasonalLibrary(themes:[.halloween()])
        #expect(legacy.schemaVersion==1)
        let same=try SeasonalLibrary.decode(legacy.encoded())==legacy;#expect(same)
    }
    @Test func disabledHeaderAndDetailAtmospherePersistWithoutChrome() throws {
        var theme=SeasonalTheme.newYear();theme.elements[0].isEnabled=false
        #expect(!theme.usesHeaderDock)
        let detail=theme.presentation(includesChrome:false)
        #expect(detail.elements.count==2)
        #expect(theme.presentation(includesChrome:false,showsNavigation:false).elements.count==1)
        #expect(!detail.usesHeaderDock)
        #expect(detail.elements.contains{$0.artwork == .snowflake})
        #expect(detail.elements.contains{$0.artwork == .snowLedge})
        let package=SeasonalLibrary(themes:[theme])
        let roundTrip=try SeasonalLibrary.decode(package.encoded())
        let match=roundTrip==package;#expect(match)
    }
    @Test func upgradingLegacyNativeAndCustomThemesKeepsTheirData() throws {
        var old=SeasonalTheme.halloween();old.elements[1].sway=0;old.reactsToTilt=false
        let arranged=old.arrangedInZones()
        #expect(arranged.id==old.id && arranged.startsAt==old.startsAt && arranged.endsAt==old.endsAt)
        #expect(!arranged.reactsToTilt)
        #expect(arranged.elements.first{$0.artwork == .spider}?.spiderMotion==0.25)
        try arranged.validate()
        let png=try SeasonalPNGImporter.frame(UIGraphicsImageRenderer(size:CGSize(width:20,height:20)).image{ctx in
            UIColor.orange.setFill();ctx.cgContext.fillEllipse(in:CGRect(x:2,y:2,width:16,height:16))
        }.pngData()!)
        old.elements=[SeasonalElement(artwork:.image,anchor:.leading,pngFrames:[png,png])]
        let custom=old.arrangedInZones();try custom.validate()
        #expect(custom.elements.contains{$0.id==old.elements[0].id && $0.pngFrames==[png,png]})
        #expect(custom.visibleElements.count==1)
    }
    @Test func importedArtworkIsBoundedAndSurvivesExportWithTransparency() throws {
        let image=UIGraphicsImageRenderer(size:CGSize(width:900,height:600)).image { ctx in
            UIColor.systemPink.setFill();ctx.cgContext.fillEllipse(in:CGRect(x:70,y:70,width:600,height:400))
        }
        let encoded=try SeasonalPNGImporter.frame(image.pngData()!)
        let data=try #require(Data(base64Encoded:encoded)),decoded=try #require(UIImage(data:data))
        #expect(data.count<=48_000)
        #expect(max(decoded.size.width,decoded.size.height)<=256)
        #expect(try #require(decoded.cgImage).alphaInfo != CGImageAlphaInfo.none)
        var scene=SeasonalTheme.gtaVI();scene.elements[0].artwork = .image;scene.elements[0].pngFrames=[encoded]
        let library=SeasonalLibrary(themes:[scene]);let same=try SeasonalLibrary.decode(library.encoded())==library
        #expect(same)
        #expect(throws:(any Error).self) { try SeasonalPNGImporter.frame(Data("not PNG".utf8)) }
        #expect(throws:(any Error).self) { try SeasonalPNGImporter.frame(image.jpegData(compressionQuality:0.8)!) }
    }
}
