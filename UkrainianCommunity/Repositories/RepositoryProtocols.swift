import Foundation

protocol UserRepository {
    func fetchCurrentUser() async throws -> AppUser
    func fetchSettings() async throws -> UserSettings
    func updateProfile(_ profile: EditableUserProfileDraft) async throws -> AppUser
    func deleteAccount(currentUser: AppUser) async throws
}

protocol LegalDocumentRepository {
    func fetchActiveDocument(type: LegalDocumentType) async throws -> LegalDocument
    func fetchActiveDocumentForReader(type: LegalDocumentType) async throws -> LegalDocument
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

extension LegalDocumentRepository {
    func fetchActiveDocumentForReader(type: LegalDocumentType) async throws -> LegalDocument {
        try await fetchActiveDocument(type: type)
    }
}

protocol DonationConfigRepository {
    func fetchDonationConfig() async throws -> DonationConfig?
    func saveDonationConfig(_ config: DonationConfig, updatedBy userID: String) async throws
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
    func clearNotifications(userID: String) async throws
    func createNotification(userID: String, notification: AppNotification) async throws
}

nonisolated enum NotificationPushRegistrationKind: String, Sendable {
    case firebaseInstallationID = "fid"
    case legacyFCMToken = "token"
}

nonisolated struct NotificationPushRegistration: Hashable, Sendable {
    let identifier: String
    let kind: NotificationPushRegistrationKind
}

protocol NotificationPushTokenRepository {
    func saveCurrentDeviceRegistration(
        userID: String,
        registration: NotificationPushRegistration
    ) async throws
    func deleteCurrentDeviceRegistration(
        userID: String,
        registration: NotificationPushRegistration
    ) async throws
}

protocol OwnerContentDraftRepository {
    func fetchDraftPage(
        userID: String,
        section: OwnerContentPlanningSection,
        limit: Int,
        after cursor: OwnerContentDraftPageCursor?
    ) async throws -> OwnerContentDraftPage
    func fetchDraft(userID: String, draftID: String) async throws -> OwnerContentDraft
    func beginPublication(
        userID: String,
        draftID: String,
        attemptID: String
    ) async throws -> OwnerContentPublicationLease
    func finalizePublication(
        userID: String,
        draftID: String,
        publication: ContentPlanningPublicationResult
    ) async throws
    func failPublication(
        userID: String,
        draftID: String,
        leaseID: String,
        message: String
    ) async throws
    func archive(userID: String, draftID: String) async throws
    func delete(userID: String, draftID: String) async throws
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
    func deleteFeedback(id: String) async throws
    func clearFeedbackInbox() async throws
    func decideDsaCase(_ request: DsaDecisionFunctionRequest) async throws
    func decideDsaAppeal(_ request: DsaAppealDecisionFunctionRequest) async throws
    func submitDsaAppeal(_ request: DsaAppealSubmissionFunctionRequest) async throws
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

    func deleteFeedback(id: String) async throws {}
    func clearFeedbackInbox() async throws {}
    func decideDsaCase(_ request: DsaDecisionFunctionRequest) async throws {}
    func decideDsaAppeal(_ request: DsaAppealDecisionFunctionRequest) async throws {}
    func submitDsaAppeal(_ request: DsaAppealSubmissionFunctionRequest) async throws {}
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

struct NewsPageCursor: Equatable {
    let publishedAt: Date
    let documentID: String
}

struct NewsPage {
    let items: [NewsPost]
    let nextCursor: NewsPageCursor?
    let hasMore: Bool
}

struct EventPageCursor: Equatable {
    let endDate: Date
    let documentID: String
}

struct EventPage {
    let items: [Event]
    let nextCursor: EventPageCursor?
    let hasMore: Bool
}

struct EventRegistrationMutationResult: Equatable {
    let eventID: String
    let registrationState: EventRegistrationState
    let registeredCount: Int
    let didChange: Bool
}

enum EventRegistrationMutationError: Error, Equatable {
    case full
    case registrationNotRequired
    case eventCancelled
    case eventPast
    case permissionDenied
    case network
    case notFound
    case unavailable

