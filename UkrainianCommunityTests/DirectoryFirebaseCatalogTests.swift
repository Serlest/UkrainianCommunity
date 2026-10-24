import Foundation
import FirebaseFirestore
import FirebaseCore
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
    nonisolated private static var liveAuditFlag: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EnableDirectoryProductionReadAudit")
    }

    /// Explicit read-only opt-in. Normal test runs never depend on production/network access.
    @Test(.enabled(if: FileManager.default.fileExists(atPath: liveAuditFlag.path)
        || ProcessInfo.processInfo.environment["UAC_DIRECTORY_READ_AUDIT"] == "1"
        || ProcessInfo.processInfo.environment["TEST_RUNNER_UAC_DIRECTORY_READ_AUDIT"] == "1"))
    func liveProductionCatalogDecodesAndRoundTripsOffline() async throws {
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        let db = Firestore.firestore()
        #expect(db.app.options.projectID == "ukrainiancommunity-dbd5f")
        #expect(db.settings.host == "firestore.googleapis.com")
        let marker = try await db.collection("appConfig").document("directoryCatalog").getDocument(source: .server)
        #expect(!marker.metadata.isFromCache)
        #expect(DirectoryContentStore.isCompleteCatalogMarker(marker.data()))
        let snapshot = try await db.collection("directoryCategories").getDocuments(source: .server)
        #expect(!snapshot.metadata.isFromCache)
        let baseline = try #require(marker.data()?["baselineCategoryIDs"] as? [String])
        #expect(Set(snapshot.documents.map(\.documentID)).isSuperset(of: Set(baseline)))
        var decoded: [String: DirectoryContentStore.PublishedCategory] = [:]
        for document in snapshot.documents where document.data()["isDeleted"] as? Bool != true {
            let payload = try #require(document.data()["payload"] as? String)
            let content = try JSONDecoder().decode(DirectoryManagedCategory.self, from: Data(payload.utf8))
            #expect(content.id == document.documentID)
            let revision = try #require(document.data()["revision"] as? Int)
            decoded[content.id] = .init(content: content, revision: revision,
                updatedAt: (document.data()["updatedAt"] as? Timestamp)?.dateValue())
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("live-complete.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = DirectoryContentStore(cacheURL: url)
        store.applySnapshot(decoded, cached: false, activateAuthority: true)
        let offline = DirectoryContentStore(cacheURL: url)
        #expect(offline.isAuthoritative && offline.syncState == .cached)
        #expect(Set(offline.allManagedCategories.map(\.id)) == Set(decoded.keys))
        for category in decoded.values {
            #expect(offline.category(category.content.id) == category.content)
        }
        // Exercise a real offline retry on the Simulator's Firestore SDK, without writing production data.
        try await db.disableNetwork()
        do {
            offline.retryObserving()
            try await Task.sleep(for: .milliseconds(200))
            #expect(offline.syncState == .cached)
            #expect(offline.allManagedCategories.count == decoded.count)
            try await db.enableNetwork()
        } catch {
            try? await db.enableNetwork()
            throw error
        }
        await offline.refresh()
        #expect(offline.syncState == .current)
        #expect(offline.isAuthoritative && !offline.categories.isEmpty)
        // Neither an empty SDK cache nor a failed marker/retry may discard the last complete cache.
        offline.applySnapshot([:], cached: true)
        #expect(offline.allManagedCategories.count == decoded.count)
        offline.applySnapshot([:], cached: false, invalid: true)
        #expect(offline.allManagedCategories.count == decoded.count)
        let receipt: [String: Any] = ["project": "ukrainiancommunity-dbd5f", "readAt": ISO8601DateFormatter().string(from: .now),
            "categories": decoded.count, "topics": decoded.values.reduce(0) { $0 + $1.content.topics.count },
            "regionalSections": decoded.values.reduce(0) { sum, category in
                sum + category.content.topics.reduce(0) { $0 + $1.regionalSections.values.reduce(0) { $0 + $1.count } }
            }, "serverMarker": true, "serverSnapshot": true, "offlineRoundTrip": true]
        let receiptURL = Self.liveAuditFlag.deletingLastPathComponent().appendingPathComponent("DirectoryProductionReadAudit.json")
        try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys]).write(to: receiptURL)
        print("LIVE DIRECTORY READ", receipt)
    }

}
