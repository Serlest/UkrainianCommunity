import Foundation
import Testing
@testable import UkrainianCommunity

struct FeaturedBannerVideoPolicyTests {
    private let digest = String(repeating: "a", count: 64)
    private func descriptor(path: String? = nil, width: Int = 1280, height: Int = 720,
                            duration: Double = 15, bytes: Int = 4 * 1024 * 1024,
                            fps: Double = 30, hasAudio: Bool = false, audioCodec: String? = nil) -> FeaturedBannerVideoDescriptor {
        .init(schemaVersion: 1, assetPath: path ?? "featuredBannerVideos/banner-1/\(digest).mp4", sha256: digest,
              byteCount: bytes, width: width, height: height, durationSeconds: duration, framesPerSecond: fps,
              codec: "h264", hasAudio: hasAudio, audioCodec: audioCodec)
    }

    @Test func renditionBoundariesAndOptionalAudio() {
        #expect(descriptor().isValid(for: "banner-1"))
        #expect(descriptor(width: 640, height: 360, duration: 1, bytes: 1, fps: 1).isValid(for: "banner-1"))
        #expect(descriptor(hasAudio: true, audioCodec: "aac").isValid(for: "banner-1"))
        #expect(!descriptor(hasAudio: true).isValid(for: "banner-1"))
        #expect(!descriptor(audioCodec: "aac").isValid(for: "banner-1"))
    }

    @Test func refusesCrossBannerPathsAndUntrustedURLs() {
        for path in ["https://example.com/video.mp4", "featuredBannerVideos/banner-2/\(digest).mp4",
                     "featuredBannerVideos/banner-1/../\(digest).mp4", "featuredBannerVideos/banner-1/%2e%2e.mp4"] {
            #expect(!descriptor(path: path).isValid(for: "banner-1"))
        }
        for id in ["", "../banner-1", "banner/1", "banner%2f1"] { #expect(!descriptor().isValid(for: id)) }
    }

    @Test func rejectsOversizedAndNonfiniteRenditions() {
        for duration in [0, 15.001, Double.nan, .infinity] { #expect(!descriptor(duration: duration).isValid(for: "banner-1")) }
        for bytes in [0, 4 * 1024 * 1024 + 1] { #expect(!descriptor(bytes: bytes).isValid(for: "banner-1")) }
        for fps in [0, 30.001, Double.nan, .infinity] { #expect(!descriptor(fps: fps).isValid(for: "banner-1")) }
        #expect(!descriptor(width: 1920, height: 1080).isValid(for: "banner-1"))
        #expect(!descriptor(width: 720, height: 1280).isValid(for: "banner-1"))
        #expect(!descriptor(width: 1279).isValid(for: "banner-1"))
    }

    @Test func autoplayRequiresEveryEligibilityCondition() {
        let ready = FeaturedBannerVideoPlaybackContext(selected: true, visibleFraction: 0.6, sceneActive: true, renditionReady: true)
        #expect(ready.permitsInlinePlayback)
        var cases: [FeaturedBannerVideoPlaybackContext] = []
        var c = ready; c.selected = false; cases.append(c)
        c = ready; c.sceneActive = false; cases.append(c)
        c = ready; c.interactionInProgress = true; cases.append(c)
        c = ready; c.reduceMotion = true; cases.append(c)
        c = ready; c.lowPower = true; cases.append(c)
        c = ready; c.lowData = true; cases.append(c)
        c = ready; c.autoplayEnabled = false; cases.append(c)
        c = ready; c.renditionReady = false; cases.append(c)
        for fraction in [0.599, -1, 1.1, Double.nan, .infinity] { c = ready; c.visibleFraction = fraction; cases.append(c) }
        for context in cases { #expect(!context.permitsInlinePlayback) }
    }

    @Test func soundConsentDoesNotLeakBetweenBannersOrBackgrounding() {
        var sound = FeaturedBannerVideoSoundState()
        sound.toggleByUser(); #expect(sound.isMuted)
        sound.present("banner-1"); #expect(sound.isMuted)
        sound.toggleByUser(); #expect(!sound.isMuted)
        sound.present("banner-1"); #expect(!sound.isMuted)
        sound.present("banner-2"); #expect(sound.isMuted)
        sound.toggleByUser(); sound.suspend(); #expect(sound.isMuted)
        sound.present(nil); sound.toggleByUser(); #expect(sound.isMuted)
    }

    @Test func carouselMakesRoomForClipWithoutWaitingForInvalidMedia() {
        #expect(FeaturedBannerVideoPolicy.displayDuration(configuredSeconds: 8, verifiedVideoDuration: 15) == 15)
        #expect(FeaturedBannerVideoPolicy.displayDuration(configuredSeconds: 20, verifiedVideoDuration: 15) == 20)
        for duration in [Double.nan, .infinity, 0, 16] {
            #expect(FeaturedBannerVideoPolicy.displayDuration(configuredSeconds: 8, verifiedVideoDuration: duration) == 8)
        }
        #expect(FeaturedBannerVideoPolicy.displayDuration(configuredSeconds: 0, verifiedVideoDuration: nil) == 3)
        #expect(FeaturedBannerVideoPolicy.displayDuration(configuredSeconds: 99, verifiedVideoDuration: nil) == 30)
    }
}
