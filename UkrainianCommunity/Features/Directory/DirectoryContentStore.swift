import FirebaseFirestore
import FirebaseFunctions
import Foundation
import Combine

@MainActor
final class DirectoryContentStore: ObservableObject {
    enum SyncState: Equatable {
        case loading
        case cached
        case current
        case failed
        case invalidContent
    }

    private static let bundledCategories = DirectoryCatalog.categories.map(DirectoryManagedCategory.bundled)
    private static let bundledIDs = Set(DirectoryCatalog.categories.map(\.id))
    private static let startIDs = Set(DirectoryCatalog.startCategories.map(\.id))
    private static let lifeIDs = Set(DirectoryCatalog.lifeCategories.map(\.id))
    private struct DisplayEntry {
        let category: DirectoryCategory
        let placement: DirectoryManagedCategory.Placement
        let order: Int
    }
    struct PublishedCategory: Codable {
        let content: DirectoryManagedCategory
        let revision: Int
        let updatedAt: Date?
    }

    @Published private(set) var published: [String: PublishedCategory] = [:]
    @Published private(set) var isAuthoritative = false
    @Published private(set) var isEditor = false
    @Published private(set) var syncState: SyncState = .loading
    private var deletedCategoryIDs: Set<String> = []

    private lazy var db = Firestore.firestore()
    private let cacheURL: URL?
    private var catalogListener: ListenerRegistration?
    private var activationInProgress = false
    private var contentListener: ListenerRegistration?
    private var accessListener: ListenerRegistration?
    private var observedUserID: String?
    private var isOwner = false
    private var isAccountUsable = false

    private struct CatalogCache: Codable {
        let schemaVersion: Int
        let categories: [String: PublishedCategory]
    }

