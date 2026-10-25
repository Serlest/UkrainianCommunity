import Combine
import FirebaseFirestore

struct ManagedUserAuditPage {
    let items: [ManagedUserAuditItem]
    let cursor: QueryDocumentSnapshot?
    let hasMore: Bool
}

@MainActor enum ManagedUserAuditReader {
    static func page(userID: String, cursor: QueryDocumentSnapshot?) async throws -> ManagedUserAuditPage {
        var query: Query = Firestore.firestore().collection("auditLogs")
            .whereField("targetUserId", isEqualTo: userID)
            .order(by: "createdAt", descending: true).limit(to: 21)
        if let cursor { query = query.start(afterDocument: cursor) }
        let snapshot = try await query.getDocuments(source: .server)
        let documents = Array(snapshot.documents.prefix(20))
        let items = documents.map { document in
            let data = document.data()
            return ManagedUserAuditItem(id: document.documentID, actionType: data["actionType"] as? String ?? "unknown",
                reason: data["reason"] as? String ?? "", performedBy: data["performedBy"] as? String ?? "",
                previousValue: data["previousValue"] as? [String: Any] ?? [:],
                newValue: data["newValue"] as? [String: Any] ?? [:],
                createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? .distantPast)
        }
        return .init(items: items, cursor: documents.last, hasMore: snapshot.documents.count > 20)
    }
}

@MainActor final class ManagedUserAuditStore: ObservableObject {
    typealias Read = (String, QueryDocumentSnapshot?) async throws -> ManagedUserAuditPage
    @Published private(set) var items: [ManagedUserAuditItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var failed = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var hasMore = false
    private var cursor: QueryDocumentSnapshot?
    private let read: Read
    private var key: String?
    private var token: String?
    private var generation = 0
    private var request: Task<Void, Never>?
    private var requestMore = false
    private var failedMore = false

    init(read: @escaping Read = ManagedUserAuditReader.page) { self.read = read }

    func ensure(userID: String, actor: AppUser?, refreshToken: String) async {
        let next = PermissionService.canManageUsers(user: actor) ? "\(actor!.id)|\(actor!.globalRole.authorizationRole.rawValue)|\(userID)" : nil
        if key != next {
            generation += 1; request?.cancel(); request = nil
            key = next; token = nil; items = []; cursor = nil
            isLoading = false; failed = false; hasLoaded = false; hasMore = false
        }
        guard next != nil else { return }
        guard !hasLoaded || token != refreshToken else { return }
        // A refresh token changing during a read must start a replacement read,
        // rather than being lost behind the old request's isLoading flag.
        if token != refreshToken, request != nil {
            generation += 1; request?.cancel(); request = nil; isLoading = false
        }
        token = refreshToken
        await load(userID: userID, more: false)
    }

    func retry(userID: String) async { await load(userID: userID, more: failedMore) }
    func more(userID: String) async { await load(userID: userID, more: true) }

    private func load(userID: String, more: Bool) async {
        guard key != nil else { return }
        if let request { if requestMore == more { await request.value }; return }
        guard !more || hasMore else { return }
        let revision = generation, after = more ? cursor : nil
        isLoading = true; failed = false; requestMore = more
        let task = Task { [self] in
            defer { if revision == generation { request = nil; isLoading = false } }
            do {
                let page = try await RefreshRequest.run { [read] in try await read(userID, after) }
                guard revision == generation, !Task.isCancelled else { return }
                var ids = Set(more ? items.map(\.id) : [])
                let fresh = page.items.filter { ids.insert($0.id).inserted }
                items = more ? items + fresh : fresh
                cursor = page.cursor; hasMore = page.hasMore; hasLoaded = true
            } catch is CancellationError { return }
            catch { guard revision == generation, !Task.isCancelled else { return }; failed = true; failedMore = more }
        }
        request = task
        await task.value
    }
}
