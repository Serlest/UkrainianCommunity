import Combine
import Foundation

nonisolated private let defaultRefreshStaleInterval: TimeInterval = 300

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var feedItems: [HomeFeedItem]
    @Published private(set) var isLoading: Bool
    @Published private(set) var error: AppError?
    private let feedViewModel: HomeFeedViewModel

    init(
        newsRepository: NewsRepository,
        eventRepository: EventRepository,
        organizationRepository: OrganizationRepository
    ) {
        feedItems = []
        isLoading = false
        feedViewModel = HomeFeedViewModel(
            newsRepository: newsRepository,
            eventRepository: eventRepository,
            organizationRepository: organizationRepository
        )
    }

    func loadIfNeeded() async {
        await feedViewModel.loadIfNeeded()
        feedItems = feedViewModel.items
        isLoading = feedViewModel.isLoading
        error = feedViewModel.error
    }

    func reload() {
        Task {
            await refresh()
        }
    }

    func refresh() async {
        await feedViewModel.refresh()
        feedItems = feedViewModel.items
        isLoading = feedViewModel.isLoading
        error = feedViewModel.error
    }

    func refreshIfStale(maxAge: TimeInterval = defaultRefreshStaleInterval) async {
        await feedViewModel.refreshIfStale(maxAge: maxAge)
        feedItems = feedViewModel.items
        isLoading = feedViewModel.isLoading
        error = feedViewModel.error
    }
}

@MainActor
final class HomeFeedViewModel: ObservableObject {
    @Published private(set) var items: [HomeFeedItem]
    @Published private(set) var isLoading: Bool
    @Published private(set) var error: AppError?

    private let newsRepository: NewsRepository
    private let eventRepository: EventRepository
    private let organizationRepository: OrganizationRepository
    private var loadTask: Task<Void, Never>?
    private var hasLoaded = false
    private var lastLoadedAt: Date?

    init(
        newsRepository: NewsRepository,
        eventRepository: EventRepository,
        organizationRepository: OrganizationRepository
    ) {
        self.newsRepository = newsRepository
        self.eventRepository = eventRepository
        self.organizationRepository = organizationRepository
        items = []
        isLoading = false
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await startLoad(force: false)
    }

    func refresh() async {
        await startLoad(force: true)
    }

    func refreshIfStale(maxAge: TimeInterval = defaultRefreshStaleInterval) async {
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
            async let newsLoad = newsRepository.fetchNews()
            async let eventsLoad = eventRepository.fetchEvents()
            async let organizationsLoad = organizationRepository.fetchOrganizations()

            let newsItems = try await newsLoad.map(HomeFeedItem.init(post:))
            let eventItems = try await eventsLoad.map(HomeFeedItem.init(event:))
            let organizationItems = try await organizationsLoad.map(HomeFeedItem.init(organization:))

            guard !Task.isCancelled else { return }
            items = (newsItems + eventItems + organizationItems)
                .sorted { $0.publishedAt > $1.publishedAt }
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
}

@MainActor
final class NewsViewModel: ObservableObject {
    @Published var posts: [NewsPost]
    @Published private(set) var isLoading: Bool
    @Published private(set) var error: AppError?
    @Published private(set) var contentVersion = 0
    @Published private(set) var pendingNewsLikeIDs = Set<String>()
    private let repository: NewsRepository
    private var loadTask: Task<Void, Never>?
    private var hasLoaded = false
    private var lastLoadedAt: Date?

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

