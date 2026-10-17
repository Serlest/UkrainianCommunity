import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct DirectoryFirebaseCatalogTests {
    private func category(_ id: String = "health") throws -> DirectoryManagedCategory {
        .bundled(try #require(DirectoryCatalog.categories.first { $0.id == id }))
    }
    private func entry(_ category: DirectoryManagedCategory, revision: Int = 1) -> DirectoryContentStore.PublishedCategory {
        .init(content: category, revision: revision, updatedAt: .now)
    }

    @Test func markerMustExplicitlyConfirmSupportedFirestoreMigration() {
        #expect(DirectoryContentStore.isCompleteCatalogMarker([
            "schemaVersion": 1, "source": "firestore", "migrationComplete": true]))
        for data: [String: Any] in [[:], ["schemaVersion": 2, "source": "firestore", "migrationComplete": true],
            ["schemaVersion": 1, "source": "firestore", "migrationComplete": false],
            ["schemaVersion": 1, "source": "bundled", "migrationComplete": true]] {
            #expect(!DirectoryContentStore.isCompleteCatalogMarker(data))
        }
    }

    @Test func partialCacheBeforeMigrationKeepsBootstrapButCannotActivateAuthority() throws {
        let store = DirectoryContentStore(cacheURL: nil)
        let health = try category()
        store.applySnapshot([health.id: entry(health)], cached: true, activateAuthority: true)
        #expect(!store.isAuthoritative)
        #expect(store.categories.count == DirectoryCatalog.categories.count)
        #expect(store.category("registration") != nil)
        store.applySnapshot([:], deleted: [health.id], cached: false)
        store.applySnapshot([health.id: entry(health)], cached: true)
        #expect(store.published[health.id] == nil) // A cached tombstone must also survive before migration.
    }

    @Test func completeServerCatalogReplacesBundledAndLaterDeletionStaysDeleted() throws {
        let store = DirectoryContentStore(cacheURL: nil)
        let health = try category()
        store.applySnapshot([health.id: entry(health)], cached: false, activateAuthority: true)
        #expect(store.isAuthoritative)
        #expect(store.categories.map(\.id) == [health.id])
        #expect(store.allManagedCategories.map(\.id) == [health.id])
        #expect(store.category("registration") == nil)
        #expect(store.publicationDate("registration") == nil)
        store.applySnapshot([:], cached: false)
        #expect(store.categories.isEmpty && store.allManagedCategories.isEmpty)
        #expect(store.category("health") == nil)
        store.applySnapshot([health.id: entry(health)], cached: true)
        #expect(store.categories.isEmpty) // A stale SDK cache cannot resurrect a deleted entry.
    }

    @Test func invalidServerSnapshotPreservesLastGoodCatalogWithoutMixingFallback() throws {
        let store = DirectoryContentStore(cacheURL: nil)
        let health = try category()
        store.applySnapshot([health.id: entry(health)], cached: false, activateAuthority: true)
        store.applySnapshot([:], cached: false, invalid: true)
        #expect(store.syncState == .invalidContent)
        #expect(store.categories.map(\.id) == [health.id])
        let bootstrap = DirectoryContentStore(cacheURL: nil)
        bootstrap.applySnapshot([:], cached: false, invalid: true, activateAuthority: true)
        #expect(!bootstrap.isAuthoritative)
    }

    @Test func completeOfflineCacheSurvivesRelaunchAndEmptyCatalogPersists() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("complete.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let health = try category()
        let store = DirectoryContentStore(cacheURL: url)
        store.applySnapshot([health.id: entry(health)], cached: false, activateAuthority: true)
        let offline = DirectoryContentStore(cacheURL: url)
        #expect(offline.isAuthoritative && offline.syncState == .cached)
        #expect(offline.categories.map(\.id) == [health.id])
        store.applySnapshot([:], cached: false)
        let emptyOffline = DirectoryContentStore(cacheURL: url)
        #expect(emptyOffline.isAuthoritative && emptyOffline.categories.isEmpty)
        try Data("broken".utf8).write(to: url)
        let corruptOffline = DirectoryContentStore(cacheURL: url)
        #expect(corruptOffline.isAuthoritative && corruptOffline.categories.isEmpty)
        #expect(corruptOffline.syncState == .failed)
    }

    @Test func serverHiddenCategoriesTopicsAndRegionalEditsDriveSearchAndDisplay() throws {
        let store = DirectoryContentStore(cacheURL: nil)
        var health = try category()
        health.title = .init(ukrainian: "Новий пошуковий заголовок", german: "Neuer Suchtitel")
        health.placement = .support
        health.topics[0].regionalSections["wien"] = []
        store.applySnapshot([health.id: entry(health, revision: 2)], cached: false, activateAuthority: true)
        #expect(store.startCategories.isEmpty && store.lifeCategories.isEmpty)
        #expect(store.supportCategories.first?.title.german == "Neuer Suchtitel")
        #expect(store.managedTopic(categoryID: health.id, topicID: health.topics[0].id)?.regionalSections["wien"] == [])
        let matches = DirectorySearchIndex.search("Neuer Suchtitel", language: .german, categories: store.categories,
            managedTopic: { store.managedTopic(categoryID: $0, topicID: $1) })
        #expect(!matches.isEmpty)
        health.isHidden = true
        store.applySnapshot([health.id: entry(health, revision: 3)], cached: false)
        #expect(store.categories.isEmpty && store.allManagedCategories.count == 1)
        #expect(store.managedTopic(categoryID: health.id, topicID: health.topics[0].id) == nil)
        store.applySnapshot([:], deleted: [health.id], cached: false)
        #expect(store.allManagedCategories.isEmpty)
    }
}
