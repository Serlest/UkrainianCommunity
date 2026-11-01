import CryptoKit
import Foundation

nonisolated private final class BannerVideoDownloadLimit: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let limit: Int64
    init(_ limit: Int) { self.limit = Int64(limit) }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > limit || totalBytesExpectedToWrite > limit { downloadTask.cancel() }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}

actor FeaturedBannerVideoCache {
    static let shared = FeaturedBannerVideoCache()
    private let directory: URL?
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("FeaturedBanners/video-v1", isDirectory: true)
    }
    func file(for video: FeaturedBannerVideoPresentation, allowsConstrainedNetwork: Bool = false) async throws -> URL {
        let d = video.descriptor
        guard d.byteCount > 0, d.byteCount <= FeaturedBannerVideoPolicy.maximumRenditionBytes,
              d.sha256.count == 64, d.sha256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              let directory else { throw AppError.validationFailed }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent(d.sha256).appendingPathExtension("mp4")
        if let size = try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize, size == d.byteCount,
           let bytes = try? Data(contentsOf: target, options: .mappedIfSafe), matches(bytes, descriptor: d) {
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: target.path)
            try? trim(excluding: target)
            return target
        }
        guard let url = URL(string: video.playbackURL), url.scheme == "https", url.host == "firebasestorage.googleapis.com" else { throw AppError.validationFailed }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false; configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 20; configuration.allowsConstrainedNetworkAccess = allowsConstrainedNetwork
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (temporary, response) = try await session.download(from: url, delegate: BannerVideoDownloadLimit(d.byteCount))
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Task.checkCancellation()
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize, size == d.byteCount else { throw AppError.validationFailed }
        let bytes = try Data(contentsOf: temporary, options: .mappedIfSafe)
        guard matches(bytes, descriptor: d) else { throw AppError.validationFailed }
        try Task.checkCancellation(); try bytes.write(to: target, options: .atomic)
        try trim(excluding: target)
        return target
    }
    private func matches(_ bytes: Data, descriptor: FeaturedBannerVideoDescriptor) -> Bool {
        bytes.count == descriptor.byteCount && SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() == descriptor.sha256
    }
    private func trim(excluding current: URL) throws {
        guard let directory else { return }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
        let entries = files.compactMap { url -> (URL, Int, Date)? in
            guard let v = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
            return (url, v.fileSize ?? 0, v.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var total = entries.reduce(0) { $0 + $1.1 }
        for (file, size, date) in entries where file != current && (total > FeaturedBannerVideoPolicy.cacheByteLimit || Date().timeIntervalSince(date) > 7 * 86400) {
            try? FileManager.default.removeItem(at: file); total -= size
        }
    }
}
