import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var user: AppUser
    @Published private(set) var highlights: [HomeHighlight]
    @Published private(set) var latestNews: [NewsPost]
    @Published private(set) var isLoading: Bool
    @Published private(set) var error: AppError?
    private let userRepository: UserRepository
    private let newsRepository: NewsRepository
    private let eventRepository: EventRepository
    private let organizationRepository: OrganizationRepository
    private let marketplaceRepository: MarketplaceRepository
    private var loadTask: Task<Void, Never>?
    private var hasLoaded = false

    init(
        userRepository: UserRepository,
        newsRepository: NewsRepository,
        eventRepository: EventRepository,
        organizationRepository: OrganizationRepository,
        marketplaceRepository: MarketplaceRepository
    ) {
        self.userRepository = userRepository
        self.newsRepository = newsRepository
        self.eventRepository = eventRepository
        self.organizationRepository = organizationRepository
        self.marketplaceRepository = marketplaceRepository
        user = .placeholder
        highlights = []
        latestNews = []
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

        loadTask?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoad()
        }
        loadTask = task
        await task.value
    }

    private func performLoad() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let loadedUser = userRepository.fetchCurrentUser()
            async let news = newsRepository.fetchNews()
            async let events = eventRepository.fetchEvents()
            async let organizations = organizationRepository.fetchOrganizations()
            async let marketplaceItems = marketplaceRepository.fetchMarketplaceItems()

            let resolvedUser = try await loadedUser
            let resolvedNews = try await news
            let resolvedEvents = try await events
            let resolvedOrganizations = try await organizations
            let resolvedMarketplaceItems = try await marketplaceItems

            guard !Task.isCancelled else { return }
            user = resolvedUser
            latestNews = Array(resolvedNews.prefix(3))
            highlights = [
                HomeHighlight(id: "news", title: AppStrings.Tabs.news, detail: AppStrings.homeHighlightNews(resolvedNews.count), systemImage: "newspaper.fill"),
                HomeHighlight(id: "events", title: AppStrings.Tabs.events, detail: AppStrings.homeHighlightEvents(resolvedEvents.count), systemImage: "calendar"),
                HomeHighlight(id: "organizations", title: AppStrings.Tabs.organizations, detail: AppStrings.homeHighlightOrganizations(resolvedOrganizations.count), systemImage: "building.2.fill"),
                HomeHighlight(id: "marketplace", title: AppStrings.Tabs.marketplace, detail: AppStrings.homeHighlightMarketplace(resolvedMarketplaceItems.count), systemImage: "basket.fill")
            ]
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

@MainActor
final class NewsViewModel: ObservableObject {
    @Published var posts: [NewsPost]
    @Published private(set) var isLoading: Bool
    @Published private(set) var error: AppError?
    @Published private(set) var contentVersion = 0
    private let repository: NewsRepository
    private var loadTask: Task<Void, Never>?
    private var hasLoaded = false

    init(repository: NewsRepository) {
        self.repository = repository
        posts = []
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

    func toggleLike(for postID: String) {
        guard let index = posts.firstIndex(where: { $0.id == postID }) else { return }
        let shouldLike = posts[index].likeState == .notLiked

        Task {
            do {
                if shouldLike {
                    try await repository.likeNews(id: postID)
                } else {
                    try await repository.unlikeNews(id: postID)
                }

                posts[index].likeState = shouldLike ? .liked : .notLiked
                posts[index].likeCount += shouldLike ? 1 : -1
                error = nil
            } catch let appError as AppError {
                error = appError
            } catch {
                self.error = .unknown
            }
        }
    }

    func post(for postID: String) -> NewsPost? {
        posts.first(where: { $0.id == postID })
    }

    func deleteNews(id: String) async throws {
        do {
            try await repository.deleteNews(id: id)
            posts.removeAll { $0.id == id }
            error = nil
        } catch let appError as AppError {
            error = appError
            throw appError
        } catch {
            self.error = .unknown
            throw AppError.unknown
        }
    }

    private func startLoad(force: Bool) async {
        guard force || !hasLoaded else { return }

        loadTask?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoad()
        }
        loadTask = task
        await task.value
    }

    private func performLoad() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let loadedPosts = try await repository.fetchNews()
            guard !Task.isCancelled else { return }
            posts = loadedPosts
            contentVersion &+= 1
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

@MainActor
final class EventsViewModel: ObservableObject {
    @Published var events: [Event]
    @Published private(set) var isLoading: Bool
    @Published private(set) var error: AppError?
    @Published private(set) var contentVersion = 0
    private let repository: EventRepository
    private var loadTask: Task<Void, Never>?
    private var hasLoaded = false

    init(repository: EventRepository) {
        self.repository = repository
        events = []
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

    func toggleLike(for eventID: String) {
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }
        let shouldLike = events[index].likeState == .notLiked

        Task {
            do {
                if shouldLike {
                    try await repository.likeEvent(id: eventID)
                } else {
                    try await repository.unlikeEvent(id: eventID)
                }

                events[index].likeState = shouldLike ? .liked : .notLiked
                events[index].likeCount += shouldLike ? 1 : -1
                error = nil
            } catch let appError as AppError {
                error = appError
            } catch {
                self.error = .unknown
            }
        }
    }