    var appError: AppError {
        switch self {
        case .permissionDenied:
            .permissionDenied
        case .network:
            .network
        case .notFound:
            .notFound
        case .full,
             .registrationNotRequired,
             .eventCancelled,
             .eventPast:
            .validationFailed
        case .unavailable:
            .unknown
        }
    }
}

protocol EventRegistrationMutating {
    @MainActor
    func registerForEvent(id: String, actionCapture: AnalyticsActionCapture?) async throws -> EventRegistrationMutationResult

    @MainActor
    func cancelEventRegistration(id: String) async throws -> EventRegistrationMutationResult
}

struct OrganizationPageCursor: Equatable {
    let createdAt: Date
    let documentID: String
}

struct OrganizationPage {
    let items: [Organization]
    let nextCursor: OrganizationPageCursor?
    let hasMore: Bool
}

protocol NewsRepository {
    func fetchNews() async throws -> [NewsPost]
    func fetchNews(id: String) async throws -> NewsPost
    func fetchBookmarkedNews() async throws -> [NewsPost]
    func fetchNewsPage(limit: Int, after cursor: NewsPageCursor?) async throws -> NewsPage
    func fetchNewsPage(
        limit: Int,
        after cursor: NewsPageCursor?,
        federalState: AustrianFederalState?
    ) async throws -> NewsPage
    func fetchNewsRecommendationCandidates(for source: NewsPost, limit: Int) async throws -> [NewsPost]
    func fetchOrganizationNews(organizationID: String, limit: Int) async throws -> [NewsPost]
    func fetchPendingNews() async throws -> [NewsPost]
    func fetchOrganizationModerationNews(organizationID: String) async throws -> [NewsPost]
    func fetchOrganizationNewsCount(organizationID: String) async throws -> Int
    func createNews(_ news: NewsPost) async throws
    func updateNews(_ news: NewsPost) async throws
    func updateExistingPlanningNews(_ news: NewsPost) async throws
    func updateNewsImageURL(id: String, imageURL: String?) async throws
    func deleteNews(id: String) async throws
    func likeNews(id: String, actionCapture: AnalyticsActionCapture?) async throws
    func unlikeNews(id: String) async throws
    func recordNewsView(id: String) async throws -> Bool
    func fetchNewsComments(newsID: String) async throws -> [Comment]
    func addNewsComment(newsID: String, text: String, author: AppUser) async throws -> Comment
    func updateNewsComment(newsID: String, commentID: String, text: String) async throws -> Comment
    func deleteNewsComment(newsID: String, commentID: String) async throws
    func bookmarkNews(id: String, actionCapture: AnalyticsActionCapture?) async throws
    func unbookmarkNews(id: String) async throws
    func updateModerationStatus(id: String, newStatus: ModerationStatus) async throws
}

protocol EventRepository: EventRegistrationMutating {
    func fetchEvents() async throws -> [Event]
    func fetchBookmarkedEvents() async throws -> [Event]
    func fetchEventsPage(limit: Int, after cursor: EventPageCursor?) async throws -> EventPage
    func fetchEventsPage(
        limit: Int,
        after cursor: EventPageCursor?,
        federalState: AustrianFederalState?
    ) async throws -> EventPage
    func fetchRecentPastEvents(
        limit: Int,
        federalState: AustrianFederalState?
    ) async throws -> [Event]
    func fetchEventRecommendationCandidates(for source: Event, limit: Int) async throws -> [Event]
    func fetchEvent(id: String) async throws -> Event
    func fetchOrganizationEvents(organizationID: String, limit: Int) async throws -> [Event]
    func fetchRegisteredEvents() async throws -> [Event]
    func fetchPendingEvents() async throws -> [Event]
    func fetchOrganizationModerationEvents(organizationID: String) async throws -> [Event]
    func fetchOrganizationEventCount(organizationID: String) async throws -> Int
    func createEvent(_ event: Event) async throws
    func updateEvent(_ event: Event) async throws
    func updateExistingPlanningEvent(_ event: Event) async throws
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
    func bookmarkEvent(id: String, actionCapture: AnalyticsActionCapture?) async throws
    func unbookmarkEvent(id: String) async throws
    func updateModerationStatus(id: String, newStatus: ModerationStatus) async throws
}

extension NewsRepository {
    func updateExistingPlanningNews(_ news: NewsPost) async throws {
        try await updateNews(news)
    }
}

extension EventRepository {
    func updateExistingPlanningEvent(_ event: Event) async throws {
        try await updateEvent(event)
    }
}

protocol OrganizationRepository {
    func fetchOrganizations() async throws -> [Organization]
    func fetchAuthoringOrganizations(user: AppUser) async throws -> [Organization]
    func fetchBookmarkedOrganizations() async throws -> [Organization]
    func fetchSubscribedOrganizations() async throws -> [Organization]
    func fetchOrganizationsPage(limit: Int, after cursor: OrganizationPageCursor?) async throws -> OrganizationPage
    func fetchOrganizationsPage(
        limit: Int,
        after cursor: OrganizationPageCursor?,
        federalState: AustrianFederalState?
    ) async throws -> OrganizationPage
    func fetchOrganization(id: String) async throws -> Organization
    func fetchPendingOrganizations() async throws -> [Organization]
    func fetchOrganizationRequests(submittedByUserID: String) async throws -> [Organization]
    func createOrganization(_ organization: Organization) async throws
    func updateOrganization(_ organization: Organization) async throws
    func deleteOrganization(id: String) async throws
    func uploadOrganizationImage(data: Data, organizationID: String) async throws -> URL
    func likeOrganization(id: String) async throws
    func unlikeOrganization(id: String) async throws
    func subscribeOrganization(id: String, actionCapture: AnalyticsActionCapture?) async throws
    func unsubscribeOrganization(id: String) async throws
    func fetchOrganizationSubscriberPage(organizationID: String, limit: Int, after cursor: OrganizationSubscriberCursor?) async throws -> OrganizationSubscriberPage
    func fetchPublicUserProfiles(userIDs: [String]) async throws -> [PublicUserProfile]
    func fetchOrganizationComments(organizationID: String) async throws -> [Comment]
    func addOrganizationComment(organizationID: String, text: String, author: AppUser) async throws -> Comment
    func updateOrganizationComment(organizationID: String, commentID: String, text: String) async throws -> Comment
    func deleteOrganizationComment(organizationID: String, commentID: String) async throws
    func bookmarkOrganization(id: String, actionCapture: AnalyticsActionCapture?) async throws
    func unbookmarkOrganization(id: String) async throws
    func isOrganizationBookmarked(id: String) async throws -> Bool
    func fetchBookmarkedOrganizationIDs() async throws -> Set<String>
    func updateModerationStatus(id: String, newStatus: ModerationStatus) async throws
    func approveOrganizationRequest(id: String, reviewerID: String) async throws
    func requestOrganizationRevision(id: String, message: String, reviewerID: String) async throws
    func rejectOrganizationRequest(id: String, reason: String, reviewerID: String) async throws
}

extension NewsRepository {
    func fetchNews(id: String) async throws -> NewsPost {
        guard let post = try await fetchNews().first(where: { $0.id == id }) else {
            throw AppError.notFound
        }
        return post
    }

