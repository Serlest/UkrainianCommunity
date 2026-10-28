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
        library.schemaVersion = 2
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
        let themes=[SeasonalTheme.halloween(),.gtaVI(),.christmas(),.newYear()]
        let library=SeasonalLibrary(themes:themes)
        #expect(try SeasonalLibrary.decode(library.encoded()) == library)
        for theme in themes {
            #expect(!theme.isEnabled)
            #expect(theme.sections == SeasonalSection.allCases)
            #expect(theme.elements.count<=3)
            #expect(library.active(at:theme.startsAt,section:.news)==nil)
        }
        #expect(!themes[1].repeatsYearly)
        #expect(themes[2].repeatsYearly && themes[3].repeatsYearly)
        #expect(!themes[1].usesHeaderDock && !themes[2].usesHeaderDock && !themes[3].usesHeaderDock)
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
