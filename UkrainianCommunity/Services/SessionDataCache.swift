import Foundation

/// App-level memory contract for authenticated interaction state used by feed and detail mapping.
actor SessionDataCache {
    private struct CachedSet {
        var ids: Set<String>
        var loadedAt: Date
    }

    private struct CachedProfile {
        var profile: PublicUserProfile
        var loadedAt: Date
    }

    private struct UserCache {
        var likedNewsIDs: CachedSet?
        var bookmarkedNewsIDs: CachedSet?
        var likedEventIDs: CachedSet?
        var bookmarkedEventIDs: CachedSet?
        var registeredEventIDs: CachedSet?
        var likedOrganizationIDs: CachedSet?
        var subscribedOrganizationIDs: CachedSet?
        var bookmarkedOrganizationIDs: CachedSet?
        var publicProfiles: [String: CachedProfile] = [:]
    }

    private let ttl: TimeInterval
    private var activeUserID: String?
    private var userCaches: [String: UserCache] = [:]

    init(ttl: TimeInterval = 300) {
        self.ttl = ttl
    }

    func resetForAuthChange(userID: String?) {
        activeUserID = userID
        userCaches.removeAll()
    }

    func cachedLikedNewsIDs(for userID: String) -> Set<String>? {
        cachedSet(\.likedNewsIDs, for: userID)
    }

    func storeLikedNewsIDs(_ ids: Set<String>, for userID: String) {
        storeSet(ids, for: userID, keyPath: \UserCache.likedNewsIDs)
    }

    func updateLikedNewsID(_ id: String, isLiked: Bool, for userID: String) {
        updateSet(id: id, isIncluded: isLiked, for: userID, keyPath: \UserCache.likedNewsIDs)
    }

    func cachedBookmarkedNewsIDs(for userID: String) -> Set<String>? {
        cachedSet(\.bookmarkedNewsIDs, for: userID)
    }

    func storeBookmarkedNewsIDs(_ ids: Set<String>, for userID: String) {
        storeSet(ids, for: userID, keyPath: \UserCache.bookmarkedNewsIDs)
    }

    func updateBookmarkedNewsID(_ id: String, isBookmarked: Bool, for userID: String) {
        updateSet(id: id, isIncluded: isBookmarked, for: userID, keyPath: \UserCache.bookmarkedNewsIDs)
    }

    func cachedLikedEventIDs(for userID: String) -> Set<String>? {
        cachedSet(\.likedEventIDs, for: userID)
    }

    func storeLikedEventIDs(_ ids: Set<String>, for userID: String) {
        storeSet(ids, for: userID, keyPath: \UserCache.likedEventIDs)
    }

    func updateLikedEventID(_ id: String, isLiked: Bool, for userID: String) {
        updateSet(id: id, isIncluded: isLiked, for: userID, keyPath: \UserCache.likedEventIDs)
    }

    func cachedBookmarkedEventIDs(for userID: String) -> Set<String>? {
        cachedSet(\.bookmarkedEventIDs, for: userID)
    }

    func storeBookmarkedEventIDs(_ ids: Set<String>, for userID: String) {
        storeSet(ids, for: userID, keyPath: \UserCache.bookmarkedEventIDs)
    }

    func updateBookmarkedEventID(_ id: String, isBookmarked: Bool, for userID: String) {
        updateSet(id: id, isIncluded: isBookmarked, for: userID, keyPath: \UserCache.bookmarkedEventIDs)
    }

    func cachedRegisteredEventIDs(for userID: String) -> Set<String>? {
        cachedSet(\.registeredEventIDs, for: userID)
    }

    func storeRegisteredEventIDs(_ ids: Set<String>, for userID: String) {
        storeSet(ids, for: userID, keyPath: \UserCache.registeredEventIDs)
    }

    func updateRegisteredEventID(_ id: String, isRegistered: Bool, for userID: String) {
        updateSet(id: id, isIncluded: isRegistered, for: userID, keyPath: \UserCache.registeredEventIDs)
    }

    func cachedLikedOrganizationIDs(for userID: String) -> Set<String>? {
        cachedSet(\.likedOrganizationIDs, for: userID)
    }

    func storeLikedOrganizationIDs(_ ids: Set<String>, for userID: String) {
        storeSet(ids, for: userID, keyPath: \UserCache.likedOrganizationIDs)
    }

    func updateLikedOrganizationID(_ id: String, isLiked: Bool, for userID: String) {
        updateSet(id: id, isIncluded: isLiked, for: userID, keyPath: \UserCache.likedOrganizationIDs)
    }

    func cachedSubscribedOrganizationIDs(for userID: String) -> Set<String>? {
        cachedSet(\.subscribedOrganizationIDs, for: userID)
    }

    func storeSubscribedOrganizationIDs(_ ids: Set<String>, for userID: String) {
        storeSet(ids, for: userID, keyPath: \UserCache.subscribedOrganizationIDs)
    }

    func updateSubscribedOrganizationID(_ id: String, isSubscribed: Bool, for userID: String) {
        updateSet(id: id, isIncluded: isSubscribed, for: userID, keyPath: \UserCache.subscribedOrganizationIDs)
    }

    func cachedBookmarkedOrganizationIDs(for userID: String) -> Set<String>? {
        cachedSet(\.bookmarkedOrganizationIDs, for: userID)
    }

    func storeBookmarkedOrganizationIDs(_ ids: Set<String>, for userID: String) {
        storeSet(ids, for: userID, keyPath: \UserCache.bookmarkedOrganizationIDs)
    }

    func updateBookmarkedOrganizationID(_ id: String, isBookmarked: Bool, for userID: String) {
        updateSet(id: id, isIncluded: isBookmarked, for: userID, keyPath: \UserCache.bookmarkedOrganizationIDs)
    }

    func cachedPublicProfiles(for userIDs: [String], userID: String) -> (profiles: [String: PublicUserProfile], missingIDs: [String]) {
        let uniqueIDs = Array(Set(userIDs)).filter { !$0.isEmpty }
        guard !uniqueIDs.isEmpty else { return ([:], []) }

        let now = Date()
        let cache = userCaches[userID]?.publicProfiles ?? [:]
        var profiles: [String: PublicUserProfile] = [:]
        var missingIDs: [String] = []

        for id in uniqueIDs {
            if let cached = cache[id], now.timeIntervalSince(cached.loadedAt) < ttl {
                profiles[id] = cached.profile
            } else {
                missingIDs.append(id)
            }
        }

        return (profiles, missingIDs)
    }

    func storePublicProfiles(_ profiles: [PublicUserProfile], for userID: String) {
        guard !profiles.isEmpty else { return }
        var cache = cache(for: userID)
        let now = Date()
        for profile in profiles {
            cache.publicProfiles[profile.id] = CachedProfile(profile: profile, loadedAt: now)
        }
        userCaches[userID] = cache
    }

    private func cachedSet(_ keyPath: KeyPath<UserCache, CachedSet?>, for userID: String) -> Set<String>? {
        guard let cached = userCaches[userID]?[keyPath: keyPath] else { return nil }
        guard Date().timeIntervalSince(cached.loadedAt) < ttl else { return nil }
        return cached.ids
    }

    private func storeSet(_ ids: Set<String>, for userID: String, keyPath: WritableKeyPath<UserCache, CachedSet?>) {
        var cache = cache(for: userID)
        cache[keyPath: keyPath] = CachedSet(ids: ids, loadedAt: Date())
        userCaches[userID] = cache
    }

    private func updateSet(id: String, isIncluded: Bool, for userID: String, keyPath: WritableKeyPath<UserCache, CachedSet?>) {
        guard var cached = userCaches[userID]?[keyPath: keyPath] else { return }
        if isIncluded {
            cached.ids.insert(id)
        } else {
            cached.ids.remove(id)
        }
        cached.loadedAt = Date()

        var cache = cache(for: userID)
        cache[keyPath: keyPath] = cached
        userCaches[userID] = cache
    }

    private func cache(for userID: String) -> UserCache {
        userCaches[userID] ?? UserCache()
    }
}
