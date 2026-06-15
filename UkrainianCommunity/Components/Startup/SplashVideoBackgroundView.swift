import AVFoundation
import SwiftUI
import UIKit

struct SplashVideoBackgroundView: View {
    @Environment(\.colorScheme) private var colorScheme

    private let shouldAnimate: Bool
    private let videoName: String
    private let videoExtension: String

    init(
        shouldAnimate: Bool,
        videoName: String = "startAnimation",
        videoExtension: String = "mp4"
    ) {
        self.shouldAnimate = shouldAnimate
        self.videoName = videoName
        self.videoExtension = videoExtension
    }

    var body: some View {
        Group {
            if let videoURL = Bundle.main.url(forResource: videoName, withExtension: videoExtension) {
                if shouldAnimate {
                    LoopingSplashVideoView(videoURL: videoURL)
                        .ignoresSafeArea()
                        .appBackgroundReadabilityOverlay(for: colorScheme)
                } else {
                    SplashVideoFirstFrameView(videoURL: videoURL)
                        .ignoresSafeArea()
                }
            } else {
                fallbackBackground
            }
        }
    }

    private var fallbackBackground: some View {
        GeometryReader { proxy in
            ZStack {
                AppTheme.glassFallbackSurface(for: colorScheme)
                    .ignoresSafeArea()

                Color.clear
                    .appBackgroundReadabilityOverlay(for: colorScheme)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

private struct LoopingSplashVideoView: View {
    let videoURL: URL

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .center) {
                LoopingVideoLayerView(
                    videoURL: videoURL,
                    videoGravity: .resizeAspectFill
                )
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
                .blur(radius: 24)
                .scaleEffect(1.06)
                .opacity(0.55)
                .clipped()

                LoopingVideoLayerView(
                    videoURL: videoURL,
                    videoGravity: .resizeAspect
                )
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
                .shadow(color: .black.opacity(0.06), radius: 10, y: 6)
                .clipped()
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
    }
}

private struct LoopingVideoLayerView: UIViewRepresentable {
    let videoURL: URL
    let videoGravity: AVLayerVideoGravity

    init(videoURL: URL, videoGravity: AVLayerVideoGravity = .resizeAspect) {
        self.videoURL = videoURL
        self.videoGravity = videoGravity
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(videoURL: videoURL, videoGravity: videoGravity)
    }

    func makeUIView(context: Context) -> PlayerHostView {
        context.coordinator.playerHostView
    }

    func updateUIView(_ uiView: PlayerHostView, context: Context) {
        context.coordinator.configureIfNeeded()
        uiView.startPlaybackIfNeeded()
    }

    func dismantleUIView(_ uiView: PlayerHostView, coordinator: Coordinator) {
        coordinator.playerHostView.stopPlayback()
    }

    final class Coordinator {
        private(set) var playerHostView: PlayerHostView = PlayerHostView()
        private let videoURL: URL
        private let videoGravity: AVLayerVideoGravity

        init(videoURL: URL, videoGravity: AVLayerVideoGravity) {
            self.videoURL = videoURL
            self.videoGravity = videoGravity
        }

        func configureIfNeeded() {
            playerHostView.setupPlayerIfNeeded(with: videoURL, videoGravity: videoGravity)
        }
    }

    final class PlayerHostView: UIView {
        private let playerLayer = AVPlayerLayer()
        private var queuePlayer: AVQueuePlayer?
        private var playerLooper: AVPlayerLooper?
        private var hasConfigured = false

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            layer.addSublayer(playerLayer)
            playerLayer.videoGravity = .resizeAspect
            playerLayer.backgroundColor = UIColor.clear.cgColor
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer.frame = bounds
        }

        func setupPlayerIfNeeded(with url: URL, videoGravity: AVLayerVideoGravity) {
            guard !hasConfigured else {
                return
            }

            let asset = AVURLAsset(url: url)
            let item = AVPlayerItem(asset: asset)

            let queue = AVQueuePlayer()
            queue.isMuted = true
            queue.volume = 0
            queue.automaticallyWaitsToMinimizeStalling = false

            playerLooper = AVPlayerLooper(player: queue, templateItem: item)
            queue.play()

            queuePlayer = queue
            playerLayer.player = queue
            playerLayer.videoGravity = videoGravity

            hasConfigured = true
        }

        func startPlaybackIfNeeded() {
            queuePlayer?.play()
        }

        func stopPlayback() {
            queuePlayer?.pause()
            queuePlayer?.removeAllItems()
            playerLooper = nil
            queuePlayer = nil
            playerLayer.player = nil
        }
    }
}

private struct SplashVideoFirstFrameView: View {
    @Environment(\.colorScheme) private var colorScheme

    let videoURL: URL
    @State private var firstFrame: UIImage?
    @State private var didFail = false

    var body: some View {
        Group {
            if let firstFrame {
                ZStack {
                    fallbackBackground

                    Image(uiImage: firstFrame)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
                .appBackgroundReadabilityOverlay(for: colorScheme)
                .ignoresSafeArea()
            } else if didFail {
                fallbackBackground
            } else {
                Color.clear
                    .task {
                        await generateFirstFrame()
                    }
                    .overlay {
                        fallbackBackground
                            .opacity(firstFrame == nil && didFail ? 1 : 0)
                    }
            }
        }
    }

    private var fallbackBackground: some View {
        AppTheme.glassFallbackSurface(for: colorScheme)
            .appBackgroundReadabilityOverlay(for: colorScheme)
            .ignoresSafeArea()
    }

    private func generateFirstFrame() async {
        guard firstFrame == nil && !didFail else {
            return
        }

        let asset = AVAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true

        do {
            let cgImage = try await Task.detached(priority: .userInitiated) {
                try imageGenerator.copyCGImage(at: .zero, actualTime: nil)
            }.value

            await MainActor.run {
                firstFrame = UIImage(cgImage: cgImage)
            }
        } catch {
            await MainActor.run {
                didFail = true
            }
        }
    }
}
