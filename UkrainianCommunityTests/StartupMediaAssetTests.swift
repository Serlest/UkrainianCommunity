import AVFoundation
import Testing

@Suite("Startup media asset")
struct StartupMediaAssetTests {
    @Test
    func splashVideoContainsVideoWithoutAudio() async throws {
        let videoURL = try #require(
            Bundle.main.url(forResource: "startAnimation", withExtension: "mp4")
        )
        let asset = AVURLAsset(url: videoURL)

        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let duration = try await asset.load(.duration)
        let isPlayable = try await asset.load(.isPlayable)

        #expect(videoTracks.count == 1)
        #expect(audioTracks.isEmpty)
        #expect(CMTimeGetSeconds(duration) > 0)
        #expect(isPlayable)
    }
}
