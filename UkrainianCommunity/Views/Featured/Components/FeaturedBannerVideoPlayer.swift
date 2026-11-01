@preconcurrency import AVFoundation
import Combine
import Network
import SwiftUI
import UIKit

@MainActor final class BannerVideoNetworkState: ObservableObject {
    static let shared = BannerVideoNetworkState()
    @Published private(set) var isConstrained = true
    @Published private(set) var isConnected = false
    private let monitor = NWPathMonitor()
    private init() {
        monitor.pathUpdateHandler = { [weak self] path in Task { @MainActor [weak self] in self?.isConstrained = path.isConstrained; self?.isConnected = path.status == .satisfied } }
        monitor.start(queue: DispatchQueue(label: "uac.banner.video.network"))
    }
}

@MainActor final class BannerVideoPlayerModel: ObservableObject {
    @Published private(set) var player: AVQueuePlayer?
    @Published private(set) var rendered = false
    @Published private(set) var muted = true
    @Published private(set) var failed = false
    @Published private(set) var paused = false
    private static weak var active: BannerVideoPlayerModel?
    private var sessionToken = UUID()
    private var looper: AVPlayerLooper?
    private var assetID: String?
    private var audioRequest: UUID?
    private var itemObservation: NSKeyValueObservation?
    private var playerObservation: NSKeyValueObservation?
    private var pendingLoad: Task<URL, any Error>?
    private let loadFile: @Sendable (FeaturedBannerVideoPresentation, Bool) async throws -> URL

    init(loadFile: @escaping @Sendable (FeaturedBannerVideoPresentation, Bool) async throws -> URL = { video, manual in
        try await FeaturedBannerVideoCache.shared.file(for: video, allowsConstrainedNetwork: manual)
    }) { self.loadFile = loadFile }

    func configure(_ video: FeaturedBannerVideoPresentation, eligible: Bool, manual: Bool) async {
        guard eligible else { stop(); return }
        if assetID == video.assetID, let player { if !paused { player.play() }; return }
        stop(); failed = false
        let token = sessionToken
        let loader = loadFile
        let load = Task { try await loader(video, manual) }
        pendingLoad = load
        defer { if token == sessionToken { pendingLoad = nil } }
        do {
            let file = try await withTaskCancellationHandler {
                try await load.value
            } onCancel: { load.cancel() }
            try Task.checkCancellation()
            guard token == sessionToken else { return }
            Self.active?.stop(); Self.active = self
            let item = AVPlayerItem(url: file)
            let player = AVQueuePlayer(); player.isMuted = true; player.automaticallyWaitsToMinimizeStalling = true
            player.preventsDisplaySleepDuringVideoPlayback = false
            player.actionAtItemEnd = .none
            looper = AVPlayerLooper(player: player, templateItem: item)
            self.assetID = video.assetID; self.player = player
            playerObservation = player.observe(\.currentItem, options: [.initial, .new]) { [weak self] player, _ in
                Task { @MainActor [weak self] in
                    guard let self, self.sessionToken == token else { return }
                    self.itemObservation = player.currentItem?.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                        if item.status == .failed { Task { @MainActor [weak self] in guard let self, self.sessionToken == token else { return }; self.stop(); self.failed = true } }
                    }
                }
            }
            if !paused { player.play() }
        } catch {
            if !Task.isCancelled, token == sessionToken { failed = true }
        }
    }
    func resetSurfaceReadiness() { rendered = false }
    func didRender(_ source: AVPlayer) { if player === source, !rendered { rendered = true } }
    func toggleSound() {
        guard let player, !failed else { return }
        if !muted || audioRequest != nil { mute(); return }
        let request = UUID()
        audioRequest = request; muted = false
        Task { [weak self] in
            let active = await FeaturedBannerVideoAudioSession.shared.activate(for: request)
            guard let self, self.audioRequest == request, self.player === player else {
                await FeaturedBannerVideoAudioSession.shared.release(request); return
            }
            if active { player.isMuted = false } else { self.mute() }
        }
    }
    func mute() {
        muted = true; player?.isMuted = true
        if let request = audioRequest {
            audioRequest = nil
            Task { await FeaturedBannerVideoAudioSession.shared.release(request) }
        }
    }
    func togglePause() { paused.toggle(); if paused { player?.pause(); mute() } else { player?.play() } }
    func interrupt() { paused = true; player?.pause(); mute() }
    func stop() {
        pendingLoad?.cancel(); pendingLoad = nil
        sessionToken = UUID(); if Self.active === self { Self.active = nil }
        mute(); player?.pause(); looper?.disableLooping(); player?.removeAllItems()
        looper = nil; player = nil; assetID = nil; rendered = false; paused = false
        itemObservation = nil; playerObservation = nil
    }
}

