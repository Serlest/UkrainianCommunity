import FirebaseFirestore
import FirebaseFunctions
import Foundation
import Combine

@MainActor
final class DirectoryContentStore: ObservableObject {
    private static let bundledCategories = DirectoryCatalog.categories.map(DirectoryManagedCategory.bundled)
    private static let bundledIDs = Set(DirectoryCatalog.categories.map(\.id))
    struct PublishedCategory {
        let content: DirectoryManagedCategory
        let revision: Int
        let updatedAt: Date?
    }

    @Published private(set) var published: [String: PublishedCategory] = [:]
    @Published private(set) var isEditor = false
    @Published private(set) var loadError: String?

    private let db = Firestore.firestore()
    private var contentListener: ListenerRegistration?
    private var accessListener: ListenerRegistration?
    private var observedUserID: String?
    private var isOwner = false

    var canEdit: Bool { isOwner || isEditor }
    var categories: [DirectoryCategory] {
        allManagedCategories.compactMap(\.visibleCategory)
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

    func category(_ id: String) -> DirectoryManagedCategory? {
        allManagedCategories.first { $0.id == id }
    }

    func revision(_ id: String) -> Int { published[id]?.revision ?? 0 }

    func publicationDate(_ id: String) -> String {
        guard let date = published[id]?.updatedAt else {
            return DirectoryGuideCatalog.checkedOn(for: id)
        }
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
        let owner = user?.globalRole.authorizationRole == .owner &&
            (user?.blockState == .active || user?.blockState == .warned)
        guard observedUserID != uid || isOwner != owner else { return }
        observedUserID = uid
        isOwner = owner
        isEditor = false
        accessListener?.remove()
        accessListener = nil
        guard let uid, !owner else { return }
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
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        self.loadError = error.localizedDescription
                        return
                    }
                    self.loadError = nil
                    guard let snapshot else { return }
                    var decoded: [String: PublishedCategory] = [:]
                    for document in snapshot.documents {
                        guard let data = document.data()["payload"] as? String,
                              let revision = document.data()["revision"] as? Int,
                              let raw = data.data(using: .utf8),
                              let content = try? JSONDecoder().decode(DirectoryManagedCategory.self, from: raw),
                              content.id == document.documentID else { continue }
                        decoded[content.id] = PublishedCategory(
                            content: content, revision: revision,
                            updatedAt: (document.data()["updatedAt"] as? Timestamp)?.dateValue()
                        )
                    }
                    self.published = decoded
                }
            }
    }

    func save(_ category: DirectoryManagedCategory, expectedRevision: Int, actorID: String) async throws {
        guard canEdit, observedUserID == actorID else { throw AppError.permissionDenied }
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
    }

    private func categories(in placement: DirectoryManagedCategory.Placement) -> [DirectoryCategory] {
        allManagedCategories.filter { $0.placement == placement }.compactMap(\.visibleCategory)
    }

    private static func placementOrder(_ value: DirectoryManagedCategory.Placement) -> Int {
        switch value {
        case .start: 0
        case .life: 1
        case .support: 2
        }
    }
}
