import Foundation

protocol UserRepository {
    func fetchCurrentUser() async throws -> AppUser
    func fetchSettings() async throws -> UserSettings
    func updateProfile(_ profile: EditableUserProfileDraft) async throws -> AppUser
    func deleteAccount(currentUser: AppUser) async throws
}

protocol LegalDocumentRepository {
    func fetchActiveDocument(type: LegalDocumentType) async throws -> LegalDocument
    func fetchManagementState(type: LegalDocumentType) async throws -> LegalDocumentManagementState
    func saveDraft(_ draft: LegalDocumentDraft, updatedBy userID: String) async throws
    func publishDraft(_ draft: LegalDocumentDraft, publishedBy userID: String) async throws
    func acceptDocument(
        type: LegalDocumentType,
        version: String,
        appVersion: String?,
        locale: String?,
        acceptedFromPlatform: String
    ) async throws -> LegalAcceptanceReceipt
}

protocol NotificationPreferencesRepository {
    func fetchNotificationPreferences(userID: String) async throws -> NotificationPreferences
    func saveNotificationPreferences(_ preferences: NotificationPreferences, userID: String) async throws
}

protocol NotificationInboxRepository {
    func fetchNotifications(userID: String, limit: Int) async throws -> [AppNotification]
    func listenNotifications(
        userID: String,
        limit: Int,
        onChange: @escaping @MainActor ([AppNotification]) -> Void,
        onError: @escaping @MainActor (AppError) -> Void
    ) -> AppRealtimeListener
    func fetchUnreadCount(userID: String) async throws -> Int
    func markNotificationRead(userID: String, notificationID: String) async throws
    func markNotificationUnread(userID: String, notificationID: String) async throws
    func markAllNotificationsRead(userID: String) async throws
    func markNotificationPopupPresented(userID: String, notificationID: String) async throws
    func archiveNotification(userID: String, notificationID: String) async throws
    func deleteNotification(userID: String, notificationID: String) async throws
    func createNotification(userID: String, notification: AppNotification) async throws
}

protocol FeedbackRepository {
    func submitFeedback(_ feedback: FeedbackItem) async throws
    func fetchFeedback() async throws -> [FeedbackItem]
    func fetchFeedback(userID: String) async throws -> [FeedbackItem]
    func fetchFeedbackMessages(feedback: FeedbackItem) async throws -> [FeedbackMessage]
    func sendUserFeedbackMessage(feedback: FeedbackItem, text: String, user: AppUser) async throws
    func sendOwnerFeedbackReply(feedback: FeedbackItem, text: String, owner: AppUser) async throws
    func updateFeedbackStatus(id: String, status: FeedbackStatus) async throws
    func replyToFeedback(id: String, reply: String, repliedByUserID: String) async throws
    func closeFeedback(id: String) async throws
}

extension FeedbackRepository {
    func fetchFeedback(userID: String) async throws -> [FeedbackItem] {
        let items = try await fetchFeedback()
        return items.filter { $0.userId == userID }
    }

    func fetchFeedbackMessages(feedback: FeedbackItem) async throws -> [FeedbackMessage] {
        feedback.legacyMessages
    }

    func sendUserFeedbackMessage(feedback: FeedbackItem, text: String, user: AppUser) async throws {}

    func sendOwnerFeedbackReply(feedback: FeedbackItem, text: String, owner: AppUser) async throws {
        try await replyToFeedback(id: feedback.id, reply: text, repliedByUserID: owner.id)
    }

    func replyToFeedback(id: String, reply: String, repliedByUserID: String) async throws {
        try await updateFeedbackStatus(id: id, status: .answered)
    }

    func closeFeedback(id: String) async throws {
        try await updateFeedbackStatus(id: id, status: .closed)
    }
}

extension FeedbackItem {
    nonisolated var legacyMessages: [FeedbackMessage] {
        var messages = [
            FeedbackMessage(
                id: "\(id)_initial",
                feedbackId: id,
                senderId: userId,
                senderDisplayName: userDisplayName,
                senderRole: .user,
                text: message,
                createdAt: createdAt,
                isSystem: false
            )
        ]

        if let ownerReply, !ownerReply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            messages.append(FeedbackMessage(
                id: "\(id)_legacy_owner_reply",
                feedbackId: id,
                senderId: repliedByUserId ?? "",
                senderDisplayName: "Support",
                senderRole: .owner,
                text: ownerReply,
                createdAt: repliedAt ?? updatedAt,
                isSystem: false
            ))
        }

        return messages
    }
}

protocol NewsRepository {
    func fetchNews() async throws -> [NewsPost]
    func fetchPendingNews() async throws -> [NewsPost]
    func fetchOrganizationModerationNews(organizationID: String) async throws -> [NewsPost]
    func fetchOrganizationNewsCount(organizationID: String) async throws -> Int
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
    func fetchOrganizationEventCount(organizationID: String) async throws -> Int
    func createEvent(_ event: Event) async throws
    func updateEvent(_ event: Event) async throws
    func updateEventImageURL(id: String, imageURL: String?) async throws
    func deleteEvent(id: String) async throws
    func likeEvent(id: String) async throws
    func unlikeEvent(id: String) async throws
    func recordEventView(id: String) async throws -> Bool
    func fetchEventComments(eventID: String) async throws -> [Comment]
    func fetchEventRegistrations(eventID: String) async throws -> [EventRegistrationAttendee]
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
    func fetchOrganizationRequests(submittedByUserID: String) async throws -> [Organization]
    func createOrganization(_ organization: Organization) async throws
    func updateOrganization(_ organization: Organization) async throws
    func deleteOrganization(id: String) async throws
    func uploadOrganizationImage(data: Data, organizationID: String) async throws -> URL
    func likeOrganization(id: String) async throws
    func unlikeOrganization(id: String) async throws
    func subscribeOrganization(id: String) async throws
    func unsubscribeOrganization(id: String) async throws
    func fetchOrganizationSubscriberPage(organizationID: String, limit: Int, after cursor: OrganizationSubscriberCursor?) async throws -> OrganizationSubscriberPage
    func fetchPublicUserProfiles(userIDs: [String]) async throws -> [PublicUserProfile]
    func fetchOrganizationComments(organizationID: String) async throws -> [Comment]
    func addOrganizationComment(organizationID: String, text: String, author: AppUser) async throws -> Comment
    func updateOrganizationComment(organizationID: String, commentID: String, text: String) async throws -> Comment
    func deleteOrganizationComment(organizationID: String, commentID: String) async throws
    func bookmarkOrganization(id: String) async throws
    func unbookmarkOrganization(id: String) async throws
    func isOrganizationBookmarked(id: String) async throws -> Bool
    func fetchBookmarkedOrganizationIDs() async throws -> Set<String>
    func updateModerationStatus(id: String, newStatus: ModerationStatus) async throws
    func approveOrganizationRequest(id: String, reviewerID: String) async throws
    func requestOrganizationRevision(id: String, message: String, reviewerID: String) async throws
    func rejectOrganizationRequest(id: String, reason: String, reviewerID: String) async throws
}

protocol OrganizationPhotoRepository {
    func fetchPhotos(organizationId: String) async throws -> [OrganizationPhoto]
    func addPhoto(organizationId: String, imageData: Data, caption: String?, uploadedBy: String) async throws -> OrganizationPhoto
    func deletePhoto(_ photo: OrganizationPhoto) async throws
}