    func fetchBookmarkedNews() async throws -> [NewsPost] {
        try await fetchNews().filter(\.isBookmarked)
    }

    func fetchNewsPage(limit: Int, after cursor: NewsPageCursor?) async throws -> NewsPage {
        let sortedItems = try await fetchNews()
        let startIndex: Int
        if let cursor,
           let cursorIndex = sortedItems.firstIndex(where: { $0.id == cursor.documentID }) {
            startIndex = sortedItems.index(after: cursorIndex)
        } else {
            startIndex = sortedItems.startIndex
        }

        let pageItems = Array(sortedItems.dropFirst(startIndex).prefix(max(1, limit)))
        let nextCursor = pageItems.last.map { NewsPageCursor(publishedAt: $0.publishedAt, documentID: $0.id) }
        return NewsPage(
            items: pageItems,
            nextCursor: nextCursor,
            hasMore: sortedItems.count > startIndex + pageItems.count
        )
    }

    func fetchNewsPage(
        limit: Int,
        after cursor: NewsPageCursor?,
        federalState: AustrianFederalState?
    ) async throws -> NewsPage {
        let sortedItems = try await fetchNews()
            .filter {
                RegionVisibilityMatcher.isVisible(
                    regionScope: $0.regionScope,
                    federalState: $0.federalState,
                    selectedFederalState: federalState
                )
            }
            .sorted {
                $0.publishedAt == $1.publishedAt
                    ? $0.id > $1.id
                    : $0.publishedAt > $1.publishedAt
            }
        let startIndex: Int
        if let cursor,
           let cursorIndex = sortedItems.firstIndex(where: { $0.id == cursor.documentID }) {
            startIndex = sortedItems.index(after: cursorIndex)
        } else {
            startIndex = sortedItems.startIndex
        }

        let pageItems = Array(sortedItems.dropFirst(startIndex).prefix(max(1, limit)))
        let nextCursor = pageItems.last.map { NewsPageCursor(publishedAt: $0.publishedAt, documentID: $0.id) }
        return NewsPage(
            items: pageItems,
            nextCursor: nextCursor,
            hasMore: sortedItems.count > startIndex + pageItems.count
        )
    }

