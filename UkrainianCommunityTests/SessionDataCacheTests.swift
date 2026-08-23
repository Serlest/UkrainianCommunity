import Foundation
import Testing
@testable import UkrainianCommunity

struct SessionDataCacheTests {
    @Test func returnsStoredInteractionStateAndUpdatesLoadedSets() async {
        let cache = SessionDataCache()
        let userID = "user-a"

        await cache.storeLikedNewsIDs(["news-1"], for: userID)
        await cache.updateLikedNewsID("news-2", isLiked: true, for: userID)
        await cache.updateLikedNewsID("news-1", isLiked: false, for: userID)

        let likedNewsIDs = await cache.cachedLikedNewsIDs(for: userID)
        #expect(likedNewsIDs == ["news-2"])
    }

    @Test func doesNotInventACompleteSetWhenMutationWasNotLoaded() async {
        let cache = SessionDataCache()

        await cache.updateBookmarkedEventID("event-1", isBookmarked: true, for: "user-a")

        let bookmarkedEventIDs = await cache.cachedBookmarkedEventIDs(for: "user-a")
        #expect(bookmarkedEventIDs == nil)
    }

    @Test func expiresCachedStateAtTheConfiguredTTL() async {
        let cache = SessionDataCache(ttl: 0)

        await cache.storeRegisteredEventIDs(["event-1"], for: "user-a")

        let registeredEventIDs = await cache.cachedRegisteredEventIDs(for: "user-a")
        #expect(registeredEventIDs == nil)
    }

    @Test func authChangeClearsInteractionAndProfileState() async {
        let cache = SessionDataCache()
        let profile = PublicUserProfile(
            id: "profile-1",
            displayName: "Test User",
            avatarURL: nil,
            city: "Vienna",
            federalState: .wien,
            updatedAt: .now
        )

        await cache.storeSubscribedOrganizationIDs(["organization-1"], for: "user-a")
        await cache.storePublicProfiles([profile], for: "user-a")
        await cache.resetForAuthChange(userID: "user-b")

        let subscribedOrganizationIDs = await cache.cachedSubscribedOrganizationIDs(for: "user-a")
        #expect(subscribedOrganizationIDs == nil)
        let profiles = await cache.cachedPublicProfiles(for: [profile.id], userID: "user-a")
        #expect(profiles.profiles.isEmpty)
        #expect(Set(profiles.missingIDs) == [profile.id])
    }

    @Test func publicProfileLookupReturnsHitsAndOnlyMissingIdentifiers() async {
        let cache = SessionDataCache()
        let profile = PublicUserProfile(
            id: "profile-1",
            displayName: "Test User",
            avatarURL: nil,
            city: "Graz",
            federalState: .steiermark,
            updatedAt: .now
        )

        await cache.storePublicProfiles([profile], for: "user-a")
        let result = await cache.cachedPublicProfiles(
            for: [profile.id, "profile-2", profile.id],
            userID: "user-a"
        )

        #expect(result.profiles[profile.id] == profile)
        #expect(Set(result.missingIDs) == ["profile-2"])
    }
}
