import Foundation

protocol UserRepository {
    func fetchCurrentUser() async throws -> AppUser
    func fetchSettings() async throws -> UserSettings
    func updateProfile(_ profile: EditableUserProfileDraft) async throws -> AppUser
}

protocol FeedbackRepository {
    func submitFeedback(_ feedback: FeedbackItem) async throws
    func fetchFeedback() async throws -> [FeedbackItem]
    func updateFeedbackStatus(id: String, status: FeedbackStatus) async throws
}

protocol NewsRepository {
    func fetchNews() async throws -> [NewsPost]
    func fetchPendingNews() async throws -> [NewsPost]
    func fetchOrganizationModerationNews(organizationID: String) async throws -> [NewsPost]
    func createNews(_ news: NewsPost) async throws
    func updateNews(_ news: NewsPost) async throws
    func updateNewsImageURL(id: String, imageURL: String?) async throws
    func deleteNews(id: String) async throws
    func likeNews(id: String) async throws
    func unlikeNews(id: String) async throws
    func recordNewsView(id: String) async throws -> Bool
    func fetchNewsComments(newsID: String) async throws -> [Comment]
    func addNewsComment(newsID: String, text: String, author: AppUser) async throws -> Comment
    func updateNewsComment(newsID: String, commentID: String, text: String) async throws -> Comment
    func deleteNewsComment(newsID: String, commentID: String) async throws
    func bookmarkNews(id: String) async throws
    func unbookmarkNews(id: String) async throws
    func updateModerationStatus(id: String, newStatus: ModerationStatus) async throws
}

protocol EventRepository {
    func fetchEvents() async throws -> [Event]
    func fetchRegisteredEvents() async throws -> [Event]
    func fetchPendingEvents() async throws -> [Event]
    func fetchOrganizationModerationEvents(organizationID: String) async throws -> [Event]
    func createEvent(_ event: Event) async throws
    func updateEvent(_ event: Event) async throws
    func updateEventImageURL(id: String, imageURL: String?) async throws
    func deleteEvent(id: String) async throws
    func likeEvent(id: String) async throws
    func unlikeEvent(id: String) async throws
    func recordEventView(id: String) async throws -> Bool
    func fetchEventComments(eventID: String) async throws -> [Comment]
    func addEventComment(eventID: String, text: String, author: AppUser) async throws -> Comment
    func updateEventComment(eventID: String, commentID: String, text: String) async throws -> Comment
    func deleteEventComment(eventID: String, commentID: String) async throws
    func registerForEvent(id: String) async throws
    func cancelEventRegistration(id: String) async throws
    func bookmarkEvent(id: String) async throws
    func unbookmarkEvent(id: String) async throws
    func updateModerationStatus(id: String, newStatus: ModerationStatus) async throws
}

protocol OrganizationRepository {
    func fetchOrganizations() async throws -> [Organization]
    func fetchOrganization(id: String) async throws -> Organization
    func fetchPendingOrganizations() async throws -> [Organization]
    func createOrganization(_ organization: Organization) async throws
    func updateOrganization(_ organization: Organization) async throws
    func deleteOrganization(id: String) async throws
    func uploadOrganizationImage(data: Data, organizationID: String) async throws -> URL
    func likeOrganization(id: String) async throws
    func unlikeOrganization(id: String) async throws
    func bookmarkOrganization(id: String) async throws
    func unbookmarkOrganization(id: String) async throws
    func isOrganizationBookmarked(id: String) async throws -> Bool
    func fetchBookmarkedOrganizationIDs() async throws -> Set<String>
    func updateModerationStatus(id: String, newStatus: ModerationStatus) async throws
}

protocol OrganizationPhotoRepository {
    func fetchPhotos(organizationId: String) async throws -> [OrganizationPhoto]
    func addPhoto(organizationId: String, imageData: Data, caption: String?, uploadedBy: String) async throws -> OrganizationPhoto
    func deletePhoto(_ photo: OrganizationPhoto) async throws
}

protocol InfoRepository {
    func fetchGuideArticles() async throws -> [GuideArticle]
}