    func fetchOrganizationNews(organizationID: String, limit: Int) async throws -> [NewsPost] {
        Array(try await fetchNews()
            .filter { $0.source.organizationId == organizationID }
            .prefix(max(1, limit)))
    }

    func fetchNewsRecommendationCandidates(for source: NewsPost, limit: Int) async throws -> [NewsPost] {
        Array(try await fetchNews()
            .filter { $0.id != source.id && $0.category == source.category }
            .prefix(min(max(1, limit), 12)))
    }
}

extension EventRepository {
    func fetchBookmarkedEvents() async throws -> [Event] {
        try await fetchEvents().filter(\.isBookmarked)
    }

    func fetchEventsPage(limit: Int, after cursor: EventPageCursor?) async throws -> EventPage {
        let sortedItems = try await fetchEvents()
        let startIndex: Int
        if let cursor,
           let cursorIndex = sortedItems.firstIndex(where: { $0.id == cursor.documentID }) {
            startIndex = sortedItems.index(after: cursorIndex)
        } else {
            startIndex = sortedItems.startIndex
        }

        let pageItems = Array(sortedItems.dropFirst(startIndex).prefix(max(1, limit)))
        let nextCursor = pageItems.last.map { EventPageCursor(endDate: $0.endDate, documentID: $0.id) }
        return EventPage(
            items: pageItems,
            nextCursor: nextCursor,
            hasMore: sortedItems.count > startIndex + pageItems.count
        )
    }

    func fetchEventsPage(
        limit: Int,
        after cursor: EventPageCursor?,
        federalState: AustrianFederalState?
    ) async throws -> EventPage {
        let sortedItems = try await fetchEvents()
            .filter {
                RegionVisibilityMatcher.isVisible(
                    regionScope: $0.regionScope,
                    federalState: $0.federalState,
                    selectedFederalState: federalState
                )
            }
            .sorted {
                $0.startDate == $1.startDate
                    ? $0.id < $1.id
                    : $0.startDate < $1.startDate
            }
        let startIndex: Int
        if let cursor,
           let cursorIndex = sortedItems.firstIndex(where: { $0.id == cursor.documentID }) {
            startIndex = sortedItems.index(after: cursorIndex)
        } else {
            startIndex = sortedItems.startIndex
        }

        let pageItems = Array(sortedItems.dropFirst(startIndex).prefix(max(1, limit)))
        let nextCursor = pageItems.last.map { EventPageCursor(endDate: $0.endDate, documentID: $0.id) }
        return EventPage(
            items: pageItems,
            nextCursor: nextCursor,
            hasMore: sortedItems.count > startIndex + pageItems.count
        )
    }

    func fetchRecentPastEvents(
        limit: Int,
        federalState: AustrianFederalState?
    ) async throws -> [Event] {
        []
    }

    func fetchOrganizationEvents(organizationID: String, limit: Int) async throws -> [Event] {
        Array(try await fetchEvents()
            .filter { $0.source.organizationId == organizationID }
            .prefix(max(1, limit)))
    }

