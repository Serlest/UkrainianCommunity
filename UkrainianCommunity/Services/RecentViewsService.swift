import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

enum RecentViewItemType: String, CaseIterable, Codable, Identifiable {
    case news
    case event
    case organization

    var id: String { rawValue }

    var title: String {
        switch self {
        case .news:
            return AppStrings.News.title
        case .event:
            return AppStrings.Events.title
        case .organization:
            return AppStrings.Tabs.organizations
        }
    }

    var systemImage: String {
        switch self {
        case .news:
            return "newspaper"
        case .event:
            return "calendar"
        case .organization:
            return "building.2"
        }
    }
}

struct RecentViewItem: Identifiable, Equatable {
    let itemId: String
    let itemType: RecentViewItemType
    let title: String
    let subtitle: String?
    let imageURL: String?
    let viewedAt: Date

    var id: String { Self.documentID(itemId: itemId, itemType: itemType) }

    static func documentID(itemId: String, itemType: RecentViewItemType) -> String {
        "\(itemType.rawValue)_\(itemId)"
    }
}

protocol RecentViewsRepository {
    func fetchRecentViews(limit: Int) async throws -> [RecentViewItem]
    func recordRecentView(_ item: RecentViewItem) async throws
    func deleteRecentView(id: String) async throws
    func clearRecentViews() async throws
}

extension RecentViewsRepository {
    func clearRecentViews() async throws {}
    func deleteRecentView(id: String) async throws {}
}

struct FirestoreRecentViewsRepository: RecentViewsRepository {
    private let database = Firestore.firestore()

    func fetchRecentViews(limit: Int = 30) async throws -> [RecentViewItem] {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AppError.permissionDenied
        }

        let snapshot = try await recentViewsCollection(userID: uid)
            .order(by: "viewedAt", descending: true)
            .limit(to: limit)
            .getDocuments()

        return snapshot.documents.compactMap(makeRecentViewItem(from:))
    }

    func recordRecentView(_ item: RecentViewItem) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let collection = recentViewsCollection(userID: uid)
        try await collection.document(item.id).setData([
            "itemId": item.itemId,
            "itemType": item.itemType.rawValue,
            "title": item.title,
            "subtitle": item.subtitle as Any,
            "imageURL": item.imageURL as Any,
            "viewedAt": Timestamp(date: item.viewedAt)
        ], merge: true)

        try await pruneRecentViews(in: collection)
    }

    func clearRecentViews() async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw AppError.permissionDenied }
        let snapshot = try await recentViewsCollection(userID: uid).getDocuments()
        guard !snapshot.documents.isEmpty else { return }
        let batch = database.batch()
        snapshot.documents.forEach { batch.deleteDocument($0.reference) }
        try await batch.commit()
    }

    func deleteRecentView(id: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { throw AppError.permissionDenied }
        try await recentViewsCollection(userID: uid).document(id).delete()
    }

    private func recentViewsCollection(userID: String) -> CollectionReference {
        database.collection("users").document(userID).collection("recentViews")
    }

    private func pruneRecentViews(in collection: CollectionReference) async throws {
        let snapshot = try await collection
            .order(by: "viewedAt", descending: true)
            .limit(to: 60)
            .getDocuments()

        let staleDocuments = snapshot.documents.dropFirst(30)
        guard !staleDocuments.isEmpty else { return }

        let batch = database.batch()
        staleDocuments.forEach { batch.deleteDocument($0.reference) }
        try await batch.commit()
    }

    private func makeRecentViewItem(from document: QueryDocumentSnapshot) -> RecentViewItem? {
        let data = document.data()
        guard let itemId = data["itemId"] as? String,
              let itemTypeRawValue = data["itemType"] as? String,
              let itemType = RecentViewItemType(rawValue: itemTypeRawValue),
              let title = data["title"] as? String,
              let viewedAt = (data["viewedAt"] as? Timestamp)?.dateValue() else {
            return nil
        }

        return RecentViewItem(
            itemId: itemId,
            itemType: itemType,
            title: title,
            subtitle: data["subtitle"] as? String,
            imageURL: data["imageURL"] as? String,
            viewedAt: viewedAt
        )
    }
}

@MainActor
final class RecentViewsViewModel: ObservableObject {
    @Published private(set) var items: [RecentViewItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: AppError?
    @Published private(set) var isClearing = false
    @Published private(set) var deletingIDs = Set<String>()

    private let repository: RecentViewsRepository
    private var hasLoaded = false
    private var loadedUserID: String?

    init(repository: RecentViewsRepository) {
        self.repository = repository
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await refresh()
    }

    func loadIfNeeded(userID: String) async {
        if loadedUserID != userID {
            resetForAuthChange()
            loadedUserID = userID
        }
        guard !hasLoaded else { return }
        await refresh()
        loadedUserID = userID
    }

    func resetForAuthChange() {
        items = []
        isLoading = false
        error = nil
        hasLoaded = false
        loadedUserID = nil
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            items = try await repository.fetchRecentViews(limit: 30)
                .sorted { $0.viewedAt > $1.viewedAt }
            error = nil
            hasLoaded = true
            loadedUserID = Auth.auth().currentUser?.uid
        } catch let appError as AppError {
            error = appError
            hasLoaded = true
        } catch {
            self.error = .unknown
            hasLoaded = true
        }
    }

    @discardableResult
    func clearHistory() async -> Bool {
        guard !isClearing else { return false }
        isClearing = true
        defer { isClearing = false }
        do {
            try await repository.clearRecentViews()
            items = []
            error = nil
            return true
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
        return false
    }

    @discardableResult
    func delete(_ item: RecentViewItem) async -> Bool {
        guard !deletingIDs.contains(item.id) else { return false }
        deletingIDs.insert(item.id)
        defer { deletingIDs.remove(item.id) }
        do {
            try await repository.deleteRecentView(id: item.id)
            items.removeAll { $0.id == item.id }
            error = nil
            return true
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
        return false
    }
}

enum RecentViewRecorder {
    private static let repository: RecentViewsRepository = FirestoreRecentViewsRepository()

    static func recordNews(_ post: NewsPost) {
        record(RecentViewItem(
            itemId: post.id,
            itemType: .news,
            title: post.title,
            subtitle: post.subtitle.isEmpty ? nil : post.subtitle,
            imageURL: post.imageURL,
            viewedAt: Date()
        ))
    }

    static func recordEvent(_ event: Event) {
        record(RecentViewItem(
            itemId: event.id,
            itemType: .event,
            title: event.title,
            subtitle: event.summary.isEmpty ? eventScheduleSubtitle(for: event) : event.summary,
            imageURL: event.imageURL,
            viewedAt: Date()
        ))
    }

    static func recordOrganization(_ organization: Organization) {
        record(RecentViewItem(
            itemId: organization.id,
            itemType: .organization,
            title: organization.name,
            subtitle: organization.shortDescription.isEmpty ? organization.city : organization.shortDescription,
            imageURL: organization.logoURL ?? organization.imageURL ?? organization.coverURL,
            viewedAt: Date()
        ))
    }

    private static func record(_ item: RecentViewItem) {
        Task {
            try? await repository.recordRecentView(item)
        }
    }

    private static func eventScheduleSubtitle(for event: Event) -> String? {
        let dateText = LocalizationStore.dateString(from: event.startDate, dateStyle: .medium, timeStyle: .none)
        guard !event.city.isEmpty else { return dateText }
        return "\(dateText) · \(event.city)"
    }
}
