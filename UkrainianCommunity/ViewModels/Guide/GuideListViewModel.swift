import Combine
import Foundation

nonisolated private let guideRefreshStaleInterval: TimeInterval = 300

@MainActor
final class GuideListViewModel: ObservableObject {
    @Published private(set) var articles: [GuideArticle]
    @Published private(set) var error: AppError?
    @Published private(set) var isLoading: Bool
    @Published var searchText = ""
    @Published var selectedCategory: GuideCategory?
    @Published var selectedContentType: GuideContentType?
    @Published var selectedFederalState: AustrianFederalState?
    @Published var selectedAudience: String?

    private let repository: GuideRepository
    private var loadTask: Task<Void, Never>?
    private var hasLoaded = false
    private var lastLoadedAt: Date?

    var filterState: GuideFilterState {
        GuideFilterState(
            searchText: searchText,
            selectedCategory: selectedCategory,
            selectedContentType: selectedContentType,
            selectedFederalState: selectedFederalState,
            selectedAudience: selectedAudience
        )
    }

    var filteredArticles: [GuideArticle] {
        articles.filter { article in
            matchesSearch(article) && matchesFilters(article)
        }
    }

    var availableContentTypes: [GuideContentType] {
        let contentTypes = Set(articles.compactMap(\.contentType))
        return GuideContentType.allCases.filter { contentTypes.contains($0) }
    }

    var availableAudiences: [String] {
        Array(Set(articles.flatMap { $0.audience ?? [] }))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

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

    func refreshIfStale(maxAge: TimeInterval = guideRefreshStaleInterval) async {
        guard hasLoaded else {
            await loadIfNeeded()
            return
        }

        guard let lastLoadedAt else {
            await refresh()
            return
        }

        guard Date().timeIntervalSince(lastLoadedAt) > maxAge else { return }
        await refresh()
    }

    func clearFilters() {
        searchText = ""
        selectedCategory = nil
        selectedContentType = nil
        selectedFederalState = nil
        selectedAudience = nil
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
        self.loadTask = nil
    }

    private func performLoad() async {
        isLoading = true
        defer { isLoading = false }

        do {
            articles = try await repository.fetchGuideArticles()
            error = nil
            hasLoaded = true
            lastLoadedAt = Date()
        } catch is CancellationError {
        } catch let appError as AppError {
            guard !Task.isCancelled else { return }
            error = appError
        } catch {
            guard !Task.isCancelled else { return }
            self.error = .unknown
        }
    }

    private func matchesSearch(_ article: GuideArticle) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }

        let searchableValues = baseSearchableValues(for: article)
            + (article.audience ?? [])
            + (article.sourceLinks ?? []).flatMap(\.searchableTextValues)
            + (article.contentBlocks ?? []).flatMap(\.searchableTextValues)

        return searchableValues.contains { value in
            value.localizedCaseInsensitiveContains(query)
        }
    }

    private func baseSearchableValues(for article: GuideArticle) -> [String] {
        [
            article.title,
            article.summary,
            article.body,
            article.category.title,
            article.category.rawValue,
            article.contentType?.rawValue,
            article.sourceName,
            article.city
        ].compactMap { value in
            let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedValue?.isEmpty == false ? trimmedValue : nil
        }
    }

    private func matchesFilters(_ article: GuideArticle) -> Bool {
        if let selectedCategory, article.category != selectedCategory {
            return false
        }

        if let selectedContentType, article.contentType != selectedContentType {
            return false
        }

        if let selectedFederalState, !matchesFederalState(article, selectedFederalState: selectedFederalState) {
            return false
        }

        if let selectedAudience, !matchesAudience(article, selectedAudience: selectedAudience) {
            return false
        }

        return true
    }

    private func matchesFederalState(_ article: GuideArticle, selectedFederalState: AustrianFederalState) -> Bool {
        switch article.regionScope {
        case .austria, nil:
            return true
        case .federalState, .city:
            return article.federalState == selectedFederalState
        }
    }

    private func matchesAudience(_ article: GuideArticle, selectedAudience: String) -> Bool {
        article.audience?.contains { audience in
            audience.localizedCaseInsensitiveCompare(selectedAudience) == .orderedSame
        } == true
    }
}

typealias InfoViewModel = GuideListViewModel