    nonisolated static var defaultCacheURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("DirectoryCatalog", isDirectory: true)
            .appendingPathComponent("complete-v1.json")
    }

    init(cacheURL: URL? = DirectoryContentStore.defaultCacheURL) {
        self.cacheURL = cacheURL
        if let cacheURL, let data = try? Data(contentsOf: cacheURL),
           let cache = try? JSONDecoder().decode(CatalogCache.self, from: data),
           cache.schemaVersion == 1,
           cache.categories.allSatisfy({ $0.key == $0.value.content.id && $0.value.revision > 0 }) {
            published = cache.categories
            isAuthoritative = true
            syncState = .cached
        } else if let cacheURL, FileManager.default.fileExists(atPath: cacheURL.appendingPathExtension("activated").path) {
            // Cache loss/corruption must not revive bundled entries deleted after migration.
            isAuthoritative = true
            syncState = .failed
        }
    }

    var canEdit: Bool { isOwner || isEditor }
    var categories: [DirectoryCategory] {
        displayEntries.map(\.category)
    }
    var visibleRouteSignature: String {
        categories.map { category in
            "\(category.id):\(category.topics.map(\.id).joined(separator: ","))"
        }.joined(separator: "|")
    }
    var startCategories: [DirectoryCategory] { categories(in: .start) }
    var lifeCategories: [DirectoryCategory] { categories(in: .life) }
    var supportCategories: [DirectoryCategory] { categories(in: .support) }

    var allManagedCategories: [DirectoryManagedCategory] {
        let builtIn = (isAuthoritative ? [] : Self.bundledCategories).map { category in
            published[category.id]?.content ?? category
        }
        let added = published.values.map(\.content).filter { (isAuthoritative || !Self.bundledIDs.contains($0.id)) }
        return (builtIn + added).sorted {
            if $0.placement != $1.placement {
                return Self.placementOrder($0.placement) < Self.placementOrder($1.placement)
            }
            return $0.order == $1.order ? $0.id < $1.id : $0.order < $1.order
        }
    }

    private var displayEntries: [DisplayEntry] {
        let builtIn = (isAuthoritative ? [] : DirectoryCatalog.categories).enumerated().compactMap { index, category -> DisplayEntry? in
            if let content = published[category.id]?.content {
                guard let visible = content.visibleCategory else { return nil }
                return DisplayEntry(category: visible, placement: content.placement, order: content.order)
            }
            let placement: DirectoryManagedCategory.Placement = Self.startIDs.contains(category.id)
                ? .start : (Self.lifeIDs.contains(category.id) ? .life : .support)
            return DisplayEntry(category: category, placement: placement, order: index * 10)
        }
        let added = published.values.compactMap { item -> DisplayEntry? in
            guard (isAuthoritative || !Self.bundledIDs.contains(item.content.id)),
                  let visible = item.content.visibleCategory else { return nil }
            return DisplayEntry(category: visible, placement: item.content.placement, order: item.content.order)
        }
        return (builtIn + added).sorted {
            if $0.placement != $1.placement {
                return Self.placementOrder($0.placement) < Self.placementOrder($1.placement)
            }
            return $0.order == $1.order
                ? $0.category.id < $1.category.id : $0.order < $1.order
        }
    }

    func category(_ id: String) -> DirectoryManagedCategory? {
        if let published = published[id] { return published.content }
        guard !isAuthoritative, let bundled = DirectoryCatalog.categories.first(where: { $0.id == id }) else { return nil }
        return .bundled(bundled)
    }

    func revision(_ id: String) -> Int { published[id]?.revision ?? 0 }

    func publicationDate(_ id: String) -> String? {
        guard let item = published[id] else { return isAuthoritative ? nil : DirectoryGuideCatalog.checkedOn(for: id) }
        guard let date = item.updatedAt else { return nil }
        return date.formatted(.dateTime.day().month().year().locale(Locale(identifier: "de_AT")))
    }

    func managedTopic(categoryID: String, topicID: String) -> DirectoryManagedTopic? {
        guard let content = published[categoryID]?.content, !content.isHidden else { return nil }
        return content.topic(topicID)
    }

    func groups(for category: DirectoryCategory) -> [DirectoryTopicGroup] {
        guard let content = published[category.id]?.content else {
            return isAuthoritative ? [] : DirectoryTopicGroups.forCategory(category)
        }
        return content.groups.filter { group in
            !group.isHidden && content.topics.contains { !$0.isHidden && $0.groupID == group.id }
        }.sorted { $0.order < $1.order }.map { group in
            DirectoryTopicGroup(group.id, group.title.ukrainian, group.title.german,
                                content.topics.filter { !$0.isHidden && $0.groupID == group.id }
                                    .sorted { $0.order < $1.order }.map(\.id))
        }
    }

    func configure(user: AppUser?) {
        let uid = user?.id
        let owner = PermissionService.isAppOwner(user: user)
        let usable = PermissionService.isUsableAccount(user: user)
        guard observedUserID != uid || isOwner != owner || isAccountUsable != usable else { return }
        observedUserID = uid
        isOwner = owner
        isAccountUsable = usable
        isEditor = false
        accessListener?.remove()
        accessListener = nil
        guard let uid, usable, !owner else { return }
        accessListener = db.collection("directoryEditors").document(uid)
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor in
                    guard self?.observedUserID == uid else { return }
                    self?.isEditor = snapshot?.data()?["enabled"] as? Bool == true
                }
            }
    }

    func startObserving() {
        if catalogListener == nil {
            catalogListener = db.collection("appConfig").document("directoryCatalog")
                .addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, _ in
                    Task { @MainActor in
                        guard let self, let snapshot, !snapshot.metadata.isFromCache,
                              Self.isCompleteCatalogMarker(snapshot.data()),
                              !self.isAuthoritative, !self.activationInProgress else { return }
                        self.activationInProgress = true
                        defer { self.activationInProgress = false }
                        do {
                            // A separate server read AFTER the marker prevents activating a partial local cache.
                            let complete = try await self.db.collection("directoryCategories").getDocuments(source: .server)
                            self.consume(complete, activateAuthority: true)
                        } catch {
                            self.syncState = .failed
                        }
                    }
                }
        }
        guard contentListener == nil else { return }
        contentListener = db.collection("directoryCategories")
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, _ in
                Task { @MainActor in
                    guard let self else { return }
                    guard let snapshot else { self.syncState = .failed; return }
                    self.consume(snapshot)
                }
            }
    }

    static func isCompleteCatalogMarker(_ data: [String: Any]?) -> Bool {
        data?["schemaVersion"] as? Int == 1 && data?["source"] as? String == "firestore"
            && data?["migrationComplete"] as? Bool == true
    }

    private func consume(_ snapshot: QuerySnapshot, activateAuthority: Bool = false) {
        var decoded: [String: PublishedCategory] = [:]
        var deleted = Set<String>()
        var invalid = false
        for document in snapshot.documents {
            if document.data()["isDeleted"] as? Bool == true {
                deleted.insert(document.documentID)
                continue
            }
            guard let payload = document.data()["payload"] as? String,
                  let revision = document.data()["revision"] as? Int, revision > 0,
                  let raw = payload.data(using: .utf8),
                  let content = try? JSONDecoder().decode(DirectoryManagedCategory.self, from: raw),
                  content.id == document.documentID else { invalid = true; continue }
            decoded[content.id] = PublishedCategory(content: content, revision: revision,
                updatedAt: (document.data()["updatedAt"] as? Timestamp)?.dateValue())
        }
        applySnapshot(decoded, deleted: deleted,
            cached: snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites,
            invalid: invalid, activateAuthority: activateAuthority)
    }

    /// Applies only a whole query snapshot; never persist a partial Firestore cache as a complete catalog.
    func applySnapshot(_ incoming: [String: PublishedCategory], deleted: Set<String> = [],
                       cached: Bool, invalid: Bool = false, activateAuthority: Bool = false) {
        if isAuthoritative && cached { return }
        if invalid && (isAuthoritative || activateAuthority) {
            syncState = .invalidContent
            return // Preserve the last valid complete snapshot, rather than mixing bundled records into it.
        }
        let effectiveDeleted = cached ? deleted.union(deletedCategoryIDs) : deleted
        var decoded = incoming
        if cached {
            for (id, current) in published where !effectiveDeleted.contains(id)
                && current.revision > (decoded[id]?.revision ?? -1) { decoded[id] = current }
        }
        deletedCategoryIDs = effectiveDeleted
        for id in effectiveDeleted { decoded.removeValue(forKey: id) }
        published = decoded
        if activateAuthority && !cached { isAuthoritative = true }
        syncState = invalid ? .invalidContent : (cached ? .cached : .current)
        if isAuthoritative && !cached { persistCompleteCatalog() }
    }

    private func persistCompleteCatalog() {
        guard let cacheURL else { return }
        do {
            let data = try JSONEncoder().encode(CatalogCache(schemaVersion: 1, categories: published))
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(),
                                                   withIntermediateDirectories: true)
            try Data("1".utf8).write(to: cacheURL.appendingPathExtension("activated"), options: .atomic)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            // Current content remains usable; do not silently replace an older valid disk snapshot.
        }
    }

    func retryObserving() {
        contentListener?.remove()
        contentListener = nil
        catalogListener?.remove()
        catalogListener = nil
        syncState = isAuthoritative ? .cached : .loading
        startObserving()
    }

    func save(_ category: DirectoryManagedCategory, expectedRevision: Int, actorID: String) async throws {
        guard canEdit, observedUserID == actorID else { throw AppError.permissionDenied }
        let category = DirectorySourceValidation.normalizingSources(in: category)
        let encoded = try DirectoryManagedValidation.validate(category)
        guard let payload = String(data: encoded, encoding: .utf8) else {
            throw DirectoryManagedValidation.Failure.invalidContent
        }
        let response = try await Functions.functions(region: "europe-west3")
            .httpsCallable("saveDirectoryCategory")
            .call(["categoryId": category.id, "payload": payload,
                   "expectedRevision": expectedRevision])
        guard let result = response.data as? [String: Any],
              result["categoryId"] as? String == category.id,
              result["revision"] as? Int == expectedRevision + 1 else {
            throw AppError.validationFailed
        }
        let nextRevision = expectedRevision + 1
        if (published[category.id]?.revision ?? 0) <= nextRevision {
            published[category.id] = PublishedCategory(
                content: category, revision: nextRevision, updatedAt: Date()
            )
            if isAuthoritative { persistCompleteCatalog() }
        }
    }

    func deleteCustomCategory(_ id: String, expectedRevision: Int, actorID: String) async throws {
        guard canEdit, observedUserID == actorID else { throw AppError.permissionDenied }
        guard id.hasPrefix("custom-"), expectedRevision > 0 else {
            throw DirectoryManagedValidation.Failure.invalidContent
        }
        let response = try await Functions.functions(region: "europe-west3")
            .httpsCallable("deleteDirectoryCategory")
            .call(["categoryId": id, "expectedRevision": expectedRevision])
        guard let result = response.data as? [String: Any],
              result["categoryId"] as? String == id,
              result["revision"] as? Int == expectedRevision + 1 else {
            throw AppError.validationFailed
        }
        deletedCategoryIDs.insert(id)
        published.removeValue(forKey: id)
        if isAuthoritative { persistCompleteCatalog() }
    }

    private func categories(in placement: DirectoryManagedCategory.Placement) -> [DirectoryCategory] {
        displayEntries.filter { $0.placement == placement }.map(\.category)
    }

    private static func placementOrder(_ value: DirectoryManagedCategory.Placement) -> Int {
        switch value {
        case .start: 0
        case .life: 1
        case .support: 2
        }
    }
}
