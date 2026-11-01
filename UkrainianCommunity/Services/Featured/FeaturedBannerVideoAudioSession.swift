@preconcurrency import AVFoundation
import Foundation

/// AVAudioSession activation can block while the route changes. Keep the legacy
/// iOS 17+ APIs on a dedicated serial queue, including category changes. The
/// mutable owner is confined to that queue; late release cannot mute a new owner.
nonisolated final class FeaturedBannerVideoAudioSession: @unchecked Sendable {
    static let shared = FeaturedBannerVideoAudioSession()
    private let queue = DispatchQueue(label: "uac.banner.video.audio", qos: .userInitiated)
    private var owner: UUID?
    private init() {}

    func activate(for request: UUID) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                do {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
                    try session.setActive(true)
                    owner = request
                    continuation.resume(returning: true)
                } catch { continuation.resume(returning: false) }
            }
        }
    }
    func release(_ request: UUID) async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                if owner == request {
                    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                    owner = nil
                }
                continuation.resume()
            }
        }
    }
}
