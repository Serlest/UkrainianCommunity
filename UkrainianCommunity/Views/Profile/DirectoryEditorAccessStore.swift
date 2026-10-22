import Combine
import FirebaseFunctions
import Foundation

struct DirectoryEditorGrant: Codable, Equatable, Identifiable {
    let id: String
    let enabled: Bool
    let revision: String?
    let grantedAt: Double?
}
struct DirectoryEditorGrantPage: Decodable {
    let grants: [DirectoryEditorGrant]
    var cursor: String? = nil
}
nonisolated private struct DirectoryAccessRequest: Encodable {
    let action: String
    let principalId: String
    var cursor: String? = nil
    var userIds: [String]? = nil
    var userId: String? = nil
    var enabled: Bool? = nil
    var operationId: String? = nil
    var expectedRevision: String? = nil
    // Explicit null distinguishes a reviewed absent grant from a missing review.
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(action, forKey: .action); try values.encode(principalId, forKey: .principalId)
        try values.encodeIfPresent(cursor, forKey: .cursor); try values.encodeIfPresent(userIds, forKey: .userIds)
        try values.encodeIfPresent(userId, forKey: .userId); try values.encodeIfPresent(enabled, forKey: .enabled)
        try values.encodeIfPresent(operationId, forKey: .operationId)
        if action == "set" { try values.encode(expectedRevision, forKey: .expectedRevision) }
    }
    private enum CodingKeys: String, CodingKey { case action, principalId, cursor, userIds, userId, enabled, operationId, expectedRevision }
}

@MainActor
struct DirectoryEditorAccessAPI {
    // Retain the small injected interface for deterministic legacy store fixtures.
    var enabledIDs: () async throws -> Set<String>
    var user: (String) async throws -> AppUser?
    var setAccess: (Bool, String, String) async throws -> Void
    var page: ((String, String?) async throws -> DirectoryEditorGrantPage)? = nil
    var inspect: ((String, [String]) async throws -> [DirectoryEditorGrant])? = nil
    var mutate: ((String, DirectoryEditorGrant, Bool, String) async throws -> DirectoryEditorGrant)? = nil
    var profiles: (([String]) async throws -> [AppUser])? = nil

    private static func call<T: Decodable>(_ request: DirectoryAccessRequest, as: T.Type) async throws -> T {
        var callable: Callable<DirectoryAccessRequest, T> = Functions.functions(region: "europe-west3").httpsCallable("manageDirectoryEditorAccess")
        callable.timeoutInterval = 30
        return try await callable.call(request)
    }
    static let live = Self(
        enabledIDs: { [] }, user: UserManagementReads.live.user,
        setAccess: { _, _, _ in throw AppError.network },
        page: { actor, cursor in try await call(.init(action: "list", principalId: actor, cursor: cursor), as: DirectoryEditorGrantPage.self) },
        inspect: { actor, ids in try await call(.init(action: "inspect", principalId: actor, userIds: ids), as: DirectoryEditorGrantPage.self).grants },
        mutate: { actor, previous, enabled, operation in
            try await call(.init(action: "set", principalId: actor, userId: previous.id, enabled: enabled, operationId: operation, expectedRevision: previous.revision), as: DirectoryEditorGrant.self)
        }, profiles: UserManagementReads.fetchUsers(ids:)
    )
}

@MainActor
final class DirectoryEditorAccessStore: ObservableObject {
    @Published private(set) var editorIDs = Set<String>()
    @Published private(set) var grants: [String: DirectoryEditorGrant] = [:]
    @Published private(set) var profiles: [String: AppUser] = [:]
    @Published private(set) var failedProfileIDs = Set<String>()
    @Published private(set) var missingProfileIDs = Set<String>()
    @Published private(set) var busyIDs = Set<String>()
    @Published private(set) var isLoading = true
    @Published private(set) var isLoadingMore = false
    @Published private(set) var canLoadMore = false
    @Published private(set) var loadFailed = false
    @Published var errorMessage: String?
    private let api: DirectoryEditorAccessAPI
    private var actorID: String?
    private var cursor: String?
    private var generation = UUID()
    private var session = UUID()
    private var operations: [String: String] = [:]

