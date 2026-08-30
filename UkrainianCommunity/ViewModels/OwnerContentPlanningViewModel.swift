import Combine
import Foundation

@MainActor
final class OwnerContentPlanningViewModel: ObservableObject {
    @Published private(set) var drafts: [OwnerContentDraft] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let repository: OwnerContentDraftRepository
    private var listener: AppRealtimeListener?
    private var activeUserID: String?

    init(repository: OwnerContentDraftRepository) {
        self.repository = repository
    }

    deinit {
        MainActor.assumeIsolated {
            listener?.cancel()
        }
    }

    func start(userID: String) {
        guard activeUserID != userID || listener == nil else { return }
        listener?.cancel()
        activeUserID = userID
        isLoading = drafts.isEmpty
        errorMessage = nil
        listener = repository.listenDrafts(
            userID: userID,
            limit: 100,
            onChange: { [weak self] drafts in
                self?.drafts = drafts
                self?.isLoading = false
                self?.errorMessage = nil
            },
            onError: { [weak self] _ in
                self?.isLoading = false
                self?.errorMessage = AppStrings.ContentPlanning.loadFailed
            }
        )
    }

    func refresh() async {
        guard let activeUserID else { return }
        isLoading = drafts.isEmpty
        do {
            drafts = try await repository.fetchDrafts(userID: activeUserID, limit: 100)
            errorMessage = nil
        } catch {
            errorMessage = AppStrings.ContentPlanning.loadFailed
        }
        isLoading = false
    }

    func markCompleted(_ draft: OwnerContentDraft) async {
        guard let activeUserID else { return }
        do {
            try await repository.markCompleted(userID: activeUserID, draftID: draft.id)
            drafts.removeAll { $0.id == draft.id }
        } catch {
            errorMessage = AppStrings.ContentPlanning.updateFailed
        }
    }

    func finishPublishing(
        _ draft: OwnerContentDraft,
        publication: ContentPlanningPublicationResult
    ) async {
        guard let activeUserID else { return }
        do {
            if publication.isScheduled {
                try await repository.markScheduled(
                    userID: activeUserID,
                    draftID: draft.id,
                    publication: publication
                )
            } else {
                try await repository.markCompleted(userID: activeUserID, draftID: draft.id)
                drafts.removeAll { $0.id == draft.id }
            }
            errorMessage = nil
        } catch {
            errorMessage = AppStrings.ContentPlanning.updateFailed
        }
    }

    func archive(_ draft: OwnerContentDraft) async {
        guard let activeUserID else { return }
        do {
            try await repository.archive(userID: activeUserID, draftID: draft.id)
            drafts.removeAll { $0.id == draft.id }
        } catch {
            errorMessage = AppStrings.ContentPlanning.updateFailed
        }
    }

    func delete(_ draft: OwnerContentDraft) async {
        guard let activeUserID else { return }
        do {
            try await repository.delete(userID: activeUserID, draftID: draft.id)
            drafts.removeAll { $0.id == draft.id }
        } catch {
            errorMessage = AppStrings.ContentPlanning.deleteFailed
        }
    }
}
