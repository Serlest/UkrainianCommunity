import AVFoundation
import Foundation
import Testing
@testable import UkrainianCommunity

private actor BannerVideoLoadGate {
    private var next = 0
    private var pending: [Int: CheckedContinuation<URL, any Error>] = [:]
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var cancelledReturns = 0
    func file() async throws -> URL {
        let id = next; next += 1
        defer { if Task.isCancelled { cancelledReturns += 1 } }
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            let ready = waiters.filter { $0.0 <= next }
            waiters.removeAll { $0.0 <= next }
            ready.forEach { $0.1.resume() }
        }
    }
    func waitForRequests(_ count: Int) async {
        if next >= count { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
    func finish(_ id: Int, with result: Result<URL, any Error>) { pending.removeValue(forKey: id)?.resume(with: result) }
}

@MainActor @Suite(.timeLimit(.minutes(1)))
struct FeaturedBannerVideoLifecycleTests {
    private var file: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("functions/src/featured/fixtures/banner-video-audio.mp4")
    }
    private func video(_ id: String = "one") -> FeaturedBannerVideoPresentation {
        let sha = String(repeating: "a", count: 64)
        return .init(assetID: id, descriptor: .init(schemaVersion: 1, assetPath: "featuredBannerVideos/\(id)/\(sha).mp4",
            sha256: sha, byteCount: 12840, width: 640, height: 360, durationSeconds: 2, framesPerSecond: 30,
            codec: "h264", hasAudio: true, audioCodec: "aac"), playbackURL: "https://fixture.invalid")
    }
    @Test(arguments: [false, true]) func stopRejectsLateSuccessAndFailure(fail: Bool) async {
        let gate = BannerVideoLoadGate()
        let model = BannerVideoPlayerModel { _, _ in try await gate.file() }
        defer { model.stop() }
        let request = Task { await model.configure(video(), eligible: true, manual: true) }
        await gate.waitForRequests(1)
        model.stop()
        await gate.finish(0, with: fail ? .failure(AppError.network) : .success(file))
        await request.value
        #expect(model.player == nil)
        #expect(!model.failed)
        #expect(!model.rendered)
        #expect(await gate.cancelledReturns == 1)
    }
    @Test func olderRequestCannotReplaceNewPlayerOrItsReadiness() async throws {
        let gate = BannerVideoLoadGate()
        let model = BannerVideoPlayerModel { _, _ in try await gate.file() }
        defer { model.stop() }
        let old = Task { await model.configure(video(), eligible: true, manual: true) }
        await gate.waitForRequests(1)
        let new = Task { await model.configure(video("two"), eligible: true, manual: true) }
        await gate.waitForRequests(2)
        await gate.finish(1, with: .success(file)); await new.value
        let player = try #require(model.player)
        await gate.finish(0, with: .success(file)); await old.value
        #expect(model.player === player)
        model.didRender(AVPlayer())
        #expect(!model.rendered)
        model.didRender(player)
        #expect(model.rendered)
    }
    @Test func interruptionDuringLoadingRequiresExplicitResume() async throws {
        let gate = BannerVideoLoadGate()
        let model = BannerVideoPlayerModel { _, _ in try await gate.file() }
        defer { model.stop() }
        let request = Task { await model.configure(video(), eligible: true, manual: true) }
        await gate.waitForRequests(1)
        model.interrupt()
        await gate.finish(0, with: .success(file)); await request.value
        let player = try #require(model.player)
        #expect(model.paused)
        #expect(player.rate == 0)
        #expect(model.muted)
        model.togglePause()
        #expect(!model.paused)
        #expect(model.muted)
    }
}