struct BannerVideoSurface: UIViewRepresentable {
    let player: AVPlayer?
    var fit = false
    let onReady: (AVPlayer) -> Void
    final class Surface: UIView { override class var layerClass: AnyClass { AVPlayerLayer.self }; var videoLayer: AVPlayerLayer { layer as! AVPlayerLayer } }
    @MainActor final class Coordinator {
        var observer: NSKeyValueObservation?
        var observedPlayer: AVPlayer?
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> Surface { let view = Surface(); view.isUserInteractionEnabled = false; view.isOpaque = false; view.backgroundColor = .clear; return view }
    func updateUIView(_ view: Surface, context: Context) {
        view.videoLayer.videoGravity = fit ? .resizeAspect : .resizeAspectFill
        guard context.coordinator.observedPlayer !== player else { return }
        context.coordinator.observer = nil; context.coordinator.observedPlayer = player; view.videoLayer.player = player
        let coordinator = context.coordinator
        context.coordinator.observer = view.videoLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak coordinator] layer, _ in
            if layer.isReadyForDisplay { Task { @MainActor [weak coordinator] in if let player, coordinator?.observedPlayer === player { onReady(player) } } }
        }
    }
    static func dismantleUIView(_ view: Surface, coordinator: Coordinator) { coordinator.observer = nil; coordinator.observedPlayer = nil; view.videoLayer.player = nil }
}

struct FeaturedBannerVideoPlayer: View {
    let video: FeaturedBannerVideoPresentation
    let title: String
    let inlineEligible: Bool
    let hasAction: Bool
    let onPrimaryAction: () -> Void
    let onExpanded: (Bool) -> Void
    var onReady: (Bool) -> Void = { _ in }
    @StateObject private var model = BannerVideoPlayerModel()
    @ObservedObject private var network = BannerVideoNetworkState.shared
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @AppStorage("bannerVideoAutoplayEnabled") private var autoplay = true
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var expanded = false
    @State private var pendingPrimaryAction = false
    @State private var fullScreenReady = false

