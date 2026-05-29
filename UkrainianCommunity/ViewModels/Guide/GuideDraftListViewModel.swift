import Combine
import Foundation

@MainActor
final class GuideDraftListViewModel: ObservableObject {
    @Published private(set) var drafts: [GuideArticle]
    @Published private(set) var error: AppError?
    @Published private(set) var isLoading: Bool
    @Published private(set) var archiveError: AppError?
    @Published private(set) var archivingArticleIDs = Set<String>()

    private let repository: GuideRepository
    private var hasLoaded = false
    private var loadTask: Task<Void, Never>?

    init(repository: GuideRepository) {
        self.repository = repository
        drafts = []
        isLoading = false
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await startLoad(force: false)
    }

    func reload() {
        Task {
            await refresh()
        }
    }

    func refresh() async {
        await startLoad(force: true)
    }

    func isArchiving(_ article: GuideArticle) -> Bool {
        archivingArticleIDs.contains(article.id)
    }

    @discardableResult
    func archive(_ article: GuideArticle, currentUserId: String?) async -> Bool {
        guard let currentUserId else {
            archiveError = .permissionDenied
            return false
        }

        archivingArticleIDs.insert(article.id)
        defer {
            archivingArticleIDs.remove(article.id)
        }

        do {
            try await repository.archiveGuideArticle(id: article.id, editorId: currentUserId)
            drafts.removeAll { $0.id == article.id }
            archiveError = nil
            return true
        } catch is CancellationError {
            return false
        } catch let appError as AppError {
            guard !Task.isCancelled else { return false }
            archiveError = appError
            return false
        } catch {
            guard !Task.isCancelled else { return false }
            archiveError = .unknown
            return false
        }
    }

    private func startLoad(force: Bool) async {
        guard force || !hasLoaded else { return }

        if let loadTask {
            await loadTask.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoad()
        }
        loadTask = task
        await task.value
        loadTask = nil
    }

    private func performLoad() async {
        isLoading = true
        defer { isLoading = false }

        do {
            drafts = try await repository.fetchDraftGuideArticles()
            error = nil
            hasLoaded = true
        } catch is CancellationError {
        } catch let appError as AppError {
            guard !Task.isCancelled else { return }
            error = appError
        } catch {
            guard !Task.isCancelled else { return }
            self.error = .unknown
        }
    }
}
