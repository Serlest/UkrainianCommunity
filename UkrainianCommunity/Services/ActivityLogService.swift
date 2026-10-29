import Foundation
import Combine
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

enum ActivityLogTargetType: String, CaseIterable, Codable, Identifiable, Sendable {
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

enum ActivityLogActionType: String, CaseIterable, Codable, Identifiable, Sendable {
    case registeredForEvent
    case canceledEventRegistration
    case followedOrganization
    case unfollowedOrganization
    case savedNews
    case unsavedNews
    case savedEvent
    case unsavedEvent
    case savedOrganization
    case unsavedOrganization

    var id: String { rawValue }

    var title: String {
        switch self {
        case .registeredForEvent:
            return AppStrings.ActivityLog.registeredForEvent
        case .canceledEventRegistration:
            return AppStrings.ActivityLog.canceledEventRegistration
        case .followedOrganization:
            return AppStrings.ActivityLog.followedOrganization
        case .unfollowedOrganization:
            return AppStrings.ActivityLog.unfollowedOrganization
        case .savedNews:
            return AppStrings.ActivityLog.savedNews
        case .unsavedNews:
            return AppStrings.ActivityLog.unsavedNews
        case .savedEvent:
            return AppStrings.ActivityLog.savedEvent
        case .unsavedEvent:
            return AppStrings.ActivityLog.unsavedEvent
        case .savedOrganization:
            return AppStrings.ActivityLog.savedOrganization
        case .unsavedOrganization:
            return AppStrings.ActivityLog.unsavedOrganization
        }
    }

    var systemImage: String {
        switch self {
        case .registeredForEvent:
            return "checkmark.circle"
        case .canceledEventRegistration:
            return "xmark.circle"
        case .followedOrganization:
            return "person.2.badge.plus"
        case .unfollowedOrganization:
            return "person.2.badge.minus"
        case .savedNews, .savedEvent, .savedOrganization:
            return "bookmark.fill"
        case .unsavedNews, .unsavedEvent, .unsavedOrganization:
            return "bookmark.slash"
        }
    }

    var tint: Color {
        switch self {
        case .registeredForEvent, .followedOrganization, .savedNews, .savedEvent, .savedOrganization:
            return AppTheme.accentPrimaryForeground
        case .canceledEventRegistration, .unfollowedOrganization, .unsavedNews, .unsavedEvent, .unsavedOrganization:
            return AppTheme.textSecondary
        }
    }

    var isSavedAction: Bool {
        switch self {
        case .savedNews, .unsavedNews, .savedEvent, .unsavedEvent, .savedOrganization, .unsavedOrganization:
            return true
        case .registeredForEvent, .canceledEventRegistration, .followedOrganization, .unfollowedOrganization:
            return false
        }
    }
}

struct ActivityLogItem: Identifiable, Equatable, Codable, Sendable {
    let id: String
    let actionType: ActivityLogActionType
    let targetId: String
    let targetType: ActivityLogTargetType
    let title: String
    let subtitle: String?
    let imageURL: String?
    let createdAt: Date
}

protocol ActivityLogRepository {
    func fetchActivityLog(userID: String, limit: Int) async throws -> [ActivityLogItem]
    func recordActivity(_ item: ActivityLogItem, userID: String) async throws
    func deleteActivity(id: String, userID: String) async throws
    func clearActivityLog(userID: String, through: Date) async throws
}

struct FirestoreActivityLogRepository: ActivityLogRepository {
    private let database = Firestore.firestore()

    func fetchActivityLog(userID: String, limit: Int = 100) async throws -> [ActivityLogItem] {
        try requireCurrentUser(userID)

        let snapshot = try await activityLogCollection(userID: userID)
            .order(by: "createdAt", descending: true)
            .limit(to: min(max(limit, 1), ActivityLogViewModel.historyLimit))
            .getDocuments(source: .server)

        return snapshot.documents.compactMap(makeActivityLogItem(from:))
    }

