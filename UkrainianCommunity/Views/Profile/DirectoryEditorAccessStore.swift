import Combine
import FirebaseFirestore

@MainActor
struct DirectoryEditorAccessAPI {
    var enabledIDs: () async throws -> Set<String>
    var user: (String) async throws -> AppUser?
    var setAccess: (Bool, String, String) async throws -> Void

    static let live = Self(
        enabledIDs: {
            let snapshot = try await Firestore.firestore().collection("directoryEditors").getDocuments(source: .server)
            return Set(snapshot.documents.filter { $0.data()["enabled"] as? Bool == true }.map(\.documentID))
        },
        user: UserManagementReads.live.user,
        setAccess: { enabled, userID, actorID in
            let reference = Firestore.firestore().collection("directoryEditors").document(userID)
            if enabled {
                try await reference.setData([
                    "enabled": true, "grantedBy": actorID, "grantedAt": FieldValue.serverTimestamp()
                ])
            } else {
                try await reference.delete()
            }
            let snapshot = try await reference.getDocument(source: .server)
            guard enabled ? snapshot.data()?["enabled"] as? Bool == true : !snapshot.exists else {
                throw AppError.network
            }
        }
    )
}

/// Keeps grant identity independent of the paginated/searchable candidate list.
@MainActor
final class DirectoryEditorAccessStore: ObservableObject {
    @Published private(set) var editorIDs = Set<String>()
    @Published private(set) var profiles: [String: AppUser] = [:]
    @Published private(set) var failedProfileIDs = Set<String>()
    @Published private(set) var missingProfileIDs = Set<String>()
    @Published private(set) var busyIDs = Set<String>()
    @Published private(set) var isLoading = true
    @Published private(set) var loadFailed = false
    @Published var errorMessage: String?
    private let api: DirectoryEditorAccessAPI
    private var actorID: String?

    init(api: DirectoryEditorAccessAPI? = nil) { self.api = api ?? .live }

    func load(actorID: String) async {
        if self.actorID != actorID {
            self.actorID = actorID
            editorIDs = []; profiles = [:]; busyIDs = []
            failedProfileIDs = []; missingProfileIDs = []; errorMessage = nil
        }
        isLoading = true
        loadFailed = false
        defer { if self.actorID == actorID { isLoading = false } }
        do {
            let ids = try await api.enabledIDs()
            guard self.actorID == actorID, !Task.isCancelled else { return }
            editorIDs = ids
            profiles = profiles.filter { ids.contains($0.key) }
            failedProfileIDs = []; missingProfileIDs = []
            for id in ids { await loadProfile(id, actorID: actorID) }
        } catch {
            if self.actorID == actorID, !Task.isCancelled {
                loadFailed = true
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadProfile(_ id: String, actorID: String) async {
        do {
            let user = try await api.user(id)
            guard self.actorID == actorID, editorIDs.contains(id), !Task.isCancelled else { return }
            profiles[id] = user
            failedProfileIDs.remove(id)
            if user == nil { missingProfileIDs.insert(id) } else { missingProfileIDs.remove(id) }
        } catch {
            guard self.actorID == actorID, editorIDs.contains(id), !Task.isCancelled else { return }
            failedProfileIDs.insert(id)
        }
    }

    func setAccess(_ enabled: Bool, userID: String, knownUser: AppUser? = nil, actorID: String) async {
        guard self.actorID == actorID, !busyIDs.contains(userID) else { return }
        busyIDs.insert(userID)
        defer { if self.actorID == actorID { busyIDs.remove(userID) } }
        do {
            try await api.setAccess(enabled, userID, actorID)
            guard self.actorID == actorID, !Task.isCancelled else { return }
            if enabled {
                if let knownUser, knownUser.id == userID {
                    profiles[userID] = knownUser
                    failedProfileIDs.remove(userID); missingProfileIDs.remove(userID)
                }
                editorIDs.insert(userID)
                if profiles[userID] == nil { await loadProfile(userID, actorID: actorID) }
            } else {
                editorIDs.remove(userID); profiles[userID] = nil
                failedProfileIDs.remove(userID); missingProfileIDs.remove(userID)
            }
        } catch {
            if self.actorID == actorID, !Task.isCancelled { errorMessage = error.localizedDescription }
        }
    }
}
