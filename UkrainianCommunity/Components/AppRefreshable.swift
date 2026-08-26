import Combine
import SwiftUI

/// Own the refresh independently of SwiftUI's transient RefreshAction task.
/// Publishing data can cancel that task while the screen is still visible.
@MainActor
final class AppRefreshCoordinator: ObservableObject {
    private var task: Task<Void, Never>?
    private var revision = 0

    func perform(_ action: @escaping @MainActor () async -> Void) async {
        if let task { await task.value; return }
        let current = revision
        let operation = Task { await action() }
        task = operation
        await operation.value
        if current == revision { task = nil }
    }

    func cancel() {
        revision &+= 1
        task?.cancel()
        task = nil
    }
}

private struct AppRefreshableModifier: ViewModifier {
    let action: @MainActor () async -> Void
    @StateObject private var coordinator = AppRefreshCoordinator()

    func body(content: Content) -> some View {
        content
            .refreshable { await coordinator.perform(action) }
            .onDisappear { coordinator.cancel() }
    }
}

extension View {
    /// Uses the native control and awaits completion; no detached UI writes or cosmetic delay.
    func appRefreshable(action: @escaping @MainActor () async -> Void) -> some View {
        modifier(AppRefreshableModifier(action: action))
    }
}
