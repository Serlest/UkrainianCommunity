import Foundation

/// Only public feed data is persisted; owner drafts and analytics never enter this cache.
final class FeaturedBannerCache {
    static let maximumStaleAge: TimeInterval = 86_400
    struct Key: Hashable, Codable {
        let section: FeaturedBannerVisibleSection
        let federalState: AustrianFederalState?
    }
    struct Entry: Codable {
        let banners: [FeaturedBanner]
        let lastLoadedAt: Date
    }
    private struct Record: Codable { let key: Key; let entry: Entry }
    private struct Snapshot: Codable { let version: Int; let records: [Record] }
    private var entries: [Key: Entry] = [:]
    private var restoredKeys = Set<Key>()
    private let persistenceURL: URL?
    private let now: () -> Date
    private let writes = DispatchQueue(label: "at.serlest.banner-catalog-cache", qos: .utility)
    private var hasRestored = false
    private var restoreTask: Task<Data?, Never>?
    private var generation = UUID()

    init(persistenceURL: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.persistenceURL = persistenceURL
        self.now = now
    }
    static func persistent() -> FeaturedBannerCache {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        return FeaturedBannerCache(persistenceURL: directory?.appendingPathComponent("FeaturedBanners/catalog-v1.json"))
    }
    func restore() async {
        guard !hasRestored, let persistenceURL else { return }
        let token = generation
        if restoreTask == nil {
            restoreTask = Task.detached(priority: .userInitiated) { try? Data(contentsOf: persistenceURL) }
        }
        let data = await restoreTask?.value
        guard token == generation, !hasRestored else { return }
        hasRestored = true
        restoreTask = nil
        guard let data, data.count <= 2_000_000,
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.version == 1, snapshot.records.count <= 48 else { return }
        for record in snapshot.records where entries[record.key] == nil {
            let age = now().timeIntervalSince(record.entry.lastLoadedAt)
            guard age >= -60, age <= Self.maximumStaleAge, record.entry.banners.count <= 100 else { continue }
            entries[record.key] = record.entry
            restoredKeys.insert(record.key)
        }
    }
    func requiresRevalidation(for key: Key) -> Bool { restoredKeys.contains(key) }
    func entry(for key: Key, maxAge: TimeInterval) -> Entry? {
        guard let entry = entries[key] else { return nil }
        let age = now().timeIntervalSince(entry.lastLoadedAt)
        guard age >= -60, age <= maxAge else { return nil }
        return entry
    }
    func store(_ banners: [FeaturedBanner], for key: Key) -> Entry {
        let entry = Entry(banners: banners, lastLoadedAt: now())
        entries[key] = entry
        restoredKeys.remove(key)
        persist()
        return entry
    }
    func invalidateAll() {
        generation = UUID()
        hasRestored = true
        entries.removeAll()
        restoredKeys.removeAll()
        guard let persistenceURL else { return }
        writes.async { try? FileManager.default.removeItem(at: persistenceURL) }
    }
    private func persist() {
        guard let persistenceURL else { return }
        let snapshot = Snapshot(version: 1, records: entries.compactMap { key, entry in
            guard now().timeIntervalSince(entry.lastLoadedAt) <= Self.maximumStaleAge else { return nil }
            return Record(key: key, entry: entry)
        })
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        writes.async {
            try? FileManager.default.createDirectory(at: persistenceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: persistenceURL, options: .atomic)
        }
    }
    /// Verification and orderly persistence; ordinary feed rendering never waits for disk writes.
    func flush() async { await withCheckedContinuation { continuation in writes.async { continuation.resume() } } }
}
