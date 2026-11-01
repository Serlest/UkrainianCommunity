import CryptoKit
import Foundation
import Testing
@testable import UkrainianCommunity

struct FeaturedBannerVideoPresentationTests {
    @Test func deliveryIsBoundToCanonicalOwnedPathAndBucket() throws {
        let digest = String(repeating: "a", count: 64)
        let descriptor = FeaturedBannerVideoDescriptor(schemaVersion: 1, assetPath: "featuredBannerVideos/banner-1/\(digest).mp4", sha256: digest,
            byteCount: 100, width: 1280, height: 720, durationSeconds: 15, framesPerSecond: 30, codec: "h264", hasAudio: false, audioCodec: nil)
        let id = SHA256.hash(data: Data(("banner-1:" + digest).utf8)).map { String(format: "%02x", $0) }.joined()
        let url = "https://firebasestorage.googleapis.com/v0/b/uac.test/o/featuredBannerVideos%2Fbanner-1%2F\(digest).mp4?alt=media&token=test"
        #expect(FeaturedBannerVideoPresentation(assetID: id, descriptor: descriptor, playbackURL: url).isValid(for: "banner-1", bucket: "uac.test"))
        for invalid in [url.replacingOccurrences(of: "uac.test", with: "foreign.test"), url.replacingOccurrences(of: "https:", with: "http:"), url + "#fragment", "https://user:password@firebasestorage.googleapis.com/video.mp4"] {
            #expect(!FeaturedBannerVideoPresentation(assetID: id, descriptor: descriptor, playbackURL: invalid).isValid(for: "banner-1", bucket: "uac.test"))
        }
        let value = FeaturedBannerVideoPresentation(assetID: id, descriptor: descriptor, playbackURL: url)
        #expect(try JSONDecoder().decode(FeaturedBannerVideoPresentation.self, from: JSONEncoder().encode(value)) == value)
        #expect(!value.isValid(for: "banner-2", bucket: "uac.test"))
    }
}
