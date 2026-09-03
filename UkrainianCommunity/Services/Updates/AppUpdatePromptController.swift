import Combine
import Foundation

@MainActor
final class AppUpdatePromptController: ObservableObject {
    @Published private(set) var update: AppStoreUpdate?
    @Published var isPresented = false
    private let client: any AppUpdateChecking
    private var checkedThisOpening = false
    private var generation: UInt = 0
    private var skipAppStoreReturn = false
    private var requestTask: Task<Void, Never>?

    init(client: any AppUpdateChecking) { self.client = client }

    func checkIfNeeded() async {
        if let requestTask { await requestTask.value; return }
        guard !checkedThisOpening else { return }
        checkedThisOpening = true
        if skipAppStoreReturn {
            skipAppStoreReturn = false
            return
        }
        let requestedGeneration = generation
        // Owned by the opening, not by a temporary sheet's SwiftUI task.
        let task = Task { [weak self, client] in
            do {
                let result = try await client.availableUpdate()
                guard !Task.isCancelled, self?.generation == requestedGeneration else { return }
                self?.update = result
            } catch {
                // Offline/server failures must never block the application.
            }
        }
        requestTask = task
        await task.value
        if generation == requestedGeneration { requestTask = nil }
    }

    func enteredBackground() {
        generation &+= 1
        requestTask?.cancel()
        requestTask = nil
        isPresented = false
        update = nil
        checkedThisOpening = false
    }

    func later() {
        isPresented = false
        update = nil
    }

    func openStore() -> URL {
        later()
        // Returning from the App Store is part of this action, not a new nag.
        skipAppStoreReturn = true
        return AppStoreUpdate.storeURL
    }

    func storeCouldNotOpen() {
        skipAppStoreReturn = false
        // Retry only on the next opening; never trap the user in an alert loop.
    }

    deinit { requestTask?.cancel() }
}