    private var eligible: Bool { phase == .active && (expanded || (inlineEligible && network.isConnected && !reduceMotion && !voiceOver && !lowPower && !network.isConstrained && autoplay)) }
    var body: some View {
        ZStack {
            BannerVideoSurface(player: expanded ? nil : model.player, onReady: model.didRender)
                .opacity(model.rendered && !expanded ? 1 : 0).allowsHitTesting(false)
            if hasAction {
                Button(action: onPrimaryAction) { Color.clear.contentShape(Rectangle()) }
                    .buttonStyle(.plain).accessibilityLabel(title + ". " + BannerVideoText.text("open"))
                    .accessibilityIdentifier("featuredBanner.video.openLink")
            }
            VStack {
                Spacer()
                HStack(spacing: 4) {
                    Spacer()
                    if video.descriptor.hasAudio {
                        control(model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", label: BannerVideoText.text(model.muted ? "unmute" : "mute"), id: "sound") { model.toggleSound() }
                            .disabled(model.player == nil)
                    }
                    control("arrow.up.left.and.arrow.down.right", label: BannerVideoText.text("expand"), id: "expand") { model.mute(); model.resetSurfaceReadiness(); fullScreenReady = false; expanded = true }
                }
            }.padding(8)
        }
        .task(id: "\(video.assetID):\(video.playbackURL.hashValue):\(eligible)") {
            if !expanded { await model.configure(video, eligible: eligible, manual: false) }
        }
        .onChange(of: model.rendered) { _, value in if !value { fullScreenReady = false }; onReady(value) }
        .onChange(of: expanded) { _, value in onExpanded(value); if !value { model.mute() } }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange).receive(on: DispatchQueue.main)) { _ in lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification).receive(on: DispatchQueue.main)) { _ in model.interrupt() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification).receive(on: DispatchQueue.main)) { note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue
            if reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue || reason == AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue { model.mute() }
        }
        .onDisappear {
            // Fullscreen covers the inline view. Its own task takes over the same
            // model; leaving the carousel normally still releases all playback.
            if !expanded { model.stop(); onReady(false); onExpanded(false) }
        }
        .fullScreenCover(isPresented: $expanded, onDismiss: { model.mute(); onExpanded(false); if pendingPrimaryAction { pendingPrimaryAction = false; onPrimaryAction() } }) {
            NavigationStack {
                ZStack {
                    Color.black.ignoresSafeArea()
                    BannerVideoSurface(player: model.player, fit: true, onReady: { source in
                        guard model.player === source else { return }
                        fullScreenReady = true; model.didRender(source)
                    })
                    if expanded && (model.player == nil || !fullScreenReady) {
                        if model.failed {
                            VStack(spacing: 16) {
                                Text(BannerVideoText.text("unavailable"))
                                Button(BannerVideoText.text("retry")) { Task { await model.configure(video, eligible: phase == .active, manual: true) } }
                            }.foregroundStyle(.white).padding()
                        }
                        else { ProgressView().tint(.white) }
                    }
                }
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(BannerVideoText.text("close")) { expanded = false }.accessibilityIdentifier("featuredBanner.video.fullscreen.close") }
                }
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        HStack(spacing: 4) {
                            control(model.paused ? "play.fill" : "pause.fill", label: BannerVideoText.text(model.paused ? "play" : "pause"), id: "fullscreen.pause") { model.togglePause() }
                                .disabled(model.player == nil)
                            if video.descriptor.hasAudio {
                                control(model.muted ? "speaker.slash.fill" : "speaker.wave.2.fill", label: BannerVideoText.text(model.muted ? "unmute" : "mute"), id: "fullscreen.sound") { model.toggleSound() }
                                    .disabled(model.player == nil)
                            }
                        }.padding(4).background(.white.opacity(0.12), in: Capsule())
                        Spacer()
                        if hasAction {
                            Button { model.stop(); pendingPrimaryAction = true; expanded = false } label: {
                                Text(BannerVideoText.text("open")).font(.headline).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.75)
                                    .padding(.horizontal, 16).frame(minHeight: 44)
                                    .background(.white.opacity(0.12), in: Capsule())
                            }.buttonStyle(.plain).accessibilityIdentifier("featuredBanner.video.fullscreen.openLink")
                        }
                    }.padding(.horizontal, 16).padding(.vertical, 8).background(.black)
                }
            }
            .task(id: "\(video.assetID):\(video.playbackURL.hashValue):\(phase)") {
                await model.configure(video, eligible: phase == .active, manual: true)
            }
            .onDisappear { model.mute() }
        }
    }
    private func control(_ image: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: image).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            .frame(width: 44, height: 44).background(.black.opacity(0.48), in: Circle()) }
            .buttonStyle(.plain).accessibilityLabel(label).accessibilityIdentifier("featuredBanner.video." + id)
    }
}
