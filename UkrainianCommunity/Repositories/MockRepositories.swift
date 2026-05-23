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
    var viewedNewsIDs = Set<String>()

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

    func feedback() -> [FeedbackItem] {
        feedbackItems.sorted { $0.createdAt > $1.createdAt }
    }

    func updateFeedbackStatus(id: String, status: FeedbackStatus) throws {
        guard let index = feedbackItems.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
        let item = feedbackItems[index]
        feedbackItems[index] = FeedbackItem(
            id: item.id,
            type: item.type,
            message: item.message,
            status: status,
            createdAt: item.createdAt,
            userId: item.userId,
            userDisplayName: item.userDisplayName
        )
    }

    func toggleNewsLike(id: String, isLiked: Bool) throws {
        guard let index = news.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
        news[index].likeState = isLiked ? .liked : .notLiked
        news[index].likeCount += isLiked ? 1 : -1
    }

    func recordNewsView(id: String) throws -> Bool {
        guard let index = news.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
        guard !viewedNewsIDs.contains(id) else { return false }
        viewedNewsIDs.insert(id)
        news[index].viewCount += 1
        return true
    }

    func setNewsBookmark(id: String, isBookmarked: Bool) throws {
        guard let index = news.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
        news[index].isBookmarked = isBookmarked
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
            category: item.category,
            tags: item.tags,
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
            likeState: existingItem.likeState,
            viewCount: existingItem.viewCount,
            isBookmarked: existingItem.isBookmarked,
            commentCount: existingItem.commentCount
        )
    }

    func updateNewsImageURL(id: String, imageURL: String?) throws {
        guard let index = news.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
        news[index] = news[index].settingImageURL(imageURL)
    }

    func pendingNews() -> [NewsPost] {
        news
            .filter { $0.moderationStatus == .pendingReview }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func organizationModerationNews(organizationID: String) -> [NewsPost] {
        news
            .filter {
                $0.source.sourceType == .organization
                    && $0.source.organizationId == organizationID
                    && [.pendingReview, .rejected, .archived].contains($0.moderationStatus)
            }
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

    func addNewsComment(newsID: String, text: String, author: AppUser) throws -> Comment {
        guard let index = news.firstIndex(where: { $0.id == newsID }) else { throw AppError.notFound }
        let comment = Comment(
            id: UUID().uuidString,
            parentType: .news,
            parentId: newsID,
            authorId: author.id,
            authorName: author.commentDisplayName,
            authorPhotoURL: author.avatarURL?.absoluteString,
            text: String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000)),
            createdAt: .now
        )
        news[index].comments.append(comment)
        news[index].commentCount += 1
        return comment
    }

    func updateNewsComment(newsID: String, commentID: String, text: String) throws -> Comment {
        guard let postIndex = news.firstIndex(where: { $0.id == newsID }),
              let commentIndex = news[postIndex].comments.firstIndex(where: { $0.id == commentID }) else {
            throw AppError.notFound
        }
        let existing = news[postIndex].comments[commentIndex]
        let updated = Comment(
            id: existing.id,
            parentType: existing.parentType,
            parentId: existing.parentId,
            authorId: existing.authorId,
            authorName: existing.authorName,
            authorPhotoURL: existing.authorPhotoURL,
            text: String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000)),
            createdAt: existing.createdAt,
            updatedAt: .now,
            moderationStatus: existing.moderationStatus,
            isDeleted: existing.isDeleted
        )
        news[postIndex].comments[commentIndex] = updated
        return updated
    }

    func deleteNewsComment(newsID: String, commentID: String) throws {
        guard let index = news.firstIndex(where: { $0.id == newsID }) else { throw AppError.notFound }
        news[index].comments.removeAll { $0.id == commentID }
        news[index].commentCount = max(0, news[index].commentCount - 1)
    }

    func newsComments(newsID: String) throws -> [Comment] {
        guard let post = news.first(where: { $0.id == newsID }) else { throw AppError.notFound }
        return post.comments.filter { !$0.isDeleted }
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
            authorId: events[index].authorId,
            authorName: events[index].authorName,
            city: events[index].city,
            venue: events[index].venue,
            address: events[index].address,
            locationNote: events[index].locationNote,
            latitude: events[index].latitude,
            longitude: events[index].longitude,
            imageURL: events[index].imageURL,
            startDate: events[index].startDate,
            endDate: events[index].endDate,
            createdAt: events[index].createdAt,
            updatedAt: events[index].updatedAt,
            price: events[index].price,
            capacity: events[index].capacity,
            registeredCount: adjustedCount,
            comments: events[index].comments,
            moderationStatus: events[index].moderationStatus,
            registrationState: isRegistered ? .registered : .notRegistered,
            likeCount: events[index].likeCount,
            likeState: events[index].likeState,
            viewCount: events[index].viewCount,
            category: events[index].category,
            isAllDay: events[index].isAllDay,
            isBookmarked: events[index].isBookmarked,
            commentCount: events[index].commentCount
        )
    }

    func setEventBookmark(id: String, isBookmarked: Bool) throws {
        guard let index = events.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
        events[index].isBookmarked = isBookmarked
    }

    func recordEventView(id: String) throws -> Bool {
        guard let index = events.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
        events[index].viewCount += 1
        return true
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
            authorId: item.authorId ?? existingItem.authorId,
            authorName: item.authorName ?? existingItem.authorName,
            city: item.city,
            venue: item.venue,
            address: item.address,
            locationNote: item.locationNote,
            latitude: item.latitude,
            longitude: item.longitude,
            imageURL: item.imageURL,
            startDate: item.startDate,
            endDate: item.endDate,
            createdAt: existingItem.createdAt,
            updatedAt: item.updatedAt,
            price: item.price,
            capacity: item.capacity,
            registeredCount: existingItem.registeredCount,
            comments: existingItem.comments,
            moderationStatus: existingItem.moderationStatus,
            registrationState: existingItem.registrationState,
            likeCount: existingItem.likeCount,
            likeState: existingItem.likeState,
            viewCount: existingItem.viewCount,
            category: item.category,
            isAllDay: item.isAllDay,
            isBookmarked: existingItem.isBookmarked,
            commentCount: existingItem.commentCount
        )
        events.sort { $0.startDate < $1.startDate }
    }

    func updateEventImageURL(id: String, imageURL: String?) throws {
        guard let index = events.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
        events[index] = events[index].settingImageURL(imageURL)
    }

    func pendingEvents() -> [Event] {
        events
            .filter { $0.moderationStatus == .pendingReview }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func organizationModerationEvents(organizationID: String) -> [Event] {
        events
            .filter {
                $0.source.sourceType == .organization
                    && $0.source.organizationId == organizationID
                    && [.pendingReview, .rejected, .archived].contains($0.moderationStatus)
            }
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

    func addEventComment(eventID: String, text: String, author: AppUser) throws -> Comment {
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { throw AppError.notFound }
        let comment = Comment(
            id: UUID().uuidString,
            parentType: .event,
            parentId: eventID,
            authorId: author.id,
            authorName: author.commentDisplayName,
            authorPhotoURL: author.avatarURL?.absoluteString,
            text: String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000)),
            createdAt: .now
        )
        events[index].comments.append(comment)
        events[index].commentCount += 1
        return comment
    }

    func updateEventComment(eventID: String, commentID: String, text: String) throws -> Comment {
        guard let eventIndex = events.firstIndex(where: { $0.id == eventID }),
              let commentIndex = events[eventIndex].comments.firstIndex(where: { $0.id == commentID }) else {
            throw AppError.notFound
        }
        let existing = events[eventIndex].comments[commentIndex]
        let updated = Comment(
            id: existing.id,
            parentType: existing.parentType,
            parentId: existing.parentId,
            authorId: existing.authorId,
            authorName: existing.authorName,
            authorPhotoURL: existing.authorPhotoURL,
            text: String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000)),
            createdAt: existing.createdAt,
            updatedAt: .now,
            moderationStatus: existing.moderationStatus,
            isDeleted: existing.isDeleted
        )
        events[eventIndex].comments[commentIndex] = updated
        return updated
    }

    func deleteEventComment(eventID: String, commentID: String) throws {
        guard let index = events.firstIndex(where: { $0.id == eventID }) else { throw AppError.notFound }
        events[index].comments.removeAll { $0.id == commentID }
        events[index].commentCount = max(0, events[index].commentCount - 1)
    }

    func eventComments(eventID: String) throws -> [Comment] {
        guard let event = events.first(where: { $0.id == eventID }) else { throw AppError.notFound }
        return event.comments.filter { !$0.isDeleted }
    }

    func toggleOrganizationLike(id: String, isLiked: Bool) throws {
        guard let index = organizations.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
        organizations[index].likeState = isLiked ? .liked : .notLiked
        organizations[index].subscriberCount = max(0, organizations[index].subscriberCount + (isLiked ? 1 : -1))
    }

    func setOrganizationBookmark(id: String, isBookmarked: Bool) throws {
        guard let index = organizations.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
        organizations[index].isBookmarked = isBookmarked
    }

    func bookmarkedOrganizationIDs() -> Set<String> {
        Set(organizations.filter(\.isBookmarked).map(\.id))
    }

    func pendingOrganizations() -> [Organization] {
        organizations
            .filter { $0.moderationStatus == .pendingReview }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func organization(id: String) throws -> Organization {
        guard let organization = organizations.first(where: { $0.id == id }) else {
            throw AppError.notFound
        }
        return organization
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
            shortDescription: item.shortDescription,
            fullDescription: item.fullDescription,
            regionScope: item.regionScope,
            federalState: item.federalState,
            city: item.city,
            imageURL: item.imageURL,
            logoURL: item.logoURL,
            coverURL: item.coverURL,
            contactEmail: item.contactEmail,
            email: item.email,
            phone: item.phone,
            website: item.website,
            address: item.address,
            latitude: item.latitude,
            longitude: item.longitude,
            organizationType: item.organizationType,
            foundedYear: item.foundedYear,
            foundedMonth: item.foundedMonth,
            languages: item.languages,
            socialLinks: item.socialLinks,
            subscriberCount: item.subscriberCount,
            eventsHeldCount: item.eventsHeldCount,
            volunteersCount: item.volunteersCount,
            helpedPeopleCount: item.helpedPeopleCount,
            ownerId: item.ownerId,
            adminIds: item.adminIds,
            moderatorIds: item.moderatorIds,
            createdAt: existingItem.createdAt,
            updatedAt: item.updatedAt,
            moderationStatus: existingItem.moderationStatus,
            likeCount: existingItem.likeCount,
            likeState: existingItem.likeState,
            isBookmarked: existingItem.isBookmarked
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

    func fetchFeedback() async throws -> [FeedbackItem] {
        await store.feedback()
    }

    func updateFeedbackStatus(id: String, status: FeedbackStatus) async throws {
        try await store.updateFeedbackStatus(id: id, status: status)
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

    func fetchOrganizationModerationNews(organizationID: String) async throws -> [NewsPost] {
        await store.organizationModerationNews(organizationID: organizationID)
    }

    func createNews(_ news: NewsPost) async throws {
        await store.createNews(news)
    }

    func updateNews(_ news: NewsPost) async throws {
        try await store.updateNews(news)
    }

    func updateNewsImageURL(id: String, imageURL: String?) async throws {
        try await store.updateNewsImageURL(id: id, imageURL: imageURL)
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

    func recordNewsView(id: String) async throws -> Bool {
        try await store.recordNewsView(id: id)
    }

    func fetchNewsComments(newsID: String) async throws -> [Comment] {
        try await store.newsComments(newsID: newsID)
    }

    func bookmarkNews(id: String) async throws {
        try await store.setNewsBookmark(id: id, isBookmarked: true)
    }

    func unbookmarkNews(id: String) async throws {
        try await store.setNewsBookmark(id: id, isBookmarked: false)
    }

    func updateModerationStatus(id: String, newStatus: ModerationStatus) async throws {
        try await store.updateNewsModerationStatus(id: id, newStatus: newStatus)
    }

    func addNewsComment(newsID: String, text: String, author: AppUser) async throws -> Comment {
        try await store.addNewsComment(newsID: newsID, text: text, author: author)
    }

    func updateNewsComment(newsID: String, commentID: String, text: String) async throws -> Comment {
        try await store.updateNewsComment(newsID: newsID, commentID: commentID, text: text)
    }

    func deleteNewsComment(newsID: String, commentID: String) async throws {
        try await store.deleteNewsComment(newsID: newsID, commentID: commentID)
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

    func fetchOrganizationModerationEvents(organizationID: String) async throws -> [Event] {
        await store.organizationModerationEvents(organizationID: organizationID)
    }

    func createEvent(_ event: Event) async throws {
        await store.createEvent(event)
    }

    func updateEvent(_ event: Event) async throws {
        try await store.updateEvent(event)
    }

    func updateEventImageURL(id: String, imageURL: String?) async throws {
        try await store.updateEventImageURL(id: id, imageURL: imageURL)
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

    func recordEventView(id: String) async throws -> Bool {
        try await store.recordEventView(id: id)
    }

    func fetchEventComments(eventID: String) async throws -> [Comment] {
        try await store.eventComments(eventID: eventID)
    }

    func registerForEvent(id: String) async throws {
        try await store.setEventRegistration(id: id, isRegistered: true)
    }

    func cancelEventRegistration(id: String) async throws {
        try await store.setEventRegistration(id: id, isRegistered: false)
    }

    func bookmarkEvent(id: String) async throws {
        try await store.setEventBookmark(id: id, isBookmarked: true)
    }

    func unbookmarkEvent(id: String) async throws {
        try await store.setEventBookmark(id: id, isBookmarked: false)
    }

    func updateModerationStatus(id: String, newStatus: ModerationStatus) async throws {
        try await store.updateEventModerationStatus(id: id, newStatus: newStatus)
    }

    func addEventComment(eventID: String, text: String, author: AppUser) async throws -> Comment {
        try await store.addEventComment(eventID: eventID, text: text, author: author)
    }

    func updateEventComment(eventID: String, commentID: String, text: String) async throws -> Comment {
        try await store.updateEventComment(eventID: eventID, commentID: commentID, text: text)
    }

    func deleteEventComment(eventID: String, commentID: String) async throws {
        try await store.deleteEventComment(eventID: eventID, commentID: commentID)
    }
}

struct MockOrganizationRepository: OrganizationRepository {
    private let store = MockRepositoryStore.shared

    func fetchOrganizations() async throws -> [Organization] {
        await store.organizations
            .filter { $0.moderationStatus == .approved }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func fetchOrganization(id: String) async throws -> Organization {
        try await store.organization(id: id)
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

    func bookmarkOrganization(id: String) async throws {
        try await store.setOrganizationBookmark(id: id, isBookmarked: true)
    }

    func unbookmarkOrganization(id: String) async throws {
        try await store.setOrganizationBookmark(id: id, isBookmarked: false)
    }

    func isOrganizationBookmarked(id: String) async throws -> Bool {
        await store.bookmarkedOrganizationIDs().contains(id)
    }

    func fetchBookmarkedOrganizationIDs() async throws -> Set<String> {
        await store.bookmarkedOrganizationIDs()
    }

    func updateModerationStatus(id: String, newStatus: ModerationStatus) async throws {
        try await store.updateOrganizationModerationStatus(id: id, newStatus: newStatus)
    }
}

private extension NewsPost {
    nonisolated func settingImageURL(_ imageURL: String?) -> NewsPost {
        NewsPost(
            id: id,
            title: title,
            subtitle: subtitle,
            regionScope: regionScope,
            federalState: federalState,
            city: city,
            category: category,
            tags: tags,
            source: source,
            imageURL: imageURL,
            body: body,
            authorName: authorName,
            publishedAt: publishedAt,
            createdAt: createdAt,
            updatedAt: Date(),
            comments: comments,
            moderationStatus: moderationStatus,
            likeCount: likeCount,
            likeState: likeState,
            viewCount: viewCount,
            isBookmarked: isBookmarked,
            commentCount: commentCount
        )
    }
}

private extension Event {
    nonisolated func settingImageURL(_ imageURL: String?) -> Event {
        Event(
            id: id,
            title: title,
            summary: summary,
            details: details,
            regionScope: regionScope,
            federalState: federalState,
            source: source,
            authorId: authorId,
            authorName: authorName,
            city: city,
            venue: venue,
            address: address,
            locationNote: locationNote,
            latitude: latitude,
            longitude: longitude,
            imageURL: imageURL,
            startDate: startDate,
            endDate: endDate,
            createdAt: createdAt,
            updatedAt: Date(),
            price: price,
            capacity: capacity,
            registeredCount: registeredCount,
            comments: comments,
            moderationStatus: moderationStatus,
            registrationState: registrationState,
            likeCount: likeCount,
            likeState: likeState,
            viewCount: viewCount,
            category: category,
            isAllDay: isAllDay,
            isBookmarked: isBookmarked,
            commentCount: commentCount
        )
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

private extension AppUser {
    nonisolated var commentDisplayName: String {
        let display = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !display.isEmpty { return display }
        let full = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        return full.isEmpty ? "Користувач" : full
    }
}