    func refreshIfStale(maxAge: TimeInterval = defaultRefreshStaleInterval) async {
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

    func toggleLike(for postID: String) {
        guard let index = posts.firstIndex(where: { $0.id == postID }) else { return }
        guard !pendingNewsLikeIDs.contains(postID) else { return }
        let shouldLike = posts[index].likeState == .notLiked
        let organizationID = posts[index].source.organizationId

        Task {
            pendingNewsLikeIDs.insert(postID)
            defer { pendingNewsLikeIDs.remove(postID) }

            do {
                if shouldLike {
                    try await repository.likeNews(id: postID)
                } else {
                    try await repository.unlikeNews(id: postID)
                }

                posts[index].likeState = shouldLike ? .liked : .notLiked
                posts[index].likeCount += shouldLike ? 1 : -1
                error = nil
                AppContentChangeBus.postNewsChanged(organizationID: organizationID)
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

    var editorRepository: NewsRepository {
        repository
    }

    func deleteNews(id: String) async throws {
        let organizationID = post(for: id)?.source.organizationId

        do {
            try await repository.deleteNews(id: id)
            error = nil
            AppContentChangeBus.postNewsChanged(organizationID: organizationID)
        } catch let appError as AppError {
            error = appError
            throw appError
        } catch {
            self.error = .unknown
            throw AppError.unknown
        }
    }

    func removeDeletedNews(id: String) {
        posts.removeAll { $0.id == id }
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
            let loadedPosts = try await repository.fetchNews()
            guard !Task.isCancelled else { return }
            posts = loadedPosts
            contentVersion &+= 1
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
}

@MainActor
final class EventsViewModel: ObservableObject {
    @Published var events: [Event]
    @Published private(set) var isLoading: Bool
    @Published private(set) var error: AppError?
    @Published private(set) var contentVersion = 0
    @Published private(set) var pendingEventLikeIDs = Set<String>()
    @Published private(set) var pendingEventRegistrationIDs = Set<String>()
    private let repository: EventRepository
    private var loadTask: Task<Void, Never>?
    private var hasLoaded = false
    private var lastLoadedAt: Date?

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

    func refreshIfStale(maxAge: TimeInterval = defaultRefreshStaleInterval) async {
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

    func toggleLike(for eventID: String) {
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }
        guard !pendingEventLikeIDs.contains(eventID) else { return }
        let shouldLike = events[index].likeState == .notLiked
        let organizationID = events[index].source.organizationId

        Task {
            pendingEventLikeIDs.insert(eventID)
            defer { pendingEventLikeIDs.remove(eventID) }

            do {
                if shouldLike {
                    try await repository.likeEvent(id: eventID)
                } else {
                    try await repository.unlikeEvent(id: eventID)
                }

                events[index].likeState = shouldLike ? .liked : .notLiked
                events[index].likeCount += shouldLike ? 1 : -1
                error = nil
                AppContentChangeBus.postEventsChanged(organizationID: organizationID)
            } catch let appError as AppError {
                error = appError
            } catch {
                self.error = .unknown
            }
        }
    }

    func toggleRegistration(for eventID: String) {
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { return }
        guard !pendingEventRegistrationIDs.contains(eventID) else { return }
        let shouldRegister = events[index].registrationState != .registered
        let organizationID = events[index].source.organizationId

        Task {
            pendingEventRegistrationIDs.insert(eventID)
            defer { pendingEventRegistrationIDs.remove(eventID) }

            do {
                if shouldRegister {
                    try await repository.registerForEvent(id: eventID)
                } else {
                    try await repository.cancelEventRegistration(id: eventID)
                }

                let updatedRegisteredCount = shouldRegister
                    ? events[index].registeredCount + 1
                    : max(0, events[index].registeredCount - 1)

                events[index] = Event(
                    id: events[index].id,
                    title: events[index].title,
                    summary: events[index].summary,
                    details: events[index].details,
                    regionScope: events[index].regionScope,
                    federalState: events[index].federalState,
                    source: events[index].source,
                    city: events[index].city,
                    venue: events[index].venue,
                    imageURL: events[index].imageURL,
                    startDate: events[index].startDate,
                    endDate: events[index].endDate,
                    createdAt: events[index].createdAt,
                    updatedAt: events[index].updatedAt,
                    capacity: events[index].capacity,
                    registeredCount: updatedRegisteredCount,
                    comments: events[index].comments,
                    moderationStatus: events[index].moderationStatus,
                    registrationState: shouldRegister ? .registered : .notRegistered,
                    likeCount: events[index].likeCount,
                    likeState: events[index].likeState
                )
                error = nil
                AppContentChangeBus.postEventsChanged(organizationID: organizationID)
                AppContentChangeBus.postRegistrationsChanged(organizationID: organizationID)
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

    var editorRepository: EventRepository {
        repository
    }

    func deleteEvent(id: String) async throws {
        let organizationID = event(for: id)?.source.organizationId

        do {
            try await repository.deleteEvent(id: id)
            error = nil
            AppContentChangeBus.postEventsChanged(organizationID: organizationID)
        } catch let appError as AppError {
            error = appError
            throw appError
        } catch {
            self.error = .unknown
            throw AppError.unknown
        }
    }

    func removeDeletedEvent(id: String) {
        events.removeAll { $0.id == id }
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
            let loadedEvents = try await repository.fetchEvents()
            guard !Task.isCancelled else { return }
            events = loadedEvents
            contentVersion &+= 1
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
}

@MainActor
final class OrganizationsViewModel: ObservableObject {
    @Published var organizations: [Organization]
    @Published private(set) var isLoading: Bool
    @Published private(set) var error: AppError?
    @Published private(set) var contentVersion = 0
    @Published private(set) var pendingOrganizationLikeIDs = Set<String>()
    @Published private(set) var pendingOrganizationDeleteIDs = Set<String>()
    @Published private(set) var isSavingOrganization = false
    @Published private(set) var isUploadingOrganizationImage = false
    @Published private(set) var validationErrorMessage: String?
    private let repository: OrganizationRepository
    private var loadTask: Task<Void, Never>?
    private var hasLoaded = false
    private var lastLoadedAt: Date?

    init(repository: OrganizationRepository) {
        self.repository = repository
        organizations = []
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

    func refreshIfStale(maxAge: TimeInterval = defaultRefreshStaleInterval) async {
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

    func toggleLike(for organizationID: String) {
        guard let index = organizations.firstIndex(where: { $0.id == organizationID }) else { return }
        guard !pendingOrganizationLikeIDs.contains(organizationID) else { return }
        let shouldLike = organizations[index].likeState == .notLiked

        Task {
            pendingOrganizationLikeIDs.insert(organizationID)
            defer { pendingOrganizationLikeIDs.remove(organizationID) }

            do {
                if shouldLike {
                    try await repository.likeOrganization(id: organizationID)
                } else {
                    try await repository.unlikeOrganization(id: organizationID)
                }

                organizations[index].likeState = shouldLike ? .liked : .notLiked
                organizations[index].likeCount += shouldLike ? 1 : -1
                error = nil
                AppContentChangeBus.postOrganizationsChanged(organizationID: organizationID)
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

    var editorRepository: OrganizationRepository {
        repository
    }

    func createOrganization(
        _ organization: Organization,
        imageData: Data?,
        user: AppUser?
    ) async throws {
        guard PermissionService.canCreateOrganization(user: user) else {
            validationErrorMessage = AppStrings.Organizations.actionPermissionError
            throw AppError.permissionDenied
        }

        try await saveOrganization(organization, imageData: imageData, isEditing: false)
    }

    func updateOrganization(
        _ organization: Organization,
        imageData: Data?,
        user: AppUser?
    ) async throws {
        guard PermissionService.canEditOrganization(organizationId: organization.id, user: user) else {
            validationErrorMessage = AppStrings.Organizations.actionPermissionError
            throw AppError.permissionDenied
        }

        try await saveOrganization(organization, imageData: imageData, isEditing: true)
    }

    func deleteOrganization(id: String, user: AppUser?) async throws {
        guard PermissionService.canDeleteOrganization(user: user) else {
            validationErrorMessage = AppStrings.Organizations.actionPermissionError
            throw AppError.permissionDenied
        }
        guard !pendingOrganizationDeleteIDs.contains(id) else { return }

        pendingOrganizationDeleteIDs.insert(id)
        defer { pendingOrganizationDeleteIDs.remove(id) }

        do {
            try await repository.deleteOrganization(id: id)
            error = nil
            validationErrorMessage = nil
            AppContentChangeBus.postOrganizationsChanged(organizationID: id)
        } catch let appError as AppError {
            error = appError
            throw appError
        } catch {
            self.error = .unknown
            throw AppError.unknown
        }
    }

    func removeDeletedOrganization(id: String) {
        organizations.removeAll { $0.id == id }
        contentVersion &+= 1
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
            let loadedOrganizations = try await repository.fetchOrganizations()
            guard !Task.isCancelled else { return }
            organizations = loadedOrganizations
            contentVersion &+= 1
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

    private func saveOrganization(_ organization: Organization, imageData: Data?, isEditing: Bool) async throws {
        guard !isSavingOrganization else { return }

        isSavingOrganization = true
        validationErrorMessage = nil
        defer {
            isSavingOrganization = false
            isUploadingOrganizationImage = false
        }

        do {
            let resolvedImageURL: String?
            if let imageData {
                isUploadingOrganizationImage = true
                let uploadedURL = try await repository.uploadOrganizationImage(data: imageData, organizationID: organization.id)
                resolvedImageURL = uploadedURL.absoluteString
                isUploadingOrganizationImage = false
            } else {
                resolvedImageURL = organization.imageURL
            }

            let organizationToSave = Organization(
                id: organization.id,
                name: organization.name,
                description: organization.description,
                regionScope: organization.regionScope,
                federalState: organization.federalState,
                city: organization.city,
                imageURL: resolvedImageURL,
                contactEmail: organization.contactEmail,
                website: organization.website,
                createdAt: organization.createdAt,
                updatedAt: organization.updatedAt,
                moderationStatus: organization.moderationStatus,
                likeCount: organization.likeCount,
                likeState: organization.likeState
            )

            if isEditing {
                try await repository.updateOrganization(organizationToSave)
                replaceOrganization(organizationToSave)
            } else {
                try await repository.createOrganization(organizationToSave)
                organizations.insert(organizationToSave, at: 0)
            }

            contentVersion &+= 1
            error = nil
            AppContentChangeBus.postOrganizationsChanged(organizationID: organizationToSave.id)
        } catch let appError as AppError {
            error = appError
            throw appError
        } catch {
            self.error = .unknown
            validationErrorMessage = error.localizedDescription
            throw AppError.unknown
        }
    }

    private func replaceOrganization(_ organization: Organization) {
        guard let index = organizations.firstIndex(where: { $0.id == organization.id }) else { return }
        organizations[index] = organization
    }
}

@MainActor
final class InfoViewModel: ObservableObject {
    @Published private(set) var articles: [GuideArticle]
    @Published private(set) var error: AppError?
    @Published private(set) var isLoading: Bool
    private let repository: InfoRepository
    private var loadTask: Task<Void, Never>?
    private var hasLoaded = false
    private var lastLoadedAt: Date?

    init(repository: InfoRepository) {
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

    func refreshIfStale(maxAge: TimeInterval = defaultRefreshStaleInterval) async {
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
}

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published private(set) var user: AppUser
    @Published var settings: UserSettings
    @Published private(set) var error: AppError?
    @Published private(set) var isSavingProfile = false
    @Published private(set) var isSubmittingFeedback = false
    @Published private(set) var isLoading = false
    @Published var profileMessage: String?
    @Published var feedbackMessage: String?
    private let repository: UserRepository
    private let feedbackRepository: FeedbackRepository
    private var loadTask: Task<Void, Never>?
    private var hasLoaded = false
    private var lastLoadedAt: Date?

    init(repository: UserRepository, feedbackRepository: FeedbackRepository) {
        self.repository = repository
        self.feedbackRepository = feedbackRepository
        user = .placeholder
        settings = .stored
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

    func refreshIfStale(maxAge: TimeInterval = defaultRefreshStaleInterval) async {
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

    var capabilities: [String] {
        [AppStrings.Common.likes, AppStrings.Profile.eventRegistration]
    }

    func saveProfile(_ profile: EditableUserProfileDraft) async -> AppUser? {
        guard !isSavingProfile else { return nil }

        let trimmedDisplayName = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDisplayName.isEmpty else {
            profileMessage = AppStrings.Profile.displayNameRequired
            return nil
        }

        isSavingProfile = true
        profileMessage = nil
        defer { isSavingProfile = false }

        do {
            let updatedUser = try await repository.updateProfile(profile)
            user = updatedUser
            error = nil
            profileMessage = AppStrings.Profile.profileSaved
            return updatedUser
        } catch let appError as AppError {
            error = appError
            profileMessage = AppStrings.Profile.profileSaveFailed
            return nil
        } catch {
            self.error = .unknown
            profileMessage = AppStrings.Profile.profileSaveFailed
            return nil
        }
    }

    func submitFeedback(type: FeedbackType, message: String, user: AppUser) async -> Bool {
        guard !isSubmittingFeedback else { return false }

        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            feedbackMessage = AppStrings.Feedback.messageRequired
            return false
        }

        isSubmittingFeedback = true
        feedbackMessage = nil
        defer { isSubmittingFeedback = false }

        do {
            try await feedbackRepository.submitFeedback(FeedbackItem(
                id: UUID().uuidString,
                type: type,
                message: trimmedMessage,
                status: .open,
                createdAt: .now,
                userId: user.id,
                userDisplayName: user.preferredDisplayName
            ))
            error = nil
            feedbackMessage = AppStrings.Feedback.submitted
            return true
        } catch let appError as AppError {
            error = appError
            feedbackMessage = AppStrings.Feedback.submitFailed
            return false
        } catch {
            self.error = .unknown
            feedbackMessage = AppStrings.Feedback.submitFailed
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
        self.loadTask = nil
    }

    private func performLoad() async {
        isLoading = true
        defer { isLoading = false }

        do {
            if !(repository is FirestoreUserRepository) {
                user = try await repository.fetchCurrentUser()
            }
            settings = try await repository.fetchSettings()
            settings.language = LocalizationStore.language
            error = nil
            profileMessage = nil
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
}
