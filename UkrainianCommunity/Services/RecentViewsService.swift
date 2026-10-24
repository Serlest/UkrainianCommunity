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
    let organizationID: String?
    let viewedAt: Date

    init(
        itemId: String,
        itemType: RecentViewItemType,
        title: String,
        subtitle: String?,
        imageURL: String?,
        organizationID: String? = nil,
        viewedAt: Date
    ) {
        self.itemId = itemId
        self.itemType = itemType
        self.title = title
        self.subtitle = subtitle
        self.imageURL = imageURL
        self.organizationID = organizationID
        self.viewedAt = viewedAt
    }

    var id: String { Self.documentID(itemId: itemId, itemType: itemType) }

    static func documentID(itemId: String, itemType: RecentViewItemType) -> String {
        "\(itemType.rawValue)_\(itemId)"
    }
}

protocol RecentViewsRepository {
    func fetchRecentViews(userID: String, limit: Int) async throws -> [RecentViewItem]
    func recordRecentView(_ item: RecentViewItem, userID: String) async throws
    func deleteRecentView(id: String, userID: String, through: Date) async throws
    func clearRecentViews(userID: String, through: Date) async throws
}

struct FirestoreRecentViewsRepository: RecentViewsRepository {
    private let database = Firestore.firestore()

    func fetchRecentViews(userID: String, limit: Int = 30) async throws -> [RecentViewItem] {
        guard Auth.auth().currentUser?.uid == userID else { throw AppError.permissionDenied }
        let uid = userID

        let snapshot = try await recentViewsCollection(userID: uid)
            .order(by: "viewedAt", descending: true)
            .limit(to: min(max(limit, 1), RecentViewsViewModel.historyLimit))
            .getDocuments(source: .server)

        return snapshot.documents.compactMap(makeRecentViewItem(from:))
    }

    func recordRecentView(_ item: RecentViewItem, userID: String) async throws {
        guard Auth.auth().currentUser?.uid == userID else { throw AppError.permissionDenied }
        let uid = userID

        let collection = recentViewsCollection(userID: uid)
        try await collection.document(item.id).setData([
            "itemId": item.itemId,
            "itemType": item.itemType.rawValue,
            "title": item.title,
            "subtitle": item.subtitle as Any,
            "imageURL": item.imageURL as Any,
            "organizationID": item.organizationID as Any,
            "viewedAt": Timestamp(date: item.viewedAt)
        ], merge: true)

        // Retention is maintenance, not part of the user-visible write. Running
        // this query after every detail open multiplied one action into as many
        // as 60 document reads. Once-per-day best-effort maintenance keeps the
        // collection bounded without delaying or overcharging every view.
        if await FirestoreMaintenanceThrottle.shared.shouldRun(key: "recentViews:\(uid)") {
            try? await pruneRecentViews(in: collection)
        }
    }

    func clearRecentViews(userID: String, through: Date) async throws {
        guard Auth.auth().currentUser?.uid == userID else { throw AppError.permissionDenied }
        let uid = userID
        // Delete in bounded batches, including history beyond the visible window.
        // New views made after confirmation remain in the history.
        let query = recentViewsCollection(userID: uid)
            .whereField("viewedAt", isLessThanOrEqualTo: Timestamp(date: through))
        while true {
            let snapshot = try await query.limit(to: 400).getDocuments(source: .server)
            guard !snapshot.documents.isEmpty else { return }
            try await deleteUnchanged(snapshot.documents)
        }
    }

    func deleteRecentView(id: String, userID: String, through: Date) async throws {
        guard Auth.auth().currentUser?.uid == userID else { throw AppError.permissionDenied }
        let uid = userID
        let reference = recentViewsCollection(userID: uid).document(id)
        _ = try await database.runTransaction { transaction, errorPointer in
            do {
                let document = try transaction.getDocument(reference)
                if let date = (document.data()?["viewedAt"] as? Timestamp)?.dateValue(), date > through { return nil }
                transaction.deleteDocument(reference)
            } catch { errorPointer?.pointee = error as NSError }
            return nil
        }
    }

    private func recentViewsCollection(userID: String) -> CollectionReference {
        database.collection("users").document(userID).collection("recentViews")
    }

    private func pruneRecentViews(in collection: CollectionReference) async throws {
        let newest = try await collection.order(by: "viewedAt", descending: true)
            .limit(to: RecentViewsViewModel.historyLimit).getDocuments(source: .server)
        guard newest.documents.count == RecentViewsViewModel.historyLimit,
              let boundary = newest.documents.last else { return }
        // Keep the same boundary while deleting every older page, not just 30 rows.
        let staleQuery = collection.order(by: "viewedAt", descending: true).start(afterDocument: boundary)
        while true {
            let page = try await staleQuery.limit(to: 400).getDocuments(source: .server)
            guard !page.documents.isEmpty else { return }
            try await deleteUnchanged(page.documents)
        }
    }

