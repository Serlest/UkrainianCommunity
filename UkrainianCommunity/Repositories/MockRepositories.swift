import Foundation

private actor MockRepositoryStore {
    static let shared = MockRepositoryStore()

    var user = MockContentBuilder.currentUser()
    var news = MockContentBuilder.newsPosts()
    var events = MockContentBuilder.events()
    var organizations = MockContentBuilder.organizations()
    var infoItems = MockContentBuilder.infoItems()
    var guideArticles = MockContentBuilder.guideArticles()
    var feedbackItems: [FeedbackItem] = []

    func updateUserProfile(_ profile: EditableUserProfileDraft) -> AppUser {
        user = AppUser(
            id: user.id,
            fullName: profile.fullName,
            displayName: profile.displayName,
            city: profile.city,
            email: user.email,
            avatarURL: profile.avatarURL ?? user.avatarURL,
            bio: profile.bio,
            telegramUsername: profile.telegramUsername,
            role: user.role,
            globalRole: user.globalRole,
            moderatorSections: user.moderatorSections,
            blockState: user.blockState,
            accountStatus: user.accountStatus,
            banExpiresAt: user.banExpiresAt,
            warningCount: user.warningCount,
            communityMemberships: user.communityMemberships,
            selectedFederalState: profile.selectedFederalState,
            acceptedTermsAt: user.acceptedTermsAt,
            acceptedPrivacyAt: user.acceptedPrivacyAt,
            termsVersion: user.termsVersion,
            privacyVersion: user.privacyVersion,
            createdAt: user.createdAt,
            updatedAt: .now
        )
        return user
    }

    func createFeedback(_ item: FeedbackItem) {
        feedbackItems.insert(item, at: 0)
    }

    func toggleNewsLike(id: String, isLiked: Bool) throws {
        guard let index = news.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
        news[index].likeState = isLiked ? .liked : .notLiked
        news[index].likeCount += isLiked ? 1 : -1
    }

    func createNews(_ item: NewsPost) {
        news.insert(item, at: 0)
    }

    func updateNews(_ item: NewsPost) throws {
        guard let index = news.firstIndex(where: { $0.id == item.id }) else { throw AppError.notFound }
        let existingItem = news[index]
        news[index] = NewsPost(
            id: existingItem.id,
            title: item.title,
            subtitle: item.subtitle,
            regionScope: item.regionScope,
            federalState: item.federalState,
            city: item.city,
            source: item.source,
            imageURL: item.imageURL,
            body: item.body,
            authorName: item.authorName,
            publishedAt: existingItem.publishedAt,
            createdAt: existingItem.createdAt,
            updatedAt: item.updatedAt,
            comments: existingItem.comments,
            moderationStatus: existingItem.moderationStatus,
            likeCount: existingItem.likeCount,
            likeState: existingItem.likeState
        )
    }

    func pendingNews() -> [NewsPost] {
        news
            .filter { $0.moderationStatus == .pendingReview }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func deleteNews(id: String) throws {
        guard let index = news.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
        news.remove(at: index)
    }

    func updateNewsModerationStatus(id: String, newStatus: ModerationStatus) throws {
        guard let index = news.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
        news[index].moderationStatus = newStatus
    }

    func toggleEventLike(id: String, isLiked: Bool) throws {
        guard let index = events.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
        events[index].likeState = isLiked ? .liked : .notLiked
        events[index].likeCount += isLiked ? 1 : -1
    }

    func setEventRegistration(id: String, isRegistered: Bool) throws {
        guard let index = events.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
        let currentState = events[index].registrationState
        let currentlyRegistered = currentState == .registered

        guard currentlyRegistered != isRegistered else { return }

        events[index].registrationState = isRegistered ? .registered : .notRegistered
        let adjustedCount = isRegistered
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
            registeredCount: adjustedCount,
            comments: events[index].comments,
            moderationStatus: events[index].moderationStatus,
            registrationState: isRegistered ? .registered : .notRegistered,
            likeCount: events[index].likeCount,
            likeState: events[index].likeState
        )
    }

    func createEvent(_ item: Event) {
        events.append(item)
        events.sort { $0.startDate < $1.startDate }
    }

    func updateEvent(_ item: Event) throws {
        guard let index = events.firstIndex(where: { $0.id == item.id }) else { throw AppError.notFound }
        let existingItem = events[index]
        events[index] = Event(
            id: existingItem.id,
            title: item.title,
            summary: item.summary,
            details: item.details,
            regionScope: item.regionScope,
            federalState: item.federalState,
            source: item.source,
            city: item.city,
            venue: item.venue,
            imageURL: item.imageURL,
            startDate: item.startDate,
            endDate: item.endDate,
            createdAt: existingItem.createdAt,
            updatedAt: item.updatedAt,
            capacity: item.capacity,
            registeredCount: existingItem.registeredCount,
            comments: existingItem.comments,
            moderationStatus: existingItem.moderationStatus,
            registrationState: existingItem.registrationState,
            likeCount: existingItem.likeCount,
            likeState: existingItem.likeState
        )
        events.sort { $0.startDate < $1.startDate }
    }

    func pendingEvents() -> [Event] {
        events
            .filter { $0.moderationStatus == .pendingReview }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func deleteEvent(id: String) throws {
        guard let index = events.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
        events.remove(at: index)
    }

    func updateEventModerationStatus(id: String, newStatus: ModerationStatus) throws {
        guard let index = events.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
        events[index].moderationStatus = newStatus
    }

    func toggleOrganizationLike(id: String, isLiked: Bool) throws {
        guard let index = organizations.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
        organizations[index].likeState = isLiked ? .liked : .notLiked
        organizations[index].likeCount += isLiked ? 1 : -1
    }

    func pendingOrganizations() -> [Organization] {
        organizations
            .filter { $0.moderationStatus == .pendingReview }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func createOrganization(_ item: Organization) {
        organizations.insert(item, at: 0)
    }

    func updateOrganization(_ item: Organization) throws {
        guard let index = organizations.firstIndex(where: { $0.id == item.id }) else { throw AppError.notFound }
        let existingItem = organizations[index]
        organizations[index] = Organization(
            id: existingItem.id,
            name: item.name,
            description: item.description,
            regionScope: item.regionScope,
            federalState: item.federalState,
            city: item.city,
            imageURL: item.imageURL,
            contactEmail: item.contactEmail,
            website: item.website,
            createdAt: existingItem.createdAt,
            updatedAt: item.updatedAt,
            moderationStatus: existingItem.moderationStatus,
            likeCount: existingItem.likeCount,
            likeState: existingItem.likeState
        )
        organizations.sort { $0.createdAt > $1.createdAt }
    }

    func deleteOrganization(id: String) throws {
        guard let index = organizations.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
        organizations.remove(at: index)
    }

    func updateOrganizationModerationStatus(id: String, newStatus: ModerationStatus) throws {
        guard let index = organizations.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
        organizations[index].moderationStatus = newStatus
    }
}

struct MockUserRepository: UserRepository {
    private let store = MockRepositoryStore.shared

    func fetchCurrentUser() async throws -> AppUser {
        await store.user
    }

    func fetchSettings() async throws -> UserSettings {
        .stored
    }

    func updateProfile(_ profile: EditableUserProfileDraft) async throws -> AppUser {
        await store.updateUserProfile(profile)
    }
}

struct MockFeedbackRepository: FeedbackRepository {
    private let store = MockRepositoryStore.shared

    func submitFeedback(_ feedback: FeedbackItem) async throws {
        await store.createFeedback(feedback)
    }
}

struct MockNewsRepository: NewsRepository {
    private let store = MockRepositoryStore.shared

    func fetchNews() async throws -> [NewsPost] {
        await store.news
            .filter { $0.moderationStatus == .approved }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func fetchPendingNews() async throws -> [NewsPost] {
        await store.pendingNews()
    }

    func createNews(_ news: NewsPost) async throws {
        await store.createNews(news)
    }

    func updateNews(_ news: NewsPost) async throws {
        try await store.updateNews(news)
    }

    func deleteNews(id: String) async throws {
        try await store.deleteNews(id: id)
    }

    func likeNews(id: String) async throws {
        try await store.toggleNewsLike(id: id, isLiked: true)
    }

    func unlikeNews(id: String) async throws {
        try await store.toggleNewsLike(id: id, isLiked: false)
    }

    func updateModerationStatus(id: String, newStatus: ModerationStatus) async throws {
        try await store.updateNewsModerationStatus(id: id, newStatus: newStatus)
    }
}

struct MockEventRepository: EventRepository {
    private let store = MockRepositoryStore.shared

    func fetchEvents() async throws -> [Event] {
        await store.events
            .filter { $0.moderationStatus == .approved }
            .sorted { $0.startDate < $1.startDate }
    }

    func fetchRegisteredEvents() async throws -> [Event] {
        await store.events
            .filter { $0.moderationStatus == .approved && $0.registrationState == .registered }
            .sorted { $0.startDate < $1.startDate }
    }

    func fetchPendingEvents() async throws -> [Event] {
        await store.pendingEvents()
    }

    func createEvent(_ event: Event) async throws {
        await store.createEvent(event)
    }

    func updateEvent(_ event: Event) async throws {
        try await store.updateEvent(event)
    }

    func deleteEvent(id: String) async throws {
        try await store.deleteEvent(id: id)
    }

    func likeEvent(id: String) async throws {
        try await store.toggleEventLike(id: id, isLiked: true)
    }

    func unlikeEvent(id: String) async throws {
        try await store.toggleEventLike(id: id, isLiked: false)
    }

    func registerForEvent(id: String) async throws {
        try await store.setEventRegistration(id: id, isRegistered: true)
    }

    func cancelEventRegistration(id: String) async throws {
        try await store.setEventRegistration(id: id, isRegistered: false)
    }

    func updateModerationStatus(id: String, newStatus: ModerationStatus) async throws {
        try await store.updateEventModerationStatus(id: id, newStatus: newStatus)
    }
}

struct MockOrganizationRepository: OrganizationRepository {
    private let store = MockRepositoryStore.shared

    func fetchOrganizations() async throws -> [Organization] {
        await store.organizations
            .filter { $0.moderationStatus == .approved }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func fetchPendingOrganizations() async throws -> [Organization] {
        await store.pendingOrganizations()
    }

    func createOrganization(_ organization: Organization) async throws {
        await store.createOrganization(organization)
    }

    func updateOrganization(_ organization: Organization) async throws {
        try await store.updateOrganization(organization)
    }

    func deleteOrganization(id: String) async throws {
        try await store.deleteOrganization(id: id)
    }

    func uploadOrganizationImage(data: Data, organizationID: String) async throws -> URL {
        URL(string: "https://example.com/organizations/\(organizationID)/cover.jpg")!
    }

    func likeOrganization(id: String) async throws {
        try await store.toggleOrganizationLike(id: id, isLiked: true)
    }

    func unlikeOrganization(id: String) async throws {
        try await store.toggleOrganizationLike(id: id, isLiked: false)
    }

    func updateModerationStatus(id: String, newStatus: ModerationStatus) async throws {
        try await store.updateOrganizationModerationStatus(id: id, newStatus: newStatus)
    }
}

struct MockInfoRepository: InfoRepository {
    private let store = MockRepositoryStore.shared

    func fetchGuideArticles() async throws -> [GuideArticle] {
        await store.guideArticles
            .filter { $0.moderationStatus == .approved }
            .sorted { lhs, rhs in
                if lhs.isPinned == rhs.isPinned {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.isPinned && !rhs.isPinned
            }
    }
}
