import Foundation

final class FeaturedBannerCache {
    struct Key: Hashable {
        let section: FeaturedBannerVisibleSection
        let federalState: AustrianFederalState?
    }

    struct Entry {
        let banners: [FeaturedBanner]
        let lastLoadedAt: Date
    }

    private var entries: [Key: Entry] = [:]

    func entry(for key: Key, maxAge: TimeInterval) -> Entry? {
        guard let entry = entries[key] else { return nil }
        guard Date().timeIntervalSince(entry.lastLoadedAt) <= maxAge else { return nil }
        return entry
    }

    func store(_ banners: [FeaturedBanner], for key: Key) -> Entry {
        let entry = Entry(banners: banners, lastLoadedAt: Date())
        entries[key] = entry
        return entry
    }

    func invalidateAll() {
        entries.removeAll()
    }
}
