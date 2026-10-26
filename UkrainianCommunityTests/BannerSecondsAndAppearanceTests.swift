import SwiftUI
import Testing
@testable import UkrainianCommunity

@MainActor
struct BannerSecondsAndAppearanceTests {
    @Test func secondsDecomposeAcrossEveryBoundaryWithoutDroppingZeroFields() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let target = now.addingTimeInterval(86_400)
        let timer = FeaturedBannerCountdown(targetDate: target, label: "", germanLabel: "", completion: .showStarted)
        let first = try #require(timer.remaining(at: now))
        #expect(first.days == 1 && first.hours == 0 && first.minutes == 0 && first.seconds == 0)
        #expect(BannerCountdownStrings.remaining(first).components(separatedBy: " · ").count == 4)
        #expect(BannerCountdownStrings.remaining(first).contains("00 " + BannerCountdownStrings.text("hours")))
        let after = try #require(timer.remaining(at: now.addingTimeInterval(1)))
        #expect(after.days == 0 && after.hours == 23 && after.minutes == 59 && after.seconds == 59)
        let final = try #require(timer.remaining(at: target.addingTimeInterval(-0.1)))
        #expect(final.minutes == 0 && final.seconds == 1)
        #expect(timer.remaining(at: target) == nil)
        #expect(timer.remaining(at: target.addingTimeInterval(1)) == nil)
    }
    @Test func scheduleTicksPerSecondStopsAtTargetAndCanPause() {
        let start = Date(timeIntervalSince1970: 1_000)
        let target = start.addingTimeInterval(2.25)
        let dates = Array(FeaturedBannerCountdownSchedule(target: target).entries(from: start, mode: .normal))
        #expect(dates == [start, start.addingTimeInterval(0.25), start.addingTimeInterval(1.25), target])
        let paused = Array(FeaturedBannerCountdownSchedule(target: target, isPaused: true).entries(from: start, mode: .normal))
        #expect(paused == [start])
    }
    @Test func textColorsSaveReopenCopyAndResetIndependently() async throws {
        let repo = MockFeaturedBannerRepository(banners: [])
        let model = FeaturedBannerEditorViewModel(repository: repo)
        model.imageURL = "https://example.com/banner.jpg"; model.title = "Подія"
        #expect(model.textAppearance == .standard)
        model.textAppearance.titleColorHex = "#2458A6"
        model.textAppearance.subtitleColorHex = "#FFD43B"
        #expect(model.previewBanner.textAppearance == model.textAppearance)
        #expect(model.hasUnsavedChanges)
        #expect(await model.save(updatedBy: "owner"))
        let saved = try #require(try await repo.fetchAllBannersForOwner().first)
        let reopened = FeaturedBannerEditorViewModel(repository: repo, mode: .edit(saved))
        #expect(!reopened.hasUnsavedChanges)
        #expect(reopened.textAppearance == model.textAppearance)
        let duplicate = FeaturedBannerEditorViewModel(repository: repo, mode: .duplicate(saved))
        #expect(duplicate.textAppearance == saved.textAppearance && !duplicate.isActive)
        reopened.textAppearance.titleColorHex = nil
        #expect(reopened.textAppearance.subtitleColorHex == "#FFD43B")
        #expect(await reopened.save(updatedBy: "owner"))
        let reset = try #require(try await repo.fetchAllBannersForOwner().first)
        #expect(reset.textAppearance.titleColorHex == nil && reset.textAppearance.subtitleColorHex == "#FFD43B")
        try await repo.setBannerActive(id: reset.id, isActive: false, updatedBy: "owner")
        #expect(try await repo.fetchAllBannersForOwner().first?.textAppearance == reset.textAppearance)
    }
    @Test func colorValidationAndPayloadAreCanonicalOpaqueAndSeparate() throws {
        let appearance = FeaturedBannerTextAppearance(titleColorHex: "#abcdef", subtitleColorHex: "#000000")
        #expect(appearance.isValid)
        #expect(!FeaturedBannerTextAppearance(titleColorHex: "#FFFFFF00").isValid)
        #expect(!FeaturedBannerTextAppearance(subtitleColorHex: "red").isValid)
        let banner = FeaturedBanner(id: "appearance", title: "", imageURL: "https://example.com/banner.jpg", visibleSections: [.home], createdAt: .now, updatedAt: .now, createdBy: "owner", textAppearance: appearance)
        let payload = try FeaturedBannerMutationPayload(banner: banner)
        #expect(payload.presentationVersion == 2)
        #expect(payload.textAppearance.titleColorHex == "#ABCDEF")
        #expect(FeaturedBannerTextColor.hex(from: .black) == "#000000")
        #expect(FeaturedBannerTextColor.hex(from: FeaturedBannerTextColor.color(hex: "#2458A6", fallback: .white)) == "#2458A6")
    }
}
