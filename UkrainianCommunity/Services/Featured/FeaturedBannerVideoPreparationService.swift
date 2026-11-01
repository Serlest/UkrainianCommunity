@preconcurrency import AVFoundation
import CoreTransferable
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated struct BannerVideoSource: Transferable, Sendable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { try copied(from: $0.file) }
        FileRepresentation(importedContentType: .gif) { try copied(from: $0.file) }
    }
    static func copied(from original: URL) throws -> Self {
        let size = try original.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard (1...FeaturedBannerVideoPolicy.maximumSourceBytes).contains(size) else { throw BannerVideoPreparationError.invalidSource }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("uac-banner-video-imports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(original.pathExtension)
        try FileManager.default.copyItem(at: original, to: target)
        return Self(url: target)
    }
}
nonisolated struct PreparedBannerVideoClip: Sendable {
    let id: UUID
    let file: URL
    let posterData: Data
    let duration: Double
    let sourceDuration: Double
}
nonisolated enum BannerVideoPreparationError: Error { case invalidSource, cannotEncode, tooLarge, gifTooComplex }

/// AVFoundation documents cancelExport as the cross-thread cancellation operation.
/// Only that operation crosses isolation; export configuration stays on the service actor.
nonisolated private final class BannerExportCancellation: @unchecked Sendable {
    private let session: AVAssetExportSession
    init(_ session: AVAssetExportSession) { self.session = session }
    func cancel() { session.cancelExport() }
    @available(iOS, introduced: 17, obsoleted: 18)
    func completionResult() -> Result<Void, Error> {
        session.status == .completed ? .success(()) : .failure(session.error ?? BannerVideoPreparationError.cannotEncode)
    }
}

