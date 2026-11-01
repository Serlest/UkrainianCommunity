import AVKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct FeaturedBannerVideoEditorSection: View {
    @ObservedObject var viewModel: FeaturedBannerEditorViewModel
    let onPoster: (Data) -> Void
    @State private var selection: PhotosPickerItem?
    @State private var source: BannerVideoSource?
    @State private var task: Task<Void, Never>?
    @State private var preparationID = UUID()
    @State private var showFiles = false
    @State private var showPreview = false
    @State private var start = 0.0
    @State private var duration = 15.0
    @State private var player: AVPlayer?

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(BannerVideoText.text("video"), isOn: $viewModel.usesVideo).font(.headline)
                    .accessibilityIdentifier("bannerEditor.video.enabled")
                    .disabled((!viewModel.videoSupported && !viewModel.usesVideo) || viewModel.isProcessingImage)
                if !viewModel.videoSupported { Text(BannerVideoText.text("notEnabled")).font(.caption).foregroundStyle(AppTheme.textSecondary) }
                if viewModel.usesVideo {
                    Text(BannerVideoText.text("helper")).font(.caption).foregroundStyle(AppTheme.textSecondary)
                    HStack {
                        PhotosPicker(selection: $selection, matching: .any(of: [.videos, .images])) {
                            Label(BannerVideoText.text("choose"), systemImage: "photo.on.rectangle")
                        }.accessibilityIdentifier("bannerEditor.video.choose")
                        Button { showFiles = true } label: { Label(BannerVideoText.text("file"), systemImage: "folder") }
                    }.buttonStyle(.bordered).disabled(viewModel.isPreparingVideo || !viewModel.videoSupported || viewModel.isProcessingImage)
                    if viewModel.isPreparingVideo { ProgressView(BannerVideoText.text("preparing")) }
                    if let clip = viewModel.preparedVideo {
                        Button { player = AVPlayer(url: clip.file); player?.isMuted = true; showPreview = true } label: {
                            Label(BannerVideoText.text("preview"), systemImage: "play.circle")
                        }.accessibilityIdentifier("bannerEditor.video.preview")
                        if source != nil {
                            Text(BannerVideoText.text("start") + ": " + String(format: "%.1f s", start)).font(.caption)
                            if clip.sourceDuration > 1.05 { Slider(value: $start, in: 0...(clip.sourceDuration - 1), step: 0.1) }
                            Text(BannerVideoText.text("duration") + ": " + String(format: "%.1f s", min(duration, clip.sourceDuration - start))).font(.caption)
                            Slider(value: $duration, in: 1...max(1.01, min(15, clip.sourceDuration - start)), step: 0.1)
                            Button(BannerVideoText.text("apply")) { prepareCurrent() }.disabled(viewModel.isPreparingVideo || !viewModel.videoSupported)
                        }
                    } else if viewModel.existingVideo != nil { Label(BannerVideoText.text("video"), systemImage: "checkmark.circle") }
                    Text(BannerVideoText.text("crop")).font(.caption).foregroundStyle(AppTheme.textSecondary)
                }
            }
        }
        .task { await viewModel.loadVideoCapabilities() }
        .onChange(of: start) { _, value in
            if let clip = viewModel.preparedVideo { duration = min(duration, max(1, clip.sourceDuration - value)) }
        }
        .onChange(of: selection) { _, item in
            guard let item else { return }
            task?.cancel(); let token = UUID(); preparationID = token; viewModel.isPreparingVideo = true
            task = Task {
                defer { if preparationID == token { viewModel.isPreparingVideo = false } }
                do {
                    guard let loaded = try await item.loadTransferable(type: BannerVideoSource.self) else { throw BannerVideoPreparationError.invalidSource }
                    guard !Task.isCancelled else { try? FileManager.default.removeItem(at: loaded.url); return }
                    if let old = source?.url { try? FileManager.default.removeItem(at: old) }
                    source = loaded; start = 0; duration = 15
                    await prepare(loaded)
                } catch { if !Task.isCancelled { viewModel.errorMessage = BannerVideoText.error(error) } }
            }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.movie, .gif]) { result in
            task?.cancel(); let token = UUID(); preparationID = token; viewModel.isPreparingVideo = true
            task = Task {
                defer { if preparationID == token { viewModel.isPreparingVideo = false } }
                do {
                    let url = try result.get(); let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let loaded = try await Task.detached { try BannerVideoSource.copied(from: url) }.value
                    guard !Task.isCancelled else { try? FileManager.default.removeItem(at: loaded.url); return }
                    if let old = source?.url { try? FileManager.default.removeItem(at: old) }
                    source = loaded; start = 0; duration = 15
                    await prepare(loaded)
                } catch { if !Task.isCancelled { viewModel.errorMessage = BannerVideoText.error(error) } }
            }
        }
        .sheet(isPresented: $showPreview, onDismiss: { player?.pause(); player = nil }) {
            NavigationStack {
                VideoPlayer(player: player).onAppear { player?.play() }.onDisappear { player?.pause() }
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button(BannerVideoText.text("close")) { showPreview = false } } }
            }
        }
        .onDisappear { task?.cancel(); player?.pause(); if let source { try? FileManager.default.removeItem(at: source.url) } }
    }
    private func prepareCurrent() {
        guard let source else { return }; task?.cancel(); task = Task { await prepare(source) }
    }
    private func prepare(_ source: BannerVideoSource) async {
        guard !Task.isCancelled else { return }
        let token = UUID(); preparationID = token
        viewModel.isPreparingVideo = true
        defer { if preparationID == token { viewModel.isPreparingVideo = false } }
        do {
            let clip = try await FeaturedBannerVideoPreparationService.shared.prepare(source, start: start, requestedDuration: min(15, max(1, duration)))
            guard !Task.isCancelled else { try? FileManager.default.removeItem(at: clip.file); return }
            duration = clip.duration
            viewModel.applyPreparedVideo(clip); onPoster(clip.posterData); viewModel.errorMessage = nil
        } catch { if !Task.isCancelled { viewModel.errorMessage = BannerVideoText.error(error) } }
    }
}
