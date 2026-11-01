@preconcurrency import AVFoundation
import CryptoKit
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import UkrainianCommunity

@MainActor struct FeaturedBannerVideoPreparationTests {
    private func fixture(_ name: String = "banner-video-audio.mp4") -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("functions/src/featured/fixtures/" + name)
    }
    /// Keep actual native encodes for the separate TypeScript MP4 inspector check.
    private func recordRendition(_ file: URL, name: String) throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/banner-video-foundation-20261101/native-renditions", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let output = root.appendingPathComponent(name).appendingPathExtension("mp4")
        try? FileManager.default.removeItem(at: output)
        try FileManager.default.copyItem(at: file, to: output)
    }
    @Test func realMP4PreparationPreservesAudioAndProducesLandscapePoster() async throws {
        let source = try BannerVideoSource.copied(from: fixture())
        defer { try? FileManager.default.removeItem(at: source.url) }
        let clip = try await FeaturedBannerVideoPreparationService.shared.prepare(source, start: 0, requestedDuration: 1)
        defer { try? FileManager.default.removeItem(at: clip.file) }
        #expect(clip.posterData.starts(with: [0xff, 0xd8]))
        #expect((try clip.file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? .max) <= FeaturedBannerVideoPolicy.maximumRenditionBytes)
        let asset = AVURLAsset(url: clip.file)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let size = try await tracks[0].load(.naturalSize)
        #expect(!audio.isEmpty)
        #expect(abs(size.width / size.height - 16 / 9) < 0.01)
        #expect(size.width <= 1280 && size.height <= 720)
        #expect(abs(try await asset.load(.duration).seconds - 1) < 0.15)
    }
    @Test(arguments: [0.4, 0.05]) func GIFIsConvertedWithoutKeepingAllFramesInMemory(delay: Double) async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("gif")
        defer { try? FileManager.default.removeItem(at: file) }
        let destination = try #require(CGImageDestinationCreateWithURL(file as CFURL, UTType.gif.identifier as CFString, 3, nil))
        for i in 0..<3 {
            let context = try #require(CGContext(data: nil, width: 64, height: 36, bitsPerComponent: 8, bytesPerRow: 64 * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(red: CGFloat(i) / 3, green: 0.4, blue: 0.8, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 64, height: 36))
            CGImageDestinationAddImage(destination, try #require(context.makeImage()), [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
        }
        #expect(CGImageDestinationFinalize(destination))
        let clip = try await FeaturedBannerVideoPreparationService.shared.prepare(.init(url: file))
        defer { try? FileManager.default.removeItem(at: clip.file) }
        #expect(clip.duration >= 1 && clip.duration <= 1.3)
        #expect(clip.posterData.starts(with: [0xff, 0xd8]))
        let asset = AVURLAsset(url: clip.file)
        #expect(try await asset.loadTracks(withMediaType: .audio).isEmpty)
        #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
        try recordRendition(clip.file, name: "gif-\(delay)")
    }
    @Test func fullLengthAndEndTrimProduceBoundedActualMP4() async throws {
        let original = AVURLAsset(url: fixture())
        let composition = AVMutableComposition()
        for i in 0..<10 {
            try await composition.insertTimeRange(CMTimeRange(start: .zero, duration: CMTime(seconds: 2, preferredTimescale: 600)), of: original,
                at: CMTime(seconds: Double(i * 2), preferredTimescale: 600))
        }
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        defer { try? FileManager.default.removeItem(at: source) }
        let session = try #require(AVAssetExportSession(asset: composition, presetName: AVAssetExportPreset640x480))
        try await session.export(to: source, as: .mp4)
        for (start, expected) in [(0.0, 15.0), (19.0, 1.0)] {
            let clip = try await FeaturedBannerVideoPreparationService.shared.prepare(.init(url: source), start: start, requestedDuration: 15)
            defer { try? FileManager.default.removeItem(at: clip.file) }
            let result = AVURLAsset(url: clip.file)
            #expect(abs(try await result.load(.duration).seconds - expected) < 0.05)
            #expect(clip.duration == expected)
            #expect((try clip.file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? .max) <= FeaturedBannerVideoPolicy.maximumRenditionBytes)
            #expect(try await result.loadTracks(withMediaType: .audio).count == 1)
            try recordRendition(clip.file, name: "video-\(Int(expected))s")
        }
    }
    @Test func oversizedSourceIsRejectedBeforeCopying() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try FileHandle(forWritingTo: url); try file.truncate(atOffset: UInt64(FeaturedBannerVideoPolicy.maximumSourceBytes + 1)); try file.close()
        #expect(throws: BannerVideoPreparationError.self) { try BannerVideoSource.copied(from: url) }
    }
    @Test func cacheRefusesCorruptionAndBoundsExistingFiles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = try Data(contentsOf: fixture()), digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let descriptor = FeaturedBannerVideoDescriptor(schemaVersion: 1, assetPath: "featuredBannerVideos/banner-1/\(digest).mp4", sha256: digest,
            byteCount: bytes.count, width: 640, height: 360, durationSeconds: 2, framesPerSecond: 30, codec: "h264", hasAudio: true, audioCodec: "aac")
        let presentation = FeaturedBannerVideoPresentation(assetID: digest, descriptor: descriptor, playbackURL: "invalid")
        let target = directory.appendingPathComponent(digest).appendingPathExtension("mp4"); try bytes.write(to: target)
        for i in 0..<8 {
            let old = directory.appendingPathComponent("old-\(i).mp4"); FileManager.default.createFile(atPath: old.path, contents: nil)
            let file = try FileHandle(forWritingTo: old); try file.truncate(atOffset: 4 * 1024 * 1024); try file.close()
        }
        let cache = FeaturedBannerVideoCache(directory: directory)
        #expect(try await cache.file(for: presentation) == target)
        let total = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]).reduce(0) { value, url in value + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        #expect(total <= FeaturedBannerVideoPolicy.cacheByteLimit)
        try Data("corrupt".utf8).write(to: target)
        await #expect(throws: (any Error).self) { try await cache.file(for: presentation) }
    }
}
