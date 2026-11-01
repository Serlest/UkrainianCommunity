import Foundation

/// Contract for a server-verified rendition, not metadata trusted from an upload.
/// This first-stage type is deliberately not wired to production publication yet.
nonisolated struct FeaturedBannerVideoDescriptor: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let assetPath: String
    let sha256: String
    let byteCount: Int
    let width: Int
    let height: Int
    let durationSeconds: Double
    let framesPerSecond: Double
    let codec: String
    let hasAudio: Bool
    let audioCodec: String?

    func isValid(for bannerID: String) -> Bool {
        guard schemaVersion == 1,
              FeaturedBannerVideoPolicy.isSafeComponent(bannerID),
              sha256.count == 64, sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              assetPath == "featuredBannerVideos/\(bannerID)/\(sha256).mp4",
              (1...FeaturedBannerVideoPolicy.maximumRenditionBytes).contains(byteCount),
              width >= 160, width <= 1280, height >= 90, height <= 720,
              width.isMultiple(of: 2), height.isMultiple(of: 2),
              abs(Double(width) / Double(height) - 16.0 / 9.0) <= 0.01,
              durationSeconds.isFinite, (1...15).contains(durationSeconds),
              framesPerSecond.isFinite, (1...30).contains(framesPerSecond),
              codec == "h264", hasAudio ? audioCodec == "aac" : audioCodec == nil else { return false }
        return true
    }
}

nonisolated enum FeaturedBannerVideoPolicy {
    static let maximumRenditionBytes = 4 * 1024 * 1024
    static let maximumSourceBytes = 50 * 1024 * 1024
    static let maximumSourceDurationSeconds: Double = 60
    static let maximumSourcePixelCount = 3840 * 2160
    static let cacheByteLimit = 24 * 1024 * 1024
    static let minimumVisibleFraction: Double = 0.6

    static func isSafeComponent(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128 && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95
        }
    }

    /// A 15-second clip must not be cut by the old carousel's 12-second cap.
    /// Loading failures never extend the dwell: callers pass nil until verified.
    static func displayDuration(configuredSeconds: Int, verifiedVideoDuration: Double?) -> Int {
        let configured = min(30, max(3, configuredSeconds))
        guard let duration = verifiedVideoDuration, duration.isFinite, (1...15).contains(duration) else { return configured }
        return max(configured, Int(ceil(duration)))
    }
}

nonisolated struct FeaturedBannerVideoPlaybackContext: Equatable, Sendable {
    var selected = false
    var visibleFraction: Double = 0
    var sceneActive = false
    var interactionInProgress = false
    var reduceMotion = false
    var lowPower = false
    var lowData = false
    var autoplayEnabled = true
    var renditionReady = false

    var permitsInlinePlayback: Bool {
        selected && sceneActive && !interactionInProgress && !reduceMotion && !lowPower && !lowData
            && autoplayEnabled && renditionReady && visibleFraction.isFinite
            && (FeaturedBannerVideoPolicy.minimumVisibleFraction...1).contains(visibleFraction)
    }
}

/// Consent is scoped to a single presentation. Never persist an unmuted default.
nonisolated struct FeaturedBannerVideoSoundState: Equatable, Sendable {
    private(set) var presentationID: String?
    private(set) var isMuted = true

    mutating func present(_ id: String?) {
        guard presentationID != id else { return }
        presentationID = id
        isMuted = true
    }

    mutating func toggleByUser() {
        guard presentationID != nil else { return }
        isMuted.toggle()
    }

    mutating func suspend() { isMuted = true }
}