    private func deleteUnchanged(_ documents: [QueryDocumentSnapshot]) async throws {
        _ = try await database.runTransaction { transaction, errorPointer in
            do {
                // Read all documents before writing; a concurrent new view wins.
                let current = try documents.map { try transaction.getDocument($0.reference) }
                for (original, latest) in zip(documents, current) {
                    if original.data()["viewedAt"] as? Timestamp == latest.data()?["viewedAt"] as? Timestamp {
                        transaction.deleteDocument(original.reference)
                    }
                }
            } catch { errorPointer?.pointee = error as NSError }
            return nil
        }
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
            organizationID: data["organizationID"] as? String,
            viewedAt: viewedAt
        )
    }
}

@MainActor
final class RecentViewsViewModel: ObservableObject {
    nonisolated static let historyLimit = 30
    @Published private(set) var items: [RecentViewItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: AppError?
    @Published private(set) var isClearing = false
    @Published private(set) var deletingIDs = Set<String>()

    private let repository: RecentViewsRepository
    private var hasLoaded = false
    private var loadedUserID: String?
    private var refreshGeneration: UInt = 0
    private var recordRevision: UInt = 0
    private var recordedUpdates: [String: (item: RecentViewItem, revision: UInt)] = [:]
    private var clearedThrough: Date?
    private var deletedThrough: [String: Date] = [:]
    var isMutating: Bool { isClearing || !deletingIDs.isEmpty }

    init(repository: RecentViewsRepository) {
        self.repository = repository
    }

    func loadIfNeeded() async {
        if loadedUserID == nil {
            loadedUserID = Auth.auth().currentUser?.uid
        }
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
    }

    func refresh(userID: String) async {
        if loadedUserID != userID {
            resetForAuthChange()
            loadedUserID = userID
        }
        await refresh()
    }

    func resetForAuthChange() {
        refreshGeneration &+= 1
        items = []
        isLoading = false
        error = nil
        isClearing = false
        deletingIDs = []
        hasLoaded = false
        loadedUserID = nil
        recordedUpdates = [:]
        recordRevision = 0
        clearedThrough = nil
        deletedThrough = [:]
    }

    func refresh() async {
        guard !isLoading, !isMutating, let requestedUserID = loadedUserID else { return }
        let baselineRevision = recordRevision
        refreshGeneration &+= 1
        let generation = refreshGeneration
        isLoading = true
        defer {
            if generation == refreshGeneration {
                isLoading = false
            }
        }

        do {
            let refreshedItems = try await RefreshRequest.run { [self] in
                try await repository.fetchRecentViews(userID: requestedUserID, limit: Self.historyLimit)
            }
                .sorted { $0.viewedAt > $1.viewedAt }
            guard generation == refreshGeneration, requestedUserID == loadedUserID else { return }
            var merged = Dictionary(refreshedItems.map { ($0.id, $0) }, uniquingKeysWith: { _, newest in newest })
            for update in recordedUpdates.values where update.revision > baselineRevision {
                merged[update.item.id] = update.item
            }
            items = bounded(Array(merged.values))
            recordedUpdates = [:]
            error = nil
            hasLoaded = true
        } catch let appError as AppError {
            guard generation == refreshGeneration, requestedUserID == loadedUserID else { return }
            error = appError
            hasLoaded = true
        } catch {
            guard generation == refreshGeneration, requestedUserID == loadedUserID else { return }
            self.error = FirebaseReadErrorMapper.map(error)
            hasLoaded = true
        }
    }

    func applyRecordedView(_ item: RecentViewItem, userID: String) {
        guard loadedUserID == userID,
              clearedThrough.map({ item.viewedAt > $0 }) ?? true,
              deletedThrough[item.id].map({ item.viewedAt > $0 }) ?? true else { return }
        recordRevision &+= 1
        if isLoading { recordedUpdates[item.id] = (item, recordRevision) }
        items = bounded(items.filter { $0.id != item.id } + [item])
        error = nil
        hasLoaded = true
    }

    private func bounded(_ values: [RecentViewItem]) -> [RecentViewItem] {
        Array(values.sorted {
            $0.viewedAt == $1.viewedAt ? $0.id < $1.id : $0.viewedAt > $1.viewedAt
        }.prefix(Self.historyLimit))
    }

    @discardableResult
    func clearHistory() async -> Bool {
        guard !isLoading, !isMutating, let requestedUserID = loadedUserID else { return false }
        let cutoff = Date()
        let generation = refreshGeneration
        isClearing = true
        defer {
            if generation == refreshGeneration, requestedUserID == loadedUserID {
                isClearing = false
            }
        }
        do {
            try await repository.clearRecentViews(userID: requestedUserID, through: cutoff)
            guard generation == refreshGeneration, requestedUserID == loadedUserID else { return false }
            clearedThrough = cutoff
            items.removeAll { $0.viewedAt <= cutoff }
            error = nil
            return true
        } catch let appError as AppError {
            guard generation == refreshGeneration, requestedUserID == loadedUserID else { return false }
            error = appError
        } catch {
            guard generation == refreshGeneration, requestedUserID == loadedUserID else { return false }
            self.error = FirebaseReadErrorMapper.map(error)
        }
        return false
    }

    @discardableResult
    func delete(_ item: RecentViewItem) async -> Bool {
        guard !isLoading, !isMutating, let requestedUserID = loadedUserID else { return false }
        let cutoff = Date()
        let generation = refreshGeneration
        deletingIDs.insert(item.id)
        defer {
            if generation == refreshGeneration, requestedUserID == loadedUserID {
                deletingIDs.remove(item.id)
            }
        }
        do {
            try await repository.deleteRecentView(id: item.id, userID: requestedUserID, through: cutoff)
            guard generation == refreshGeneration, requestedUserID == loadedUserID else { return false }
            deletedThrough[item.id] = cutoff
            items.removeAll { $0.id == item.id && $0.viewedAt <= cutoff }
            error = nil
            return true
        } catch let appError as AppError {
            guard generation == refreshGeneration, requestedUserID == loadedUserID else { return false }
            error = appError
        } catch {
            guard generation == refreshGeneration, requestedUserID == loadedUserID else { return false }
            self.error = FirebaseReadErrorMapper.map(error)
        }
        return false
    }
}

struct RecentViewRecordingEvent {
    let item: RecentViewItem
    let userID: String
}

@MainActor
enum RecentViewRecorder {
    private static let repository: RecentViewsRepository = FirestoreRecentViewsRepository()
    static let didRecord = PassthroughSubject<RecentViewRecordingEvent, Never>()