    init(api: DirectoryEditorAccessAPI? = nil) { self.api = api ?? .live }
    func reset() {
        generation = UUID(); session = UUID(); actorID = nil; cursor = nil; operations = [:]
        editorIDs = []; grants = [:]; profiles = [:]; busyIDs = []
        failedProfileIDs = []; missingProfileIDs = []; errorMessage = nil
        isLoading = false; isLoadingMore = false; canLoadMore = false; loadFailed = false
    }
    func load(actorID: String) async {
        if self.actorID != actorID { reset(); self.actorID = actorID }
        generation = UUID()
        await fetchPage(actorID: actorID, more: false)
    }
    func loadMore(actorID: String) async {
        guard canLoadMore, !isLoading, !isLoadingMore else { return }
        await fetchPage(actorID: actorID, more: true)
    }
    private func fetchPage(actorID: String, more: Bool) async {
        guard self.actorID == actorID else { return }
        let token = generation
        if more { isLoadingMore = true } else { isLoading = true }
        loadFailed = false
        defer { if generation == token { isLoading = false; isLoadingMore = false } }
        do {
            let page: DirectoryEditorGrantPage
            if let read = api.page { page = try await read(actorID, more ? cursor : nil) }
            else { page = DirectoryEditorGrantPage(grants: try await api.enabledIDs().map { DirectoryEditorGrant(id: $0, enabled: true, revision: nil, grantedAt: nil) }) }
            guard self.actorID == actorID, generation == token, !Task.isCancelled else { return }
            if !more { editorIDs = []; grants = [:] }
            for grant in page.grants { grants[grant.id] = grant; if grant.enabled { editorIDs.insert(grant.id) } }
            cursor = page.cursor; canLoadMore = page.cursor != nil
            isLoading = false; isLoadingMore = false
            // Rights and revoke controls become available before profile hydration.
            if let batch = api.profiles, !page.grants.isEmpty {
                let ids = page.grants.map(\.id)
                do {
                    let result = try await batch(ids)
                    guard self.actorID == actorID, generation == token, !Task.isCancelled else { return }
                    for user in result { profiles[user.id] = user; failedProfileIDs.remove(user.id); missingProfileIDs.remove(user.id) }
                    for id in Set(ids).subtracting(result.map(\.id)) { profiles[id] = nil; missingProfileIDs.insert(id) }
                } catch {
                    if self.actorID == actorID, generation == token { failedProfileIDs.formUnion(ids) }
                }
            } else {
                for grant in page.grants { await loadProfile(grant.id, actorID: actorID) }
            }
        } catch {
            if self.actorID == actorID, generation == token, !Task.isCancelled { loadFailed = true; errorMessage = error.localizedDescription }
        }
    }
    func inspect(_ ids: [String], actorID: String) async {
        guard self.actorID == actorID, let read = api.inspect, !ids.isEmpty else { return }
        let token = generation
        do {
            var result: [DirectoryEditorGrant] = []
            for start in stride(from: 0, to: ids.count, by: 40) {
                let missing = Array(ids[start..<min(start + 40, ids.count)]).filter { grants[$0] == nil }
                if !missing.isEmpty { result += try await read(actorID, missing) }
            }
            guard self.actorID == actorID, generation == token, !Task.isCancelled else { return }
            for grant in result { grants[grant.id] = grant }
        } catch { if self.actorID == actorID, generation == token, !Task.isCancelled { errorMessage = error.localizedDescription } }
    }
    func loadProfile(_ id: String, actorID: String) async {
        let token = generation
        do {
            let user = try await api.user(id)
            guard self.actorID == actorID, generation == token, editorIDs.contains(id), !Task.isCancelled else { return }
            profiles[id] = user; failedProfileIDs.remove(id)
            if user == nil { missingProfileIDs.insert(id) } else { missingProfileIDs.remove(id) }
        } catch {
            guard self.actorID == actorID, generation == token, editorIDs.contains(id), !Task.isCancelled else { return }
            failedProfileIDs.insert(id)
        }
    }
    func setAccess(_ enabled: Bool, userID: String, knownUser: AppUser? = nil, actorID: String, reviewed: DirectoryEditorGrant? = nil) async {
        guard self.actorID == actorID, !busyIDs.contains(userID) else { return }
        let previous = reviewed ?? grants[userID]
        guard api.mutate == nil || previous != nil else { return }
        let token = generation, requestSession = session
        busyIDs.insert(userID)
        defer { if self.actorID == actorID, session == requestSession { busyIDs.remove(userID) } }
        do {
            if let mutate = api.mutate, let previous {
                let key = [actorID, userID, previous.revision ?? "absent", String(enabled)].joined(separator: "|")
                let operation = operations[key] ?? UUID().uuidString
                operations[key] = operation
                let result = try await mutate(actorID, previous, enabled, operation)
                guard self.actorID == actorID, session == requestSession, !Task.isCancelled else { return }
                if generation != token { await load(actorID: actorID); return }
                // Invalidate in-flight reads so a stale page cannot restore revoked access.
                generation = UUID(); isLoading = false; isLoadingMore = false
                grants[userID] = result
            } else { try await api.setAccess(enabled, userID, actorID) }
            guard self.actorID == actorID, (api.mutate != nil || generation == token), !Task.isCancelled else { return }
            if enabled {
                if let knownUser, knownUser.id == userID { profiles[userID] = knownUser; failedProfileIDs.remove(userID); missingProfileIDs.remove(userID) }
                editorIDs.insert(userID)
                if profiles[userID] == nil { await loadProfile(userID, actorID: actorID) }
            } else { editorIDs.remove(userID); profiles[userID] = nil; failedProfileIDs.remove(userID); missingProfileIDs.remove(userID) }
        } catch {
            if self.actorID == actorID, session == requestSession, !Task.isCancelled {
                if (error as NSError).code == FunctionsErrorCode.aborted.rawValue {
                    await load(actorID: actorID)
                    guard self.actorID == actorID, session == requestSession, !Task.isCancelled else { return }
                    errorMessage = UserDirectoryCopy.changed
                } else { errorMessage = error.localizedDescription }
            }
        }
    }
}
