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
    struct PublishedCategory {
        let content: DirectoryManagedCategory
        let revision: Int
        let updatedAt: Date?
    }

    @Published private(set) var published: [String: PublishedCategory] = [:]
    @Published private(set) var isEditor = false
    @Published private(set) var syncState: SyncState = .loading
    private var deletedCategoryIDs: Set<String> = []

    private let db = Firestore.firestore()
    private var contentListener: ListenerRegistration?
    private var accessListener: ListenerRegistration?
    private var observedUserID: String?
    private var isOwner = false
    private var isAccountUsable = false

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
        let builtIn = Self.bundledCategories.map { category in
            published[category.id]?.content ?? category
        }
        let added = published.values.map(\.content).filter { !Self.bundledIDs.contains($0.id) }
        return (builtIn + added).sorted {
            if $0.placement != $1.placement {
                return Self.placementOrder($0.placement) < Self.placementOrder($1.placement)
            }
            return $0.order == $1.order ? $0.id < $1.id : $0.order < $1.order
        }
    }

    private var displayEntries: [DisplayEntry] {
        let builtIn = DirectoryCatalog.categories.enumerated().compactMap { index, category -> DisplayEntry? in
            if let content = published[category.id]?.content {
                guard let visible = content.visibleCategory else { return nil }
                return DisplayEntry(category: visible, placement: content.placement, order: content.order)
            }
            let placement: DirectoryManagedCategory.Placement = Self.startIDs.contains(category.id)
                ? .start : (Self.lifeIDs.contains(category.id) ? .life : .support)
            return DisplayEntry(category: category, placement: placement, order: index * 10)
        }
        let added = published.values.compactMap { item -> DisplayEntry? in
            guard !Self.bundledIDs.contains(item.content.id),
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
        guard let bundled = DirectoryCatalog.categories.first(where: { $0.id == id }) else { return nil }
        return .bundled(bundled)
    }

    func revision(_ id: String) -> Int { published[id]?.revision ?? 0 }

    func publicationDate(_ id: String) -> String? {
        guard let item = published[id] else { return DirectoryGuideCatalog.checkedOn(for: id) }
        guard let date = item.updatedAt else { return nil }
        return date.formatted(.dateTime.day().month().year().locale(Locale(identifier: "de_AT")))
    }

    func managedTopic(categoryID: String, topicID: String) -> DirectoryManagedTopic? {
        guard let content = published[categoryID]?.content, !content.isHidden else { return nil }
        return content.topic(topicID)
    }

    func groups(for category: DirectoryCategory) -> [DirectoryTopicGroup] {
        guard let content = published[category.id]?.content else {
            return DirectoryTopicGroups.forCategory(category)
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
        guard contentListener == nil else { return }
        contentListener = db.collection("directoryCategories")
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if error != nil {
                        self.syncState = .failed
                        return
                    }
                    guard let snapshot else {
                        self.syncState = .failed
                        return
                    }
                    var decoded: [String: PublishedCategory] = [:]
                    var hasInvalidContent = false
                    for document in snapshot.documents {
                        if document.data()["isDeleted"] as? Bool == true {
                            self.deletedCategoryIDs.insert(document.documentID)
                            continue
                        }
                        guard !self.deletedCategoryIDs.contains(document.documentID) else { continue }
                        guard let data = document.data()["payload"] as? String,
                              let revision = document.data()["revision"] as? Int,
                              let raw = data.data(using: .utf8),
                              let content = try? JSONDecoder().decode(DirectoryManagedCategory.self, from: raw),
                              content.id == document.documentID else {
                            hasInvalidContent = true
                            continue
                        }
                        decoded[content.id] = PublishedCategory(
                            content: content, revision: revision,
                            updatedAt: (document.data()["updatedAt"] as? Timestamp)?.dateValue()
                        )
                    }
                    // Only a cached snapshot may lag behind an acknowledged save.
                    // A server snapshot is authoritative, including missing documents.
                    if snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites {
                        for (id, current) in self.published where
                            !self.deletedCategoryIDs.contains(id) &&
                            current.revision > (decoded[id]?.revision ?? -1) {
                            decoded[id] = current
                        }
                    }
                    self.published = decoded
                    self.syncState = hasInvalidContent ? .invalidContent
                        : (snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites
                            ? .cached : .current)
                }
            }
    }

    func retryObserving() {
        contentListener?.remove()
        contentListener = nil
        syncState = .loading
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