    func recordActivity(_ item: ActivityLogItem, userID: String) async throws {
        try requireCurrentUser(userID)

        let collection = activityLogCollection(userID: userID)
        let reference = collection.document(item.id)
        // Activity entries are immutable. A lost acknowledgement must not turn
        // an already committed entry into a forbidden update on retry.
        _ = try await database.runTransaction { transaction, errorPointer in
            do {
                let existing = try transaction.getDocument(reference)
                if existing.exists {
                    guard existing.data()?["actionType"] as? String == item.actionType.rawValue,
                          existing.data()?["targetId"] as? String == item.targetId,
                          existing.data()?["targetType"] as? String == item.targetType.rawValue else {
                        throw AppError.validationFailed
                    }
                    return nil
                }
                transaction.setData([
                    "id": item.id,
                    "actionType": item.actionType.rawValue,
                    "targetId": item.targetId,
                    "targetType": item.targetType.rawValue,
                    "title": item.title,
                    "subtitle": item.subtitle as Any,
                    "imageURL": item.imageURL as Any,
                    // Preserve when the action happened, including delayed delivery.
                    "createdAt": Timestamp(date: item.createdAt)
                ], forDocument: reference)
            } catch { errorPointer?.pointee = error as NSError }
            return nil
        }

        // Do not scan up to 150 records after every interaction. Retention is
        // best-effort maintenance and is sufficient once per account/day.
        if await FirestoreMaintenanceThrottle.shared.shouldRun(key: "activityLog:\(userID)") {
            try? await pruneActivityLog(in: collection)
        }
    }

    func clearActivityLog(userID: String, through: Date) async throws {
        try requireCurrentUser(userID)
        let collection = activityLogCollection(userID: userID)
        while true {
            let snapshot = try await collection.whereField("createdAt", isLessThanOrEqualTo: Timestamp(date: through))
                .limit(to: 400).getDocuments(source: .server)
            guard !snapshot.documents.isEmpty else { return }
            let batch = database.batch()
            snapshot.documents.forEach { batch.deleteDocument($0.reference) }
            try await batch.commit()
            try requireCurrentUser(userID)
        }
    }

    func deleteActivity(id: String, userID: String) async throws {
        try requireCurrentUser(userID)
        try await activityLogCollection(userID: userID).document(id).delete()
    }

    private func activityLogCollection(userID: String) -> CollectionReference {
        database.collection("users").document(userID).collection("activityLog")
    }

    private func requireCurrentUser(_ userID: String) throws {
        guard Auth.auth().currentUser?.uid == userID else {
            throw AppError.permissionDenied
        }
    }

    private func pruneActivityLog(in collection: CollectionReference) async throws {
        while true {
            let snapshot = try await collection
                .order(by: "createdAt", descending: true)
                .limit(to: 400)
                .getDocuments(source: .server)
            let staleDocuments = Array(snapshot.documents.dropFirst(100))
            guard !staleDocuments.isEmpty else { return }

            let batch = database.batch()
            staleDocuments.forEach { batch.deleteDocument($0.reference) }
            try await batch.commit()
        }
    }

