import Foundation

protocol UserRepository {
    func fetchCurrentUser() async throws -> AppUser
    func fetchSettings() async throws -> UserSettings
    func updateProfile(_ profile: EditableUserProfileDraft) async throws -> AppUser
}

protocol FeedbackRepository {
    func submitFeedback(_ feedback: FeedbackItem) async throws
}

protocol NewsRepository {
    func fetchNews() async throws -> [NewsPost]
    func fetchPendingNews() async throws -> [NewsPost]
    func createNews(_ news: NewsPost) async throws
    func updateNews(_ news: NewsPost) async throws
    func deleteNews(id: String) async throws
    func likeNews(id: String) async throws
    func unlikeNews(id: String) async throws
    func updateModerationStatus(id: String, newStatus: ModerationStatus) async throws
}

protocol EventRepository {
    func fetchEvents() async throws -> [Event]
    func fetchRegisteredEvents() async throws -> [Event]
    func fetchPendingEvents() async throws -> [Event]
    func createEvent(_ event: Event) async throws
    func updateEvent(_ event: Event) async throws
    func deleteEvent(id: String) async throws
    func likeEvent(id: String) async throws
    func unlikeEvent(id: String) async throws
    func registerForEvent(id: String) async throws
    func cancelEventRegistration(id: String) async throws
    func updateModerationStatus(id: String, newStatus: ModerationStatus) async throws
}

protocol OrganizationRepository {
    func fetchOrganizations() async throws -> [Organization]
    func fetchPendingOrganizations() async throws -> [Organization]
    func createOrganization(_ organization: Organization) async throws
    func updateOrganization(_ organization: Organization) async throws
    func deleteOrganization(id: String) async throws
    func uploadOrganizationImage(data: Data, organizationID: String) async throws -> URL
    func likeOrganization(id: String) async throws
    func unlikeOrganization(id: String) async throws
    func updateModerationStatus(id: String, newStatus: ModerationStatus) async throws
}

protocol InfoRepository {
    func fetchGuideArticles() async throws -> [GuideArticle]
}
