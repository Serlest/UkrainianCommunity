import Combine
import Foundation

@MainActor
final class ManagedUserPresenceViewModel: ObservableObject {
    @Published private(set) var snapshot: ManagedUserPresenceSnapshot?
    @Published private(set) var failed = false
    @Published private(set) var isRefreshing = false

    private let load: (String) async throws -> ManagedUserPresenceSnapshot
    private let readDeadline: RefreshRequest.Deadline
    private let onRequestCoalesced: () -> Void
    private var consecutiveFailures = 0
    var pollingDelay: Duration {
        .seconds(consecutiveFailures == 0 ? 30 : min(180, 30 * (1 << min(consecutiveFailures, 3))))
    }
    private var key: String?
    private var revision = 0
    private var request: Task<Void, Never>?

    init(
        load: @escaping (String) async throws -> ManagedUserPresenceSnapshot = UserPresenceAPI.load,
        readDeadline: @escaping RefreshRequest.Deadline = RefreshRequest.continuousDeadline,
        onRequestCoalesced: @escaping () -> Void = {}
    ) {
        self.load = load
        self.readDeadline = readDeadline
        self.onRequestCoalesced = onRequestCoalesced
    }

    func refresh(userID: String, actor: AppUser?) async {
        let allowed = PermissionService.canManageUsers(user: actor)
        let nextKey = allowed ? "\(actor?.id ?? "")|\(actor?.globalRole.authorizationRole.rawValue ?? "")|\(userID)" : nil
        if key != nextKey {
            cancelPending()
            key = nextKey
            snapshot = nil
            failed = false
            consecutiveFailures = 0
        }
        guard allowed else { return }
        // Polling and a manual pull share the same real request and both await it.
        if let request {
            onRequestCoalesced()
            await request.value
            return
        }
        let current = revision
        isRefreshing = true
        let task = Task { [self, load] in
            defer {
                if current == revision { request = nil; isRefreshing = false }
            }
            do {
                let value = try await RefreshRequest.run(deadline: readDeadline) { try await load(userID) }
                guard current == revision, key == nextKey else { return }
                snapshot = value
                failed = false
                consecutiveFailures = 0
            } catch is CancellationError {
                return
            } catch {
                guard current == revision, key == nextKey else { return }
                failed = true
                consecutiveFailures = min(consecutiveFailures + 1, 3)
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
