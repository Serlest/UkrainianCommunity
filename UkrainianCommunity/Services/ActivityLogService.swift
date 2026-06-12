import Foundation
import Combine
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

enum ActivityLogTargetType: String, CaseIterable, Codable, Identifiable {
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

enum ActivityLogActionType: String, CaseIterable, Codable, Identifiable {
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
            return AppTheme.accentPrimary
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

struct ActivityLogItem: Identifiable, Equatable {
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
    func fetchActivityLog(limit: Int) async throws -> [ActivityLogItem]
    func recordActivity(_ item: ActivityLogItem) async throws
}

struct FirestoreActivityLogRepository: ActivityLogRepository {
    private let database = Firestore.firestore()

    func fetchActivityLog(limit: Int = 100) async throws -> [ActivityLogItem] {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw AppError.permissionDenied
        }

        let snapshot = try await activityLogCollection(userID: uid)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments()

        return snapshot.documents.compactMap(makeActivityLogItem(from:))
    }

    func recordActivity(_ item: ActivityLogItem) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let collection = activityLogCollection(userID: uid)
        try await collection.document(item.id).setData([
            "id": item.id,
            "actionType": item.actionType.rawValue,
            "targetId": item.targetId,
            "targetType": item.targetType.rawValue,
            "title": item.title,
            "subtitle": item.subtitle as Any,
            "imageURL": item.imageURL as Any,
            "createdAt": Timestamp(date: item.createdAt)
        ])

        try await pruneActivityLog(in: collection)
    }

    private func activityLogCollection(userID: String) -> CollectionReference {
        database.collection("users").document(userID).collection("activityLog")
    }

    private func pruneActivityLog(in collection: CollectionReference) async throws {
        let snapshot = try await collection
            .order(by: "createdAt", descending: true)
            .limit(to: 150)
            .getDocuments()

        let staleDocuments = snapshot.documents.dropFirst(100)
        guard !staleDocuments.isEmpty else { return }

        let batch = database.batch()
        staleDocuments.forEach { batch.deleteDocument($0.reference) }
        try await batch.commit()
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

    private let repository: ActivityLogRepository
    private var hasLoaded = false
    private var loadedUserID: String?

    init(repository: ActivityLogRepository) {
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
            items = try await repository.fetchActivityLog(limit: 100)
                .sorted { $0.createdAt > $1.createdAt }
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
            title: organization.name,
            subtitle: organization.shortDescription.isEmpty ? organization.city : organization.shortDescription,
            imageURL: organization.logoURL ?? organization.imageURL ?? organization.coverURL,
            createdAt: Date()
        ))
    }

    private static func record(_ item: ActivityLogItem) {
        Task {
            try? await repository.recordActivity(item)
        }
    }

    private static func eventScheduleSubtitle(for event: Event) -> String? {
        let dateText = LocalizationStore.dateString(from: event.startDate, dateStyle: .medium, timeStyle: .none)
        guard !event.city.isEmpty else { return dateText }
        return "\(dateText) · \(event.city)"
    }
}