    func toggleRegistration(for eventID: String) {
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }
        let shouldRegister = events[index].registrationState != .registered

        Task {
            do {
                if shouldRegister {
                    try await repository.registerForEvent(id: eventID)
                } else {
                    try await repository.cancelEventRegistration(id: eventID)
                }

                events[index].registrationState = shouldRegister ? .registered : .notRegistered
                error = nil
            } catch let appError as AppError {
                error = appError
            } catch {
                self.error = .unknown
            }
        }
    }

    func event(for eventID: String) -> Event? {
        events.first(where: { $0.id == eventID })
    }

    func deleteEvent(id: String) async throws {
        do {
            try await repository.deleteEvent(id: id)
            error = nil
            await refresh()
        } catch let appError as AppError {
            error = appError
            throw appError
        } catch {
            self.error = .unknown
            throw AppError.unknown
        }
    }

    private func startLoad(force: Bool) async {
        guard force || !hasLoaded else { return }

        loadTask?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoad()
        }
        loadTask = task
        await task.value
    }

    private func performLoad() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let loadedEvents = try await repository.fetchEvents()
            guard !Task.isCancelled else { return }
            events = loadedEvents
            contentVersion &+= 1
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

@MainActor
final class OrganizationsViewModel: ObservableObject {
    @Published var organizations: [Organization]
    @Published private(set) var error: AppError?
    private let repository: OrganizationRepository

    init(repository: OrganizationRepository) {
        self.repository = repository
        organizations = []
        reload()
    }

    func reload() {
        Task {
            do {
                organizations = try await repository.fetchOrganizations()
                error = nil
            } catch let appError as AppError {
                error = appError
            } catch {
                self.error = .unknown
            }
        }
    }

    func toggleLike(for organizationID: String) {
        guard let index = organizations.firstIndex(where: { $0.id == organizationID }) else { return }
        let shouldLike = organizations[index].likeState == .notLiked

        Task {
            do {
                if shouldLike {
                    try await repository.likeOrganization(id: organizationID)
                } else {
                    try await repository.unlikeOrganization(id: organizationID)
                }

                organizations[index].likeState = shouldLike ? .liked : .notLiked
                organizations[index].likeCount += shouldLike ? 1 : -1
                error = nil
            } catch let appError as AppError {
                error = appError
            } catch {
                self.error = .unknown
            }
        }
    }

    func organization(for organizationID: String) -> Organization? {
        organizations.first(where: { $0.id == organizationID })
    }
}

@MainActor
final class MarketplaceViewModel: ObservableObject {
    @Published var items: [MarketplaceItem]
    @Published private(set) var error: AppError?
    private let repository: MarketplaceRepository

    init(repository: MarketplaceRepository) {
        self.repository = repository
        items = []
        reload()
    }

    func reload() {
        Task {
            do {
                items = try await repository.fetchMarketplaceItems()
                error = nil
            } catch let appError as AppError {
                error = appError
            } catch {
                self.error = .unknown
            }
        }
    }

    func toggleLike(for itemID: String) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        let shouldLike = items[index].likeState == .notLiked

        Task {
            do {
                if shouldLike {
                    try await repository.likeMarketplaceItem(id: itemID)
                } else {
                    try await repository.unlikeMarketplaceItem(id: itemID)
                }

                items[index].likeState = shouldLike ? .liked : .notLiked
                items[index].likeCount += shouldLike ? 1 : -1
                error = nil
            } catch let appError as AppError {
                error = appError
            } catch {
                self.error = .unknown
            }
        }
    }

    func item(for itemID: String) -> MarketplaceItem? {
        items.first(where: { $0.id == itemID })
    }
}

@MainActor
final class InfoViewModel: ObservableObject {
    @Published private(set) var items: [InfoItem]
    @Published private(set) var error: AppError?
    private let repository: InfoRepository

    init(repository: InfoRepository) {
        self.repository = repository
        items = []
        reload()
    }

    func reload() {
        Task {
            do {
                items = try await repository.fetchInfoItems()
                error = nil
            } catch let appError as AppError {
                error = appError
            } catch {
                self.error = .unknown
            }
        }
    }
}

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published private(set) var user: AppUser
    @Published var settings: UserSettings
    @Published private(set) var error: AppError?
    private let repository: UserRepository

    init(repository: UserRepository) {
        self.repository = repository
        user = .placeholder
        settings = .stored
        reload()
    }

    func reload() {
        Task {
            do {
                user = try await repository.fetchCurrentUser()
                settings = try await repository.fetchSettings()
                settings.language = LocalizationStore.language
                error = nil
            } catch let appError as AppError {
                error = appError
            } catch {
                self.error = .unknown
            }
        }
    }

    var capabilities: [String] {
        var items = [AppStrings.Common.likes]
        if user.role.canCreateContent {
            items.append(AppStrings.Roles.moderator)
        }
        if user.role.canManageModerators {
            items.append(AppStrings.Roles.admin)
        }
        if user.role.canManageUsers {
            items.append(AppStrings.Roles.owner)
        }
        return items
    }
}