actor FeaturedBannerVideoPreparationService {
    static let shared = FeaturedBannerVideoPreparationService()

    func prepare(_ source: BannerVideoSource, start: Double = 0, requestedDuration: Double = 15) async throws -> PreparedBannerVideoClip {
        let size = try source.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard (1...FeaturedBannerVideoPolicy.maximumSourceBytes).contains(size), start.isFinite, start >= 0,
              requestedDuration.isFinite, (1...15).contains(requestedDuration) else { throw BannerVideoPreparationError.invalidSource }
        let handle = try FileHandle(forReadingFrom: source.url)
        let prefix = try handle.read(upToCount: 6); try handle.close()
        if prefix == Data("GIF89a".utf8) || prefix == Data("GIF87a".utf8) {
            return try await prepareGIF(source.url, start: start, requestedDuration: requestedDuration)
        }
        let asset = AVURLAsset(url: source.url, options: [AVURLAssetReferenceRestrictionsKey: AVAssetReferenceRestrictions.forbidAll.rawValue])
        let duration = try await asset.load(.duration).seconds
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first, tracks.count == 1, duration.isFinite, duration >= 1, duration <= 60,
              audioTracks.count <= 1,
              start < duration, duration - start >= 1 else { throw BannerVideoPreparationError.invalidSource }
        let natural = try await track.load(.naturalSize)
        guard natural.width > 0, natural.height > 0,
              natural.width * natural.height <= Double(FeaturedBannerVideoPolicy.maximumSourcePixelCount) else { throw BannerVideoPreparationError.invalidSource }
        let transform = try await track.load(.preferredTransform)
        let clipDuration = min(requestedDuration, duration - start)
        let timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), duration: CMTime(seconds: clipDuration, preferredTimescale: 600))
        for (width, height, preset) in [(1280, 720, AVAssetExportPreset1280x720), (640, 360, AVAssetExportPresetMediumQuality)] {
            try Task.checkCancellation()
            let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
            var keep = false; defer { if !keep { try? FileManager.default.removeItem(at: output) } }
            guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { throw BannerVideoPreparationError.cannotEncode }
            session.timeRange = timeRange; session.shouldOptimizeForNetworkUse = true
            // Force AAC through the export audio-processing path. Passthrough can
            // retain accumulated priming/edit padding from an already edited source.
            if let audioTrack = audioTracks.first {
                let parameters = AVMutableAudioMixInputParameters(track: audioTrack)
                parameters.setVolume(1, at: .zero)
                let mix = AVMutableAudioMix(); mix.inputParameters = [parameters]
                session.audioMix = mix
            }
            let instruction = AVMutableVideoCompositionInstruction(); instruction.timeRange = CMTimeRange(start: .zero, duration: try await asset.load(.duration))
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
            let bounds = CGRect(origin: .zero, size: natural).applying(transform)
            let scale = max(CGFloat(width) / abs(bounds.width), CGFloat(height) / abs(bounds.height))
            let normalized = transform.concatenating(CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(translationX: (CGFloat(width) - abs(bounds.width) * scale) / 2,
                                               y: (CGFloat(height) - abs(bounds.height) * scale) / 2))
            layer.setTransform(normalized, at: .zero); instruction.layerInstructions = [layer]
            let composition = AVMutableVideoComposition(); composition.renderSize = CGSize(width: width, height: height)
            composition.frameDuration = CMTime(value: 1, timescale: 30); composition.instructions = [instruction]
            session.videoComposition = composition
            try await export(session, to: output)
            let outputSize = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            if outputSize > FeaturedBannerVideoPolicy.maximumRenditionBytes { continue }
            guard outputSize > 0 else { throw BannerVideoPreparationError.cannotEncode }
            let poster = try await posterJPEG(output)
            keep = true
            return .init(id: UUID(), file: output, posterData: poster, duration: clipDuration, sourceDuration: duration)
        }
        throw BannerVideoPreparationError.tooLarge
    }

    private func export(_ session: AVAssetExportSession, to output: URL) async throws {
        let cancellation = BannerExportCancellation(session)
        try await withTaskCancellationHandler {
            if #available(iOS 18, *) { try await session.export(to: output, as: .mp4) }
            else { try await legacyExport(session, to: output) }
            try Task.checkCancellation()
        } onCancel: { cancellation.cancel() }
    }
    @available(iOS, introduced: 17, obsoleted: 18)
    private func legacyExport(_ session: AVAssetExportSession, to output: URL) async throws {
        session.outputURL = output; session.outputFileType = .mp4
        let completion = BannerExportCancellation(session)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                continuation.resume(with: completion.completionResult())
            }
        }
    }
    private func posterJPEG(_ file: URL) async throws -> Data {
        let asset = AVURLAsset(url: file)
        let generator = AVAssetImageGenerator(asset: asset); generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 720)
        let (image, _) = try await generator.image(at: .zero)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { throw BannerVideoPreparationError.cannotEncode }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw BannerVideoPreparationError.cannotEncode }
        return data as Data
    }

    private func prepareGIF(_ url: URL, start: Double, requestedDuration: Double) async throws -> PreparedBannerVideoClip {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { throw BannerVideoPreparationError.invalidSource }
        let count = CGImageSourceGetCount(source)
        guard (2...300).contains(count) else { throw BannerVideoPreparationError.invalidSource }
        var ends: [Double] = [], duration = 0.0, decodedPixelBudget = 0
        for i in 0..<count {
            guard let p = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any],
                  let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int,
                  w > 0, h > 0, w <= FeaturedBannerVideoPolicy.maximumSourcePixelCount / h else { throw BannerVideoPreparationError.invalidSource }
            decodedPixelBudget += w * h
            guard decodedPixelBudget <= 32_000_000 else { throw BannerVideoPreparationError.gifTooComplex }
            let gif = p[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
            guard delay.isFinite, delay >= 0, delay <= 60 else { throw BannerVideoPreparationError.invalidSource }
            duration += delay > 0 ? max(0.01, delay) : 0.1; ends.append(duration)
        }
        let sourceDuration = max(1, duration)
        guard duration > 0, duration <= 60, start < sourceDuration, sourceDuration - start >= 1 else { throw BannerVideoPreparationError.invalidSource }
        let length = min(requestedDuration, sourceDuration - start)
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        var keep = false; defer { if !keep { try? FileManager.default.removeItem(at: output) } }
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 1280, AVVideoHeightKey: 720,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 1_200_000, AVVideoMaxKeyFrameIntervalKey: 30]])
        let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 1280, kCVPixelBufferHeightKey as String: 720, kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true])
        writer.add(input); guard writer.startWriting() else { throw BannerVideoPreparationError.cannotEncode }; writer.startSession(atSourceTime: .zero)
        do {
            let frames = max(30, Int(floor(length * 30)))
            for i in 0..<frames {
                try Task.checkCancellation()
                while !input.isReadyForMoreMediaData {
                    guard writer.status == .writing else { throw BannerVideoPreparationError.cannotEncode }
                    try await Task.sleep(for: .milliseconds(5)); try Task.checkCancellation()
                }
                let time = (start + Double(i) / 30).truncatingRemainder(dividingBy: duration), index = ends.firstIndex(where: { time < $0 }) ?? (count - 1)
                guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1280, kCGImageSourceShouldCache: false] as CFDictionary),
                      let pool = adapter.pixelBufferPool else { throw BannerVideoPreparationError.cannotEncode }
                var buffer: CVPixelBuffer?; guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer) == kCVReturnSuccess, let buffer else { throw BannerVideoPreparationError.cannotEncode }
                CVPixelBufferLockBaseAddress(buffer, [])
                let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 1280, height: 720, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
                let scale = max(1280.0 / Double(image.width), 720.0 / Double(image.height))
                guard let context else { CVPixelBufferUnlockBaseAddress(buffer, []); throw BannerVideoPreparationError.cannotEncode }
                context.draw(image, in: CGRect(x: (1280 - Double(image.width) * scale) / 2, y: (720 - Double(image.height) * scale) / 2,
                                                width: Double(image.width) * scale, height: Double(image.height) * scale))
                CVPixelBufferUnlockBaseAddress(buffer, [])
                guard adapter.append(buffer, withPresentationTime: CMTime(value: Int64(i), timescale: 30)) else { throw BannerVideoPreparationError.cannotEncode }
            }
            input.markAsFinished(); await writer.finishWriting()
            guard writer.status == .completed else { throw BannerVideoPreparationError.cannotEncode }
            let bytes = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard (1...FeaturedBannerVideoPolicy.maximumRenditionBytes).contains(bytes) else { throw BannerVideoPreparationError.tooLarge }
            let poster = try await posterJPEG(output); keep = true
            return .init(id: UUID(), file: output, posterData: poster, duration: Double(frames) / 30, sourceDuration: sourceDuration)
        } catch { writer.cancelWriting(); throw error }
    }
}