    static func recordNews(_ post: NewsPost) {
        record(RecentViewItem(
            itemId: post.id,
            itemType: .news,
            title: post.title,
            subtitle: post.subtitle.isEmpty ? nil : post.subtitle,
            imageURL: post.imageURL,
            organizationID: post.source.organizationId,
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
            organizationID: event.source.organizationId,
            viewedAt: Date()
        ))
    }

    static func recordOrganization(_ organization: Organization) {
        record(RecentViewItem(
            itemId: organization.id,
            itemType: .organization,
            title: organization.localizedName,
            subtitle: organization.localizedShortDescription.isEmpty ? organization.city : organization.localizedShortDescription,
            imageURL: organization.logoURL ?? organization.imageURL ?? organization.coverURL,
            organizationID: organization.id,
            viewedAt: Date()
        ))
    }

    private static func record(_ item: RecentViewItem) {
        guard let userID = Auth.auth().currentUser?.uid else { return }
        Task {
            guard Auth.auth().currentUser?.uid == userID else { return }
            do {
                try await repository.recordRecentView(item, userID: userID)
                guard Auth.auth().currentUser?.uid == userID else { return }
                didRecord.send(RecentViewRecordingEvent(item: item, userID: userID))
            } catch {
                // Recent views remain best-effort and must not interrupt detail navigation.
            }
        }
    }

    private static func eventScheduleSubtitle(for event: Event) -> String? {
        let dateText = LocalizationStore.dateString(from: event.startDate, dateStyle: .medium, timeStyle: .none)
        guard !event.city.isEmpty else { return dateText }
        return "\(dateText) · \(event.city)"
    }
}

#if DEBUG
/// Isolated history fixture; enabled only by the UI test launch contract.
@MainActor
final class UITestRecentViewsRepository: RecentViewsRepository {
    private var items: [RecentViewItem] = {
        let post = MockContentBuilder.newsPosts()[0]
        let event = MockContentBuilder.events()[0]
        let org = MockContentBuilder.organizations()[0]
        return [
            RecentViewItem(itemId: post.id, itemType: .news, title: post.title, subtitle: post.subtitle, imageURL: nil, viewedAt: Date()),
            RecentViewItem(itemId: event.id, itemType: .event, title: event.title, subtitle: event.summary, imageURL: nil, viewedAt: Date().addingTimeInterval(-60)),
            RecentViewItem(itemId: org.id, itemType: .organization, title: org.localizedName, subtitle: org.city, imageURL: nil, viewedAt: Date().addingTimeInterval(-120))
        ]
    }()
    func fetchRecentViews(userID: String, limit: Int) async throws -> [RecentViewItem] {
        if try await MockRepositoryStore.shared.personalPageIsEmpty("recentViews") { return [] }
        return Array(items.prefix(limit))
    }
    func recordRecentView(_ item: RecentViewItem, userID: String) async throws {}
    func deleteRecentView(id: String, userID: String, through: Date) async throws {
        items.removeAll { $0.id == id && $0.viewedAt <= through }
    }
    func clearRecentViews(userID: String, through: Date) async throws { items.removeAll { $0.viewedAt <= through } }
}
#endif
