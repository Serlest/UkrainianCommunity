import Foundation
@testable import UkrainianCommunity

/// Controlled time for deliberately suspended SDK responses, not a longer timeout.
@MainActor
final class ManualRefreshDeadline {
    private var waiters: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var durations: [Duration] = []

    func sleep(for duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                waiters[id] = continuation
                durations.append(duration)
                let started = startWaiters
                startWaiters.removeAll()
                started.forEach { $0.resume() }
            }
        } onCancel: {
            Task { @MainActor in self.waiters.removeValue(forKey: id)?.resume(throwing: CancellationError()) }
        }
    }

    func waitUntilScheduled() async {
        guard durations.isEmpty else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func expire() {
        let pending = Array(waiters.values)
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }

    func cancel() {
        let pending = Array(waiters.values)
        waiters.removeAll()
        pending.forEach { $0.resume(throwing: CancellationError()) }
    }
}