    func fetchEventRecommendationCandidates(for source: Event, limit: Int) async throws -> [Event] {
        Array(try await fetchEvents()
            .filter { $0.id != source.id && $0.category == source.category }
            .prefix(min(max(1, limit), 12)))
    }
}

extension Event {
    func applyingRegistrationMutation(_ result: EventRegistrationMutationResult) -> Event {
        guard result.eventID == id else { return self }

        return Event(
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
            organizerName: organizerName,
            organizerURL: organizerURL,
            contactPhone: contactPhone,
            contactEmail: contactEmail,
            contactURL: contactURL,
            imageURL: imageURL,
            mediaMetadata: mediaMetadata,
            startDate: startDate,
            endDate: endDate,
            createdAt: createdAt,
            updatedAt: updatedAt,
            requiresRegistration: requiresRegistration,
            price: price,
            capacity: capacity,
            registeredCount: max(0, result.registeredCount),
            comments: comments,
            moderationStatus: moderationStatus,
            registrationState: result.registrationState,
            likeCount: likeCount,
            likeState: likeState,
            viewCount: viewCount,
            category: category,
            audience: audience,
            minimumAge: minimumAge,
            maximumAge: maximumAge,
            tags: tags,
            isAllDay: isAllDay,
            isBookmarked: isBookmarked,
            commentCount: commentCount,
            cancellationState: cancellationState,
            cancelledAt: cancelledAt,
            cancellationReason: cancellationReason
        )
    }
}

extension OrganizationRepository {
    func fetchAuthoringOrganizations(user: AppUser) async throws -> [Organization] {
        PermissionService.manageableOrganizations(from: try await fetchOrganizations(), user: user)
            .filter { $0.moderationStatus == .approved }
    }

    func fetchBookmarkedOrganizations() async throws -> [Organization] {
        try await fetchOrganizations().filter(\.isBookmarked)
    }

    func fetchSubscribedOrganizations() async throws -> [Organization] {
        try await fetchOrganizations().filter(\.isSubscribed)
    }

    func fetchOrganizationsPage(limit: Int, after cursor: OrganizationPageCursor?) async throws -> OrganizationPage {
        let sortedItems = try await fetchOrganizations()
        let startIndex: Int
        if let cursor,
           let cursorIndex = sortedItems.firstIndex(where: { $0.id == cursor.documentID }) {
            startIndex = sortedItems.index(after: cursorIndex)
        } else {
            startIndex = sortedItems.startIndex
        }

        let pageItems = Array(sortedItems.dropFirst(startIndex).prefix(max(1, limit)))
        let nextCursor = pageItems.last.map { OrganizationPageCursor(createdAt: $0.createdAt, documentID: $0.id) }
        return OrganizationPage(
            items: pageItems,
            nextCursor: nextCursor,
            hasMore: sortedItems.count > startIndex + pageItems.count
        )
    }

    func fetchOrganizationsPage(
        limit: Int,
        after cursor: OrganizationPageCursor?,
        federalState: AustrianFederalState?
    ) async throws -> OrganizationPage {
        let sortedItems = try await fetchOrganizations()
            .filter {
                RegionVisibilityMatcher.isVisible(
                    regionScope: $0.regionScope,
                    federalState: $0.federalState,
                    selectedFederalState: federalState
                )
            }
            .sorted {
                $0.createdAt == $1.createdAt
                    ? $0.id > $1.id
                    : $0.createdAt > $1.createdAt
            }
        let startIndex: Int
        if let cursor,
           let cursorIndex = sortedItems.firstIndex(where: { $0.id == cursor.documentID }) {
            startIndex = sortedItems.index(after: cursorIndex)
        } else {
            startIndex = sortedItems.startIndex
        }

        let pageItems = Array(sortedItems.dropFirst(startIndex).prefix(max(1, limit)))
        let nextCursor = pageItems.last.map { OrganizationPageCursor(createdAt: $0.createdAt, documentID: $0.id) }
        return OrganizationPage(
            items: pageItems,
            nextCursor: nextCursor,
            hasMore: sortedItems.count > startIndex + pageItems.count
        )
    }
}

protocol OrganizationPhotoRepository {
    func fetchPhotos(organizationId: String) async throws -> [OrganizationPhoto]
    func addPhoto(organizationId: String, imageData: Data, caption: String?, uploadedBy: String) async throws -> OrganizationPhoto
    func deletePhoto(_ photo: OrganizationPhoto) async throws
}
