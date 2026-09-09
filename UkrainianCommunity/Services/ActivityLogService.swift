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

struct ActivityLogItem: Identifiable, Equatable, Sendable {
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
    func clearActivityLog(userID: String) async throws
}

extension ActivityLogRepository {
    func clearActivityLog(userID: String) async throws {}
    func deleteActivity(id: String, userID: String) async throws {}
}

struct FirestoreActivityLogRepository: ActivityLogRepository {
    private let database = Firestore.firestore()

    func fetchActivityLog(userID: String, limit: Int = 100) async throws -> [ActivityLogItem] {
        try requireCurrentUser(userID)

        let snapshot = try await activityLogCollection(userID: userID)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments()

        return snapshot.documents.compactMap(makeActivityLogItem(from:))
    }

    func recordActivity(_ item: ActivityLogItem, userID: String) async throws {
        try requireCurrentUser(userID)

        let collection = activityLogCollection(userID: userID)
        try await collection.document(item.id).setData([
            "id": item.id,
            "actionType": item.actionType.rawValue,
            "targetId": item.targetId,
            "targetType": item.targetType.rawValue,
            "title": item.title,
            "subtitle": item.subtitle as Any,
            "imageURL": item.imageURL as Any,
            "createdAt": FieldValue.serverTimestamp()
        ])

        // Do not scan up to 150 records after every interaction. Retention is
        // best-effort maintenance and is sufficient once per account/day.
        if await FirestoreMaintenanceThrottle.shared.shouldRun(key: "activityLog:\(userID)") {
            try? await pruneActivityLog(in: collection)
        }
    }

    func clearActivityLog(userID: String) async throws {
        try requireCurrentUser(userID)
        let collection = activityLogCollection(userID: userID)
        while true {
            let snapshot = try await collection.limit(to: 400).getDocuments()
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
                .getDocuments()
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
    @Published private(set) var items: [ActivityLogItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: AppError?
    @Published private(set) var isClearing = false
    @Published private(set) var deletingIDs = Set<String>()

    private let repository: ActivityLogRepository
    private var hasLoaded = false
    private var loadedUserID: String?
    private var sessionGeneration: UInt = 0
    private var refreshGeneration: UInt = 0

    init(repository: ActivityLogRepository) {
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
    }

    func refresh() async {
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
            let recordingError = await ActivityLogRecorder.reconcilePending(userID: requestedUserID)
            let refreshedItems = try await RefreshRequest.run { [self] in
                try await repository.fetchActivityLog(userID: requestedUserID, limit: 100)
            }
                .sorted { $0.createdAt > $1.createdAt }
            guard generation == refreshGeneration, requestedUserID == loadedUserID else { return }
            items = refreshedItems
            error = recordingError
            hasLoaded = true
        } catch let appError as AppError {
            guard generation == refreshGeneration, requestedUserID == loadedUserID else { return }
            error = appError
            hasLoaded = true
        } catch {
            guard generation == refreshGeneration, requestedUserID == loadedUserID else { return }
            self.error = .unknown
            hasLoaded = true
        }
    }

    @discardableResult
    func clearHistory() async -> Bool {
        guard !isClearing else { return false }
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
            try await repository.clearActivityLog(userID: requestedUserID)
            guard generation == sessionGeneration, requestedUserID == loadedUserID else { return false }
            await ActivityLogRecorder.discardPending(userID: requestedUserID)
            items = []
            error = nil
            return true
        } catch let appError as AppError {
            guard generation == sessionGeneration, requestedUserID == loadedUserID else { return false }
            error = appError
        } catch {
            guard generation == sessionGeneration, requestedUserID == loadedUserID else { return false }
            self.error = .unknown
        }
        return false
    }

    @discardableResult
    func delete(_ item: ActivityLogItem) async -> Bool {
        guard !deletingIDs.contains(item.id) else { return false }
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
            try await repository.deleteActivity(id: item.id, userID: requestedUserID)
            guard generation == sessionGeneration, requestedUserID == loadedUserID else { return false }
            await ActivityLogRecorder.discardPending(id: item.id, userID: requestedUserID)
            items.removeAll { $0.id == item.id }
            error = nil
            return true
        } catch let appError as AppError {
            guard generation == sessionGeneration, requestedUserID == loadedUserID else { return false }
            error = appError
        } catch {
            guard generation == sessionGeneration, requestedUserID == loadedUserID else { return false }
            self.error = .unknown
        }
        return false
    }
}

private actor PendingActivityLogStore {
    static let shared = PendingActivityLogStore()

    private var itemsByUserID: [String: [String: ActivityLogItem]] = [:]

    func enqueue(_ item: ActivityLogItem, userID: String) {
        itemsByUserID[userID, default: [:]][item.id] = item
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
    }

    func removeAll(userID: String) {
        itemsByUserID[userID] = nil
    }
}

enum ActivityLogRecorder {
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

    private static func record(_ item: ActivityLogItem) {
        // Hosted unit tests exercise mock interactions, not account activity writes.
        // Keep this before the task so the live repository is never initialized.
        guard !AppTestHost.isUnitTesting else { return }
        guard let userID = Auth.auth().currentUser?.uid else { return }
        Task {
            await PendingActivityLogStore.shared.enqueue(item, userID: userID)
            guard Auth.auth().currentUser?.uid == userID else { return }
            do {
                try await repository.recordActivity(item, userID: userID)
                await PendingActivityLogStore.shared.remove(id: item.id, userID: userID)
            } catch {
                // The stable item ID remains queued for an explicit History refresh.
            }
        }
    }

    static func reconcilePending(userID: String) async -> AppError? {
        guard Auth.auth().currentUser?.uid == userID else { return .permissionDenied }
        var lastError: AppError?
        for item in await PendingActivityLogStore.shared.items(userID: userID) {
            guard Auth.auth().currentUser?.uid == userID else { return .permissionDenied }
            do {
                try await repository.recordActivity(item, userID: userID)
                await PendingActivityLogStore.shared.remove(id: item.id, userID: userID)
            } catch let appError as AppError {
                lastError = appError
            } catch {
                lastError = .unknown
            }
        }
        return lastError
    }

    static func discardPending(id: String, userID: String) async {
        await PendingActivityLogStore.shared.remove(id: id, userID: userID)
    }

    static func discardPending(userID: String) async {
        await PendingActivityLogStore.shared.removeAll(userID: userID)
    }

    private static func eventScheduleSubtitle(for event: Event) -> String? {
        let dateText = LocalizationStore.dateString(from: event.startDate, dateStyle: .medium, timeStyle: .none)
        guard !event.city.isEmpty else { return dateText }
        return "\(dateText) · \(event.city)"
    }
}
