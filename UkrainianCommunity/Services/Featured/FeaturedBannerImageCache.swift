import CryptoKit
import Foundation

/// Bounded public artwork cache. The key includes the authoritative banner revision,
/// so editing an image at the same URL cannot reuse artwork from an older revision.
actor FeaturedBannerImageCache {
    static let shared = FeaturedBannerImageCache(directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("FeaturedBanners/artwork-v1"))
    private let directory: URL?
    private let byteLimit: Int
    private let maximumAge: TimeInterval
    init(directory: URL?, byteLimit: Int = 20 * 1024 * 1024, maximumAge: TimeInterval = 86_400) {
        self.directory = directory
        self.byteLimit = byteLimit
        self.maximumAge = maximumAge
    }
    func data(for key: String, now: Date = .now) -> Data? {
        guard let url = file(for: key),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attributes[.modificationDate] as? Date,
              now.timeIntervalSince(date) >= -60, now.timeIntervalSince(date) <= maximumAge,
              let size = attributes[.size] as? Int, size <= byteLimit else { return nil }
        return try? Data(contentsOf: url)
    }
    func store(_ data: Data, for key: String) {
        guard !data.isEmpty, data.count <= min(byteLimit, 8 * 1024 * 1024), let directory, let url = file(for: key) else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
            let records = files.compactMap { file -> (URL, Int, Date)? in
                guard let v = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
                return (file, v.fileSize ?? 0, v.contentModificationDate ?? .distantPast)
            }.sorted { $0.2 < $1.2 }
            var bytes = records.reduce(0) { $0 + $1.1 }
            var count = records.count
            for (file, size, date) in records where bytes > byteLimit || count > 32 || Date().timeIntervalSince(date) > maximumAge {
                try FileManager.default.removeItem(at: file)
                bytes -= size
                count -= 1
            }
        } catch { /* A cache failure must never prevent loading authoritative artwork. */ }
    }
    private func file(for key: String) -> URL? {
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory?.appendingPathComponent(digest)
    }
}