    private func makeActivityLogItem(from document: QueryDocumentSnapshot) -> ActivityLogItem? {
        let data = document.data()
        guard let id = data["id"] as? String,
              let actionTypeRawValue = data["actionType"] as? String,
              let actionType = ActivityLogActionType(rawValue: actionTypeRawValue),
              let targetId = data["targetId"] as? String,
              let targetTypeRawValue = data["targetType"] as? String,
              let targetType = ActivityLogTargetType(rawValue: targetTypeRawValue),
              let title = data["title"] as? String,
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() else {
            return nil
        }

        return ActivityLogItem(
            id: id,
            actionType: actionType,
            targetId: targetId,
            targetType: targetType,
            title: title,
            subtitle: data["subtitle"] as? String,
            imageURL: data["imageURL"] as? String,
            createdAt: createdAt
        )
    }
}

@MainActor
final class ActivityLogViewModel: ObservableObject {
    nonisolated static let historyLimit = 100
    @Published private(set) var items: [ActivityLogItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: AppError?
    @Published private(set) var isClearing = false
    @Published private(set) var deletingIDs = Set<String>()

    private let repository: ActivityLogRepository
    private let synchronizePending: (String) async -> AppError?
    private var revision: UInt = 0
    private var localUpdates: [String: (item: ActivityLogItem, revision: UInt)] = [:]
    private var clearedThrough: Date?
    private var deletedIDs = Set<String>()
    var isMutating: Bool { isClearing || !deletingIDs.isEmpty }
    @Published private(set) var hasLoaded = false
    private var isSynchronizingPending = false
    private var loadedUserID: String?
    private var sessionGeneration: UInt = 0
    private var refreshGeneration: UInt = 0

    init(repository: ActivityLogRepository, synchronizePending: @escaping (String) async -> AppError? = ActivityLogRecorder.reconcilePending) {
        self.repository = repository
        self.synchronizePending = synchronizePending
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
        await refresh()
    }

    func resetForAuthChange() {
        sessionGeneration &+= 1
        refreshGeneration &+= 1
        items = []
        isLoading = false
        error = nil
        isClearing = false
        deletingIDs = []
        hasLoaded = false
        loadedUserID = nil
        localUpdates = [:]
        isSynchronizingPending = false
        revision = 0
        clearedThrough = nil
        deletedIDs = []
    }

    func refresh() async {
        guard !isLoading, !isMutating else { return }
        let baseline = revision
        guard let requestedUserID = loadedUserID ?? Auth.auth().currentUser?.uid else {
            resetForAuthChange()
            return
        }
        refreshGeneration &+= 1
        let generation = refreshGeneration
        isLoading = true
        defer {
            if generation == refreshGeneration, requestedUserID == loadedUserID {
                isLoading = false
            }
        }

        do {
            let refreshedItems = try await RefreshRequest.run { [self] in
                try await repository.fetchActivityLog(userID: requestedUserID, limit: Self.historyLimit)
            }
                .sorted { $0.createdAt > $1.createdAt }
            guard generation == refreshGeneration, requestedUserID == loadedUserID else { return }
            var merged = Dictionary(refreshedItems.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            for update in localUpdates.values where update.revision > baseline { merged[update.item.id] = update.item }
            items = bounded(Array(merged.values))
            localUpdates = [:]
            error = nil
            hasLoaded = true
            // The read is ready. Pending write acknowledgements must not hold
            // this screen behind a spinner (or delay its first read).
            isLoading = false
            await synchronizePendingIfNeeded(userID: requestedUserID, generation: generation)
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

    private func synchronizePendingIfNeeded(userID: String, generation: UInt) async {
        guard !isSynchronizingPending else { return }
        let session = sessionGeneration
        isSynchronizingPending = true
        defer { if session == sessionGeneration { isSynchronizingPending = false } }
        let recordingError = await synchronizePending(userID)
        guard generation == refreshGeneration, session == sessionGeneration, userID == loadedUserID else { return }
        if let recordingError { error = recordingError }
    }

    func applyRecorded(_ item: ActivityLogItem, userID: String) {
        guard userID == loadedUserID, !deletedIDs.contains(item.id),
              clearedThrough.map({ item.createdAt > $0 }) ?? true else { return }
        revision &+= 1
        if isLoading { localUpdates[item.id] = (item, revision) }
        items = bounded(items.filter { $0.id != item.id } + [item])
    }

    private func bounded(_ records: [ActivityLogItem]) -> [ActivityLogItem] {
        Array(records.sorted { $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt > $1.createdAt }.prefix(Self.historyLimit))
    }

    @discardableResult
    func clearHistory() async -> Bool {
        guard !isLoading, !isMutating else { return false }
        let cutoff = Date()
        guard let requestedUserID = loadedUserID else { return false }
        let generation = sessionGeneration
        refreshGeneration &+= 1
        isLoading = false
        isClearing = true
        defer {
            if generation == sessionGeneration, requestedUserID == loadedUserID {
                isClearing = false
            }
        }
        do {
            try await ActivityLogWriteQueue.shared.run(userID: requestedUserID) { [repository] in
                try await repository.clearActivityLog(userID: requestedUserID, through: cutoff)
                await ActivityLogRecorder.discardPending(userID: requestedUserID, through: cutoff)
            }
            guard generation == sessionGeneration, requestedUserID == loadedUserID else { return false }
            clearedThrough = cutoff
            items.removeAll { $0.createdAt <= cutoff }
            error = nil
            return true
        } catch let appError as AppError {
            guard generation == sessionGeneration, requestedUserID == loadedUserID else { return false }
            error = appError
        } catch {
            guard generation == sessionGeneration, requestedUserID == loadedUserID else { return false }
            self.error = FirebaseReadErrorMapper.map(error)
        }
        return false
    }

    @discardableResult
    func delete(_ item: ActivityLogItem) async -> Bool {
        guard !isLoading, !isMutating else { return false }
        guard let requestedUserID = loadedUserID else { return false }
        let generation = sessionGeneration
        refreshGeneration &+= 1
        isLoading = false
        deletingIDs.insert(item.id)
        defer {
            if generation == sessionGeneration, requestedUserID == loadedUserID {
                deletingIDs.remove(item.id)
            }
        }
        do {
            try await ActivityLogWriteQueue.shared.run(userID: requestedUserID) { [repository] in
                try await repository.deleteActivity(id: item.id, userID: requestedUserID)
                await ActivityLogRecorder.discardPending(id: item.id, userID: requestedUserID)
            }
            guard generation == sessionGeneration, requestedUserID == loadedUserID else { return false }
            deletedIDs.insert(item.id)
            items.removeAll { $0.id == item.id }
            error = nil
            return true
        } catch let appError as AppError {
            guard generation == sessionGeneration, requestedUserID == loadedUserID else { return false }
            error = appError
        } catch {
            guard generation == sessionGeneration, requestedUserID == loadedUserID else { return false }
            self.error = FirebaseReadErrorMapper.map(error)
        }
        return false
    }
}

actor PendingActivityLogStore {
    static let shared = PendingActivityLogStore()

    private var clearedThrough: [String: Date] = [:]
    private var removedIDs: [String: Set<String>] = [:]
    private var itemsByUserID: [String: [String: ActivityLogItem]] = [:]
    private let defaults: UserDefaults
    private let storageKey = "uac.pendingActivityLog.v1"

    init(suiteName: String? = nil) {
        let defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let restored = try? JSONDecoder().decode([String: [String: ActivityLogItem]].self, from: data) {
            itemsByUserID = restored
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(itemsByUserID) else { return }
        defaults.set(data, forKey: storageKey)
    }

    func enqueue(_ item: ActivityLogItem, userID: String) {
        guard !(removedIDs[userID]?.contains(item.id) ?? false),
              clearedThrough[userID].map({ item.createdAt > $0 }) ?? true else { return }
        itemsByUserID[userID, default: [:]][item.id] = item
        // A failed delivery must survive an app restart; bound it to the same
        // latest-100 contract as the displayed/server history.
        let latest = itemsByUserID[userID]!.values.sorted { $0.createdAt > $1.createdAt }.prefix(100)
        itemsByUserID[userID] = Dictionary(latest.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        persist()
    }

    func items(userID: String) -> [ActivityLogItem] {
        guard let items = itemsByUserID[userID] else { return [] }
        return items.values.sorted { $0.createdAt < $1.createdAt }
    }

    func remove(id: String, userID: String) {
        itemsByUserID[userID]?[id] = nil
        if itemsByUserID[userID]?.isEmpty == true {
            itemsByUserID[userID] = nil
        }
        persist()
    }

    func discard(id: String, userID: String) {
        removedIDs[userID, default: []].insert(id)
        remove(id: id, userID: userID)
    }

    func removeAll(userID: String, through: Date) {
        clearedThrough[userID] = through
        itemsByUserID[userID] = itemsByUserID[userID]?.filter { $0.value.createdAt > through }
        persist()
    }
}

@MainActor
final class ActivityLogWriteQueue {
    static let shared = ActivityLogWriteQueue()
    private var tails: [String: (id: UUID, completion: Task<Void, Never>)] = [:]

    func run(userID: String, operation: @escaping @MainActor () async throws -> Void) async throws {
        let previous = tails[userID]?.completion
        let id = UUID()
        let task = Task { @MainActor in
            await previous?.value
            try await operation()
        }
        tails[userID] = (id, Task { @MainActor in _ = try? await task.value })
        defer { if tails[userID]?.id == id { tails[userID] = nil } }
        try await task.value
    }
}

struct ActivityLogRecordingEvent {
    let item: ActivityLogItem
    let userID: String
}

enum ActivityLogRecorder {
    static let didRecord = PassthroughSubject<ActivityLogRecordingEvent, Never>()
    private static let repository: ActivityLogRepository = FirestoreActivityLogRepository()

    static func recordEvent(_ event: Event, actionType: ActivityLogActionType) {
        record(ActivityLogItem(
            id: UUID().uuidString,
            actionType: actionType,
            targetId: event.id,
            targetType: .event,
            title: event.title,
            subtitle: event.summary.isEmpty ? eventScheduleSubtitle(for: event) : event.summary,
            imageURL: event.imageURL,
            createdAt: Date()
        ))
    }

    static func recordNews(_ post: NewsPost, actionType: ActivityLogActionType) {
        record(ActivityLogItem(
            id: UUID().uuidString,
            actionType: actionType,
            targetId: post.id,
            targetType: .news,
            title: post.title,
            subtitle: post.subtitle.isEmpty ? nil : post.subtitle,
            imageURL: post.imageURL,
            createdAt: Date()
        ))
    }

    static func recordOrganization(_ organization: Organization, actionType: ActivityLogActionType) {
        record(ActivityLogItem(
            id: UUID().uuidString,
            actionType: actionType,
            targetId: organization.id,
            targetType: .organization,
            title: organization.localizedName,
            subtitle: organization.localizedShortDescription.isEmpty ? organization.city : organization.localizedShortDescription,
            imageURL: organization.logoURL ?? organization.imageURL ?? organization.coverURL,
            createdAt: Date()
        ))
    }

    static func record(_ item: ActivityLogItem) {
        // Hosted unit tests exercise mock interactions, not account activity writes.
        // Keep this before the task so the live repository is never initialized.
        guard !AppTestHost.isUnitTesting else { return }
        guard let userID = Auth.auth().currentUser?.uid else { return }
        record(item, userID: userID)
    }

    static func record(_ item: ActivityLogItem, userID: String) {
        guard !AppTestHost.isUnitTesting, Auth.auth().currentUser?.uid == userID else { return }
        Task {
            await PendingActivityLogStore.shared.enqueue(item, userID: userID)
            guard Auth.auth().currentUser?.uid == userID else { return }
            do {
                try await ActivityLogWriteQueue.shared.run(userID: userID) {
                    guard await PendingActivityLogStore.shared.items(userID: userID).contains(where: { $0.id == item.id }) else { return }
                    try await repository.recordActivity(item, userID: userID)
                    await PendingActivityLogStore.shared.remove(id: item.id, userID: userID)
                    didRecord.send(ActivityLogRecordingEvent(item: item, userID: userID))
                }
            } catch {
                // Retry the same immutable entry after a transient failure.
            }
        }
    }

    static func reconcilePending(userID: String) async -> AppError? {
        guard Auth.auth().currentUser?.uid == userID else { return .permissionDenied }
        var lastError: AppError?
        do {
            try await ActivityLogWriteQueue.shared.run(userID: userID) {
                for item in await PendingActivityLogStore.shared.items(userID: userID) {
                    do {
                        try await repository.recordActivity(item, userID: userID)
                        await PendingActivityLogStore.shared.remove(id: item.id, userID: userID)
                        didRecord.send(ActivityLogRecordingEvent(item: item, userID: userID))
                    } catch {
                        // Keep the queue intact and retry later; an offline first
                        // write must not trigger up to 99 more sequential failures.
                        lastError = FirebaseReadErrorMapper.map(error)
                        break
                    }
                }
            }
        } catch { lastError = FirebaseReadErrorMapper.map(error) }
        return lastError
    }

    static func discardPending(id: String, userID: String) async {
        await PendingActivityLogStore.shared.discard(id: id, userID: userID)
    }

    static func discardPending(userID: String, through: Date) async {
        await PendingActivityLogStore.shared.removeAll(userID: userID, through: through)
    }

    private static func eventScheduleSubtitle(for event: Event) -> String? {
        let dateText = LocalizationStore.dateString(from: event.startDate, dateStyle: .medium, timeStyle: .none)
        guard !event.city.isEmpty else { return dateText }
        return "\(dateText) · \(event.city)"
    }
}

#if DEBUG
@MainActor
final class UITestActivityLogRepository: ActivityLogRepository {
    private var items: [ActivityLogItem] = {
        let post = MockContentBuilder.newsPosts()[0]
        let event = MockContentBuilder.events()[0]
        let org = MockContentBuilder.organizations()[0]
        return [
            ActivityLogItem(id: "activity-news", actionType: .savedNews, targetId: post.id, targetType: .news,
                title: post.title, subtitle: post.subtitle, imageURL: nil, createdAt: Date()),
            ActivityLogItem(id: "activity-event", actionType: .registeredForEvent, targetId: event.id, targetType: .event,
                title: event.title, subtitle: event.summary, imageURL: nil, createdAt: Date().addingTimeInterval(-60)),
            ActivityLogItem(id: "activity-org", actionType: .unfollowedOrganization, targetId: org.id, targetType: .organization,
                title: org.localizedName, subtitle: org.city, imageURL: nil, createdAt: Date().addingTimeInterval(-120))
        ]
    }()
    func fetchActivityLog(userID: String, limit: Int) async throws -> [ActivityLogItem] {
        if try await MockRepositoryStore.shared.personalPageIsEmpty("activityHistory") { return [] }
        return Array(items.prefix(limit))
    }
    func recordActivity(_ item: ActivityLogItem, userID: String) async throws {}
    func deleteActivity(id: String, userID: String) async throws { items.removeAll { $0.id == id } }
    func clearActivityLog(userID: String, through: Date) async throws { items.removeAll { $0.createdAt <= through } }
}
#endif
