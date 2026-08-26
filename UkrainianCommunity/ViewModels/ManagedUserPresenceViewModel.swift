import Combine
import Foundation

@MainActor
final class ManagedUserPresenceViewModel: ObservableObject {
    @Published private(set) var snapshot: ManagedUserPresenceSnapshot?
    @Published private(set) var failed = false
    @Published private(set) var isRefreshing = false

    private let load: (String) async throws -> ManagedUserPresenceSnapshot
    private var key: String?
    private var revision = 0
    private var request: Task<Void, Never>?

    init(load: @escaping (String) async throws -> ManagedUserPresenceSnapshot = UserPresenceAPI.load) {
        self.load = load
    }

    func refresh(userID: String, actor: AppUser?) async {
        let allowed = PermissionService.canManageUsers(user: actor)
        let nextKey = allowed ? "\(actor?.id ?? "")|\(actor?.globalRole.authorizationRole.rawValue ?? "")|\(userID)" : nil
        if key != nextKey {
            cancelPending()
            key = nextKey
            snapshot = nil
            failed = false
        }
        guard allowed else { return }
        // Polling and a manual pull share the same real request and both await it.
        if let request { await request.value; return }
        let current = revision
        isRefreshing = true
        let task = Task { [self, load] in
            defer {
                if current == revision { request = nil; isRefreshing = false }
            }
            do {
                let value = try await RefreshRequest.run { try await load(userID) }
                guard current == revision, key == nextKey else { return }
                snapshot = value
                failed = false
            } catch is CancellationError {
                return
            } catch {
                guard current == revision, key == nextKey else { return }
                failed = true
            }
        }
        request = task
        await task.value
    }

    func cancelPending() {
        revision &+= 1
        request?.cancel()
        request = nil
        isRefreshing = false
    }
}
