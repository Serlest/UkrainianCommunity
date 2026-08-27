import Foundation

private struct MockOwnerContentDraftListener: AppRealtimeListener {
    func cancel() {}
}

struct MockOwnerContentDraftRepository: OwnerContentDraftRepository {
    func fetchDrafts(userID: String, limit: Int) async throws -> [OwnerContentDraft] { [] }

    func listenDrafts(
        userID: String,
        limit: Int,
        onChange: @escaping @MainActor ([OwnerContentDraft]) -> Void,
        onError: @escaping @MainActor (AppError) -> Void
    ) -> AppRealtimeListener {
        Task { @MainActor in onChange([]) }
        return MockOwnerContentDraftListener()
    }

    func markCompleted(userID: String, draftID: String) async throws {}
    func archive(userID: String, draftID: String) async throws {}
    func delete(userID: String, draftID: String) async throws {}
}
