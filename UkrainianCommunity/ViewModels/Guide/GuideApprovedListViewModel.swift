import Combine
import Foundation

@MainActor
final class GuideApprovedListViewModel: ObservableObject {
    @Published private(set) var articles: [GuideArticle]
    @Published private(set) var error: AppError?
    @Published private(set) var isLoading: Bool

    private let repository: GuideRepository
    private var hasLoaded = false
    private var loadTask: Task<Void, Never>?

    init(repository: GuideRepository) {
        self.repository = repository
        articles = []
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
            articles = try await repository.fetchApprovedGuideArticles()
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
