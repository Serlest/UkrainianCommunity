import Foundation

private actor MockRepositoryStore {
    static let shared = MockRepositoryStore()

    var user = MockContentBuilder.currentUser()
    var news = MockContentBuilder.newsPosts()
    var events = MockContentBuilder.events()
    var organizations = MockContentBuilder.organizations()
    var organizationComments: [String: [Comment]] = [:]
    var infoItems = MockContentBuilder.infoItems()
    var guideArticles = MockContentBuilder.guideArticles()
    var feedbackItems: [FeedbackItem] = []
    var feedbackMessages: [String: [FeedbackMessage]] = [:]
    var notificationPreferencesByUserID: [String: NotificationPreferences] = [:]
    var notificationsByUserID: [String: [AppNotification]] = [:]
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

    func notificationPreferences(userID: String) -> NotificationPreferences {
        notificationPreferencesByUserID[userID] ?? .default
    }

    func saveNotificationPreferences(_ preferences: NotificationPreferences, userID: String) {
        notificationPreferencesByUserID[userID] = NotificationPreferences(
            notificationsEnabled: preferences.notificationsEnabled,
            eventRemindersEnabled: preferences.eventRemindersEnabled,
            reminderLeadMinutes: preferences.reminderLeadMinutes,
            updatedAt: .now
        )
    }

    func notifications(userID: String, limit: Int) -> [AppNotification] {
        Array((notificationsByUserID[userID] ?? [])
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(max(1, limit)))
    }

    func unreadNotificationCount(userID: String) -> Int {
        (notificationsByUserID[userID] ?? []).filter { !$0.isRead }.count
    }

    func createNotification(_ notification: AppNotification, userID: String) {
        var notifications = notificationsByUserID[userID] ?? []
        notifications.removeAll { $0.id == notification.id }
        notifications.append(notification)
        notificationsByUserID[userID] = notifications
    }

    func markNotificationRead(userID: String, notificationID: String) {
        guard var notifications = notificationsByUserID[userID],
              let index = notifications.firstIndex(where: { $0.id == notificationID }) else { return }
        let notification = notifications[index]
        notifications[index] = AppNotification(
            id: notification.id,
            recipientUserId: notification.recipientUserId,
            type: notification.type,
            sourceType: notification.sourceType,
            sourceId: notification.sourceId,
            actorUserId: notification.actorUserId,
            actorDisplayName: notification.actorDisplayName,
            payload: notification.payload,
            isRead: true,
            readAt: .now,
            createdAt: notification.createdAt
        )
        notificationsByUserID[userID] = notifications
    }

    func markAllNotificationsRead(userID: String) {
        let notifications = (notificationsByUserID[userID] ?? []).map { notification in
            AppNotification(
                id: notification.id,
                recipientUserId: notification.recipientUserId,
                type: notification.type,
                sourceType: notification.sourceType,
                sourceId: notification.sourceId,
                actorUserId: notification.actorUserId,
                actorDisplayName: notification.actorDisplayName,
                payload: notification.payload,
                isRead: true,
                readAt: notification.readAt ?? .now,
                createdAt: notification.createdAt
            )
        }
        notificationsByUserID[userID] = notifications
    }

    func feedback() -> [FeedbackItem] {
        feedbackItems.sorted { $0.createdAt > $1.createdAt }
    }

    func feedback(userID: String) -> [FeedbackItem] {
        feedbackItems
            .filter { $0.userId == userID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func updateFeedbackStatus(id: String, status: FeedbackStatus) throws {
        guard let index = feedbackItems.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
        let item = feedbackItems[index]
        feedbackItems[index] = FeedbackItem(
            id: item.id,
            type: item.type,
            subject: item.subject,
            message: item.message,
            status: status,
            createdAt: item.createdAt,
            updatedAt: .now,
            userId: item.userId,
            userDisplayName: item.userDisplayName,
            ownerReply: item.ownerReply,
            repliedAt: item.repliedAt,
            repliedByUserId: item.repliedByUserId,
            lastMessageText: item.lastMessageText,
            lastMessageAt: item.lastMessageAt,
            lastMessageByUserId: item.lastMessageByUserId,
            lastMessageByRole: item.lastMessageByRole,
            unreadForOwner: item.unreadForOwner,
            unreadForUser: item.unreadForUser
        )
    }

    func replyToFeedback(id: String, reply: String, repliedByUserID: String) throws {
        guard let index = feedbackItems.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
        let item = feedbackItems[index]
        feedbackItems[index] = FeedbackItem(
            id: item.id,
            type: item.type,
            subject: item.subject,
            message: item.message,
            status: .answered,
            createdAt: item.createdAt,
            updatedAt: .now,
            userId: item.userId,
            userDisplayName: item.userDisplayName,
            ownerReply: reply,
            repliedAt: .now,
            repliedByUserId: repliedByUserID,
            lastMessageText: reply,
            lastMessageAt: .now,
            lastMessageByUserId: repliedByUserID,
            lastMessageByRole: .owner,
            unreadForOwner: false,
            unreadForUser: true
        )
    }

    func feedbackMessages(for item: FeedbackItem) -> [FeedbackMessage] {
        let storedMessages = feedbackMessages[item.id] ?? []
        var messages: [FeedbackMessage] = []
        if let initialMessage = item.legacyMessages.first,
           !storedMessages.contains(where: { $0.isStoredInitialMessage(for: item) }) {
            messages.append(initialMessage)
        }
        messages.append(contentsOf: storedMessages)
        if !storedMessages.contains(where: { $0.senderRole == .owner }),
           let legacyReply = item.legacyMessages.dropFirst().first {
            messages.append(legacyReply)
        }
        return messages.deduplicatedByID().sorted { $0.createdAt < $1.createdAt }
    }

    func addFeedbackMessage(feedback item: FeedbackItem, text: String, sender: AppUser, senderRole: FeedbackSenderRole) throws {
        guard let index = feedbackItems.firstIndex(where: { $0.id == item.id }) else { throw AppError.notFound }
        let now = Date()
        let message = FeedbackMessage(
            id: UUID().uuidString,
            feedbackId: item.id,
            senderId: sender.id,
            senderDisplayName: sender.displayName,
            senderRole: senderRole,
            text: text,
            createdAt: now,
            isSystem: false
        )
        feedbackMessages[item.id, default: []].append(message)

        let existing = feedbackItems[index]
        feedbackItems[index] = FeedbackItem(
            id: existing.id,
            type: existing.type,
            subject: existing.subject,
            message: existing.message,
            status: senderRole == .owner ? .answered : .open,
            createdAt: existing.createdAt,
            updatedAt: now,
            userId: existing.userId,
            userDisplayName: existing.userDisplayName,
            ownerReply: senderRole == .owner ? text : existing.ownerReply,
            repliedAt: senderRole == .owner ? now : existing.repliedAt,
            repliedByUserId: senderRole == .owner ? sender.id : existing.repliedByUserId,
            lastMessageText: text,
            lastMessageAt: now,
            lastMessageByUserId: sender.id,
            lastMessageByRole: senderRole,
            unreadForOwner: senderRole == .user,
            unreadForUser: senderRole == .owner
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

    func organizationNewsCount(organizationID: String) -> Int {
        news.filter {
            $0.source.sourceType == .organization
                && $0.source.organizationId == organizationID
                && [.pendingReview, .approved].contains($0.moderationStatus)
        }.count
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
        news[index].comments.upsertByID(comment)
        news[index].commentCount = news[index].comments.filter { !$0.isDeleted }.count
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

    func createGuideArticle(from draft: GuideArticleDraft, authorId: String) throws -> GuideArticle {
        let trimmedAuthorId = authorId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAuthorId.isEmpty else { throw AppError.permissionDenied }

        let article = try draft.makeGuideArticle(createdBy: trimmedAuthorId)
        guideArticles.insert(article, at: 0)
        return article
    }

    func draftGuideArticles() -> [GuideArticle] {
        guideArticles
            .filter { $0.moderationStatus == .draft }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func inReviewGuideArticles() -> [GuideArticle] {
        guideArticles
            .filter { $0.moderationStatus == .pendingReview && $0.status == .review }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func approvedGuideArticles() -> [GuideArticle] {
        guideArticles
            .filter { $0.moderationStatus == .approved && $0.status == .approved }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func updateGuideArticle(id: String, from draft: GuideArticleDraft, editorId: String) throws -> GuideArticle {
        let trimmedId = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEditorId = editorId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty, !trimmedEditorId.isEmpty else { throw AppError.permissionDenied }
        guard let index = guideArticles.firstIndex(where: { $0.id == trimmedId }) else { throw AppError.notFound }

        let existingArticle = guideArticles[index]
        guard existingArticle.moderationStatus == .draft,
              existingArticle.status == nil || existingArticle.status == .draft,
              existingArticle.archivedAt == nil else {
            throw AppError.validationFailed
        }

        let article = try draft.updatingGuideArticle(guideArticles[index], editorId: trimmedEditorId)
        guideArticles[index] = article
        return article
    }

    func submitGuideArticleForReview(id: String, submitterId: String) throws {
        let trimmedId = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSubmitterId = submitterId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty, !trimmedSubmitterId.isEmpty else { throw AppError.permissionDenied }
        guard let index = guideArticles.firstIndex(where: { $0.id == trimmedId }) else { throw AppError.notFound }

        let existingArticle = guideArticles[index]
        guard existingArticle.moderationStatus == .draft,
              existingArticle.status == nil || existingArticle.status == .draft,
              existingArticle.archivedAt == nil else {
            throw AppError.validationFailed
        }

        guideArticles[index] = GuideArticle(
            id: existingArticle.id,
            title: existingArticle.title,
            summary: existingArticle.summary,
            body: existingArticle.body,
            category: existingArticle.category,
            regionScope: existingArticle.regionScope,
            federalState: existingArticle.federalState,
            city: existingArticle.city,
            officialSourceURL: existingArticle.officialSourceURL,
            sourceName: existingArticle.sourceName,
            isPinned: existingArticle.isPinned,
            moderationStatus: .pendingReview,
            createdAt: existingArticle.createdAt,
            updatedAt: .now,
            contentType: existingArticle.contentType,
            status: .review,
            contentBlocks: existingArticle.contentBlocks,
            audience: existingArticle.audience,
            sourceLinks: existingArticle.sourceLinks,
            officialSourcesRequired: existingArticle.officialSourcesRequired,
            priority: existingArticle.priority,
            isFeatured: existingArticle.isFeatured,
            createdBy: existingArticle.createdBy,
            updatedBy: trimmedSubmitterId,
            reviewedBy: existingArticle.reviewedBy,
            publishedAt: existingArticle.publishedAt,
            lastReviewedAt: existingArticle.lastReviewedAt,
            nextReviewAt: existingArticle.nextReviewAt,
            reviewInterval: existingArticle.reviewInterval,
            archivedAt: existingArticle.archivedAt
        )
    }

    func approveGuideArticle(id: String, reviewerId: String) throws {
        let trimmedId = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReviewerId = reviewerId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty, !trimmedReviewerId.isEmpty else { throw AppError.permissionDenied }
        guard let index = guideArticles.firstIndex(where: { $0.id == trimmedId }) else { throw AppError.notFound }

        let existingArticle = guideArticles[index]
        guard existingArticle.moderationStatus == .pendingReview,
              existingArticle.status == .review,
              existingArticle.archivedAt == nil else {
            throw AppError.validationFailed
        }

        let reviewedAt = Date()
        guideArticles[index] = GuideArticle(
            id: existingArticle.id,
            title: existingArticle.title,
            summary: existingArticle.summary,
            body: existingArticle.body,
            category: existingArticle.category,
            regionScope: existingArticle.regionScope,
            federalState: existingArticle.federalState,
            city: existingArticle.city,
            officialSourceURL: existingArticle.officialSourceURL,
            sourceName: existingArticle.sourceName,
            isPinned: existingArticle.isPinned,
            moderationStatus: .approved,
            createdAt: existingArticle.createdAt,
            updatedAt: reviewedAt,
            contentType: existingArticle.contentType,
            status: .approved,
            contentBlocks: existingArticle.contentBlocks,
            audience: existingArticle.audience,
            sourceLinks: existingArticle.sourceLinks,
            officialSourcesRequired: existingArticle.officialSourcesRequired,
            priority: existingArticle.priority,
            isFeatured: existingArticle.isFeatured,
            createdBy: existingArticle.createdBy,
            updatedBy: trimmedReviewerId,
            reviewedBy: trimmedReviewerId,
            publishedAt: existingArticle.publishedAt,
            lastReviewedAt: reviewedAt,
            nextReviewAt: existingArticle.nextReviewAt,
            reviewInterval: existingArticle.reviewInterval,
            archivedAt: existingArticle.archivedAt
        )
    }

    func publishGuideArticle(id: String, publisherId: String) throws {
        let trimmedId = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPublisherId = publisherId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty, !trimmedPublisherId.isEmpty else { throw AppError.permissionDenied }
        guard let index = guideArticles.firstIndex(where: { $0.id == trimmedId }) else { throw AppError.notFound }

        let existingArticle = guideArticles[index]
        guard existingArticle.moderationStatus == .approved,
              existingArticle.status == .approved,
              existingArticle.archivedAt == nil else {
            throw AppError.validationFailed
        }

        let publishedAt = Date()
        let reviewInterval = existingArticle.reviewInterval ?? .normal
        let reviewIntervalMonths: Int
        switch reviewInterval {
        case .critical:
            reviewIntervalMonths = 3
        case .normal:
            reviewIntervalMonths = 6
        case .stable:
            reviewIntervalMonths = 12
        }
        let nextReviewAt = Calendar.current.date(
            byAdding: .month,
            value: reviewIntervalMonths,
            to: publishedAt
        ) ?? publishedAt

        guideArticles[index] = GuideArticle(
            id: existingArticle.id,
            title: existingArticle.title,
            summary: existingArticle.summary,
            body: existingArticle.body,
            category: existingArticle.category,
            regionScope: existingArticle.regionScope,
            federalState: existingArticle.federalState,
            city: existingArticle.city,
            officialSourceURL: existingArticle.officialSourceURL,
            sourceName: existingArticle.sourceName,
            isPinned: existingArticle.isPinned,
            moderationStatus: .approved,
            createdAt: existingArticle.createdAt,
            updatedAt: publishedAt,
            contentType: existingArticle.contentType,
            status: .published,
            contentBlocks: existingArticle.contentBlocks,
            audience: existingArticle.audience,
            sourceLinks: existingArticle.sourceLinks,
            officialSourcesRequired: existingArticle.officialSourcesRequired,
            priority: existingArticle.priority,
            isFeatured: existingArticle.isFeatured,
            createdBy: existingArticle.createdBy,
            updatedBy: trimmedPublisherId,
            reviewedBy: existingArticle.reviewedBy,
            publishedAt: publishedAt,
            lastReviewedAt: publishedAt,
            nextReviewAt: nextReviewAt,
            reviewInterval: existingArticle.reviewInterval,
            archivedAt: existingArticle.archivedAt
        )
    }

    func archiveGuideArticle(id: String, editorId: String) throws {
        let trimmedId = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEditorId = editorId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty, !trimmedEditorId.isEmpty else { throw AppError.permissionDenied }
        guard let index = guideArticles.firstIndex(where: { $0.id == trimmedId }) else { throw AppError.notFound }

        let existingArticle = guideArticles[index]
        guard existingArticle.moderationStatus == .draft,
              existingArticle.status == nil || existingArticle.status == .draft,
              existingArticle.archivedAt == nil else {
            throw AppError.validationFailed
        }

        guideArticles[index] = existingArticle.archivedBy(editorId: trimmedEditorId)
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

    func organizationEventCount(organizationID: String) -> Int {
        events.filter {
            $0.source.sourceType == .organization
                && $0.source.organizationId == organizationID
                && [.pendingReview, .approved].contains($0.moderationStatus)
        }.count
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
        events[index].comments.upsertByID(comment)
        events[index].commentCount = events[index].comments.filter { !$0.isDeleted }.count
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
        organizations[index].likeCount = max(0, organizations[index].likeCount + (isLiked ? 1 : -1))
    }

    func toggleOrganizationSubscription(id: String, isSubscribed: Bool) throws {
        guard let index = organizations.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
        organizations[index].isSubscribed = isSubscribed
        organizations[index].subscriberCount = max(0, organizations[index].subscriberCount + (isSubscribed ? 1 : -1))
    }

    func organizationSubscriberPage(organizationID: String, limit: Int, after cursor: OrganizationSubscriberCursor?) throws -> OrganizationSubscriberPage {
        guard organizations.contains(where: { $0.id == organizationID }) else { throw AppError.notFound }
        return OrganizationSubscriberPage(items: [], nextCursor: nil, hasMore: false)
    }

    func organizationComments(organizationID: String) throws -> [Comment] {
        guard organizations.contains(where: { $0.id == organizationID }) else { throw AppError.notFound }
        return (organizationComments[organizationID] ?? []).filter { !$0.isDeleted }
    }

    func addOrganizationComment(organizationID: String, text: String, author: AppUser) throws -> Comment {
        guard organizations.contains(where: { $0.id == organizationID }) else { throw AppError.notFound }
        let comment = Comment(
            id: UUID().uuidString,
            parentType: .organization,
            parentId: organizationID,
            authorId: author.id,
            authorName: author.commentDisplayName,
            authorPhotoURL: author.avatarURL?.absoluteString,
            text: String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1000)),
            createdAt: .now
        )
        organizationComments[organizationID, default: []].upsertByID(comment)
        return comment
    }

    func updateOrganizationComment(organizationID: String, commentID: String, text: String) throws -> Comment {
        guard var comments = organizationComments[organizationID],
              let index = comments.firstIndex(where: { $0.id == commentID }) else {
            throw AppError.notFound
        }
        let existing = comments[index]
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
        comments[index] = updated
        organizationComments[organizationID] = comments
        return updated
    }

    func deleteOrganizationComment(organizationID: String, commentID: String) throws {
        guard var comments = organizationComments[organizationID] else { throw AppError.notFound }
        comments.removeAll { $0.id == commentID }
        organizationComments[organizationID] = comments
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

    func organizationRequests(submittedByUserID: String) -> [Organization] {
        organizations
            .filter {
                $0.submittedByUserId == submittedByUserID
                    && $0.moderationStatus != .approved
            }
            .sorted { ($0.submittedAt ?? $0.createdAt) > ($1.submittedAt ?? $1.createdAt) }
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
            submittedByUserId: item.submittedByUserId,
            submittedByDisplayName: item.submittedByDisplayName,
            submittedAt: item.submittedAt,
            reviewMessage: item.reviewMessage,
            reviewedByUserId: item.reviewedByUserId,
            reviewedAt: item.reviewedAt,
            rejectionReason: item.rejectionReason,
            createdAt: existingItem.createdAt,
            updatedAt: item.updatedAt,
            moderationStatus: item.moderationStatus,
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

    func approveOrganizationRequest(id: String, reviewerID: String) throws {
        guard let index = organizations.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
        guard let submittedByUserId = organizations[index].submittedByUserId else { throw AppError.validationFailed }
        organizations[index].moderationStatus = .approved
        organizations[index] = organizations[index].updatingReview(
            ownerId: submittedByUserId,
            status: .approved,
            reviewMessage: nil,
            reviewedByUserId: reviewerID,
            rejectionReason: nil
        )
    }

    func requestOrganizationRevision(id: String, message: String, reviewerID: String) throws {
        guard let index = organizations.firstIndex(where: { $0.id == id }) else { throw AppError.notFound }
        organizations[index] = organizations[index].updatingReview(
            status: .needsRevision,
            reviewMessage: message,
            reviewedByUserId: reviewerID,
            rejectionReason: nil
        )
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

    func deleteAccount(currentUser: AppUser) async throws {
    }
}

struct MockNotificationPreferencesRepository: NotificationPreferencesRepository {
    private let store = MockRepositoryStore.shared

    func fetchNotificationPreferences(userID: String) async throws -> NotificationPreferences {
        await store.notificationPreferences(userID: userID)
    }

    func saveNotificationPreferences(_ preferences: NotificationPreferences, userID: String) async throws {
        await store.saveNotificationPreferences(preferences, userID: userID)
    }
}

private struct MockRealtimeListener: AppRealtimeListener {
    func cancel() {}
}

struct MockNotificationInboxRepository: NotificationInboxRepository {
    private let store = MockRepositoryStore.shared

    func fetchNotifications(userID: String, limit: Int) async throws -> [AppNotification] {
        await store.notifications(userID: userID, limit: limit)
    }

    func listenNotifications(
        userID: String,
        limit: Int,
        onChange: @escaping @MainActor ([AppNotification]) -> Void
    ) -> AppRealtimeListener {
        Task {
            let notifications = await store.notifications(userID: userID, limit: limit)
            await MainActor.run {
                onChange(notifications)
            }
        }
        return MockRealtimeListener()
    }

    func fetchUnreadCount(userID: String) async throws -> Int {
        await store.unreadNotificationCount(userID: userID)
    }

    func markNotificationRead(userID: String, notificationID: String) async throws {
        await store.markNotificationRead(userID: userID, notificationID: notificationID)
    }

    func markAllNotificationsRead(userID: String) async throws {
        await store.markAllNotificationsRead(userID: userID)
    }

    func createNotification(userID: String, notification: AppNotification) async throws {
        await store.createNotification(notification, userID: userID)
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

    func fetchFeedback(userID: String) async throws -> [FeedbackItem] {
        await store.feedback(userID: userID)
    }

    func fetchFeedbackMessages(feedback: FeedbackItem) async throws -> [FeedbackMessage] {
        await store.feedbackMessages(for: feedback)
    }

    func sendUserFeedbackMessage(feedback: FeedbackItem, text: String, user: AppUser) async throws {
        try await store.addFeedbackMessage(feedback: feedback, text: text, sender: user, senderRole: .user)
    }

    func sendOwnerFeedbackReply(feedback: FeedbackItem, text: String, owner: AppUser) async throws {
        try await store.addFeedbackMessage(feedback: feedback, text: text, sender: owner, senderRole: .owner)
    }

    func updateFeedbackStatus(id: String, status: FeedbackStatus) async throws {
        try await store.updateFeedbackStatus(id: id, status: status)
    }

    func replyToFeedback(id: String, reply: String, repliedByUserID: String) async throws {
        try await store.replyToFeedback(id: id, reply: reply, repliedByUserID: repliedByUserID)
    }

    func closeFeedback(id: String) async throws {
        try await store.updateFeedbackStatus(id: id, status: .closed)
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

    func fetchOrganizationNewsCount(organizationID: String) async throws -> Int {
        await store.organizationNewsCount(organizationID: organizationID)
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

    func fetchOrganizationEventCount(organizationID: String) async throws -> Int {
        await store.organizationEventCount(organizationID: organizationID)
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

    func fetchOrganizationRequests(submittedByUserID: String) async throws -> [Organization] {
        await store.organizationRequests(submittedByUserID: submittedByUserID)
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
        URL(string: "https://example.com/organizations/\(organizationID)/logo.jpg")!
    }

    func likeOrganization(id: String) async throws {
        try await store.toggleOrganizationLike(id: id, isLiked: true)
    }

    func unlikeOrganization(id: String) async throws {
        try await store.toggleOrganizationLike(id: id, isLiked: false)
    }

    func subscribeOrganization(id: String) async throws {
        try await store.toggleOrganizationSubscription(id: id, isSubscribed: true)
    }

    func unsubscribeOrganization(id: String) async throws {
        try await store.toggleOrganizationSubscription(id: id, isSubscribed: false)
    }

    func fetchOrganizationSubscriberPage(
        organizationID: String,
        limit: Int,
        after cursor: OrganizationSubscriberCursor?
    ) async throws -> OrganizationSubscriberPage {
        try await store.organizationSubscriberPage(organizationID: organizationID, limit: limit, after: cursor)
    }

    func fetchPublicUserProfiles(userIDs: [String]) async throws -> [PublicUserProfile] {
        []
    }

    func fetchOrganizationComments(organizationID: String) async throws -> [Comment] {
        try await store.organizationComments(organizationID: organizationID)
    }

    func addOrganizationComment(organizationID: String, text: String, author: AppUser) async throws -> Comment {
        try await store.addOrganizationComment(organizationID: organizationID, text: text, author: author)
    }

    func updateOrganizationComment(organizationID: String, commentID: String, text: String) async throws -> Comment {
        try await store.updateOrganizationComment(organizationID: organizationID, commentID: commentID, text: text)
    }

    func deleteOrganizationComment(organizationID: String, commentID: String) async throws {
        try await store.deleteOrganizationComment(organizationID: organizationID, commentID: commentID)
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

    func approveOrganizationRequest(id: String, reviewerID: String) async throws {
        try await store.approveOrganizationRequest(id: id, reviewerID: reviewerID)
    }

    func requestOrganizationRevision(id: String, message: String, reviewerID: String) async throws {
        try await store.requestOrganizationRevision(id: id, message: message, reviewerID: reviewerID)
    }

    func rejectOrganizationRequest(id: String, reason: String, reviewerID: String) async throws {
        try await store.deleteOrganization(id: id)
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

private extension Organization {
    nonisolated func updatingReview(
        ownerId: String? = nil,
        status: ModerationStatus,
        reviewMessage: String?,
        reviewedByUserId: String,
        rejectionReason: String?
    ) -> Organization {
        Organization(
            id: id,
            name: name,
            description: description,
            shortDescription: shortDescription,
            fullDescription: fullDescription,
            regionScope: regionScope,
            federalState: federalState,
            city: city,
            imageURL: imageURL,
            logoURL: logoURL,
            coverURL: coverURL,
            contactEmail: contactEmail,
            email: email,
            phone: phone,
            website: website,
            address: address,
            latitude: latitude,
            longitude: longitude,
            organizationType: organizationType,
            foundedYear: foundedYear,
            foundedMonth: foundedMonth,
            languages: languages,
            socialLinks: socialLinks,
            telegramURL: telegramURL,
            donationURL: donationURL,
            missionStatement: missionStatement,
            contactPerson: contactPerson,
            subscriberCount: subscriberCount,
            eventsHeldCount: eventsHeldCount,
            volunteersCount: volunteersCount,
            helpedPeopleCount: helpedPeopleCount,
            ownerId: ownerId ?? self.ownerId,
            adminIds: adminIds,
            moderatorIds: moderatorIds,
            isSystemManaged: isSystemManaged,
            sourceType: sourceType,
            pinnedNewsId: pinnedNewsId,
            pinnedEventId: pinnedEventId,
            submittedByUserId: submittedByUserId,
            submittedByDisplayName: submittedByDisplayName,
            submittedAt: submittedAt,
            reviewMessage: reviewMessage,
            reviewedByUserId: reviewedByUserId,
            reviewedAt: .now,
            rejectionReason: rejectionReason,
            createdAt: createdAt,
            updatedAt: .now,
            moderationStatus: status,
            likeCount: likeCount,
            likeState: likeState,
            isSubscribed: isSubscribed,
            isBookmarked: isBookmarked
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

struct MockGuideRepository: GuideRepository {
    private let store = MockRepositoryStore.shared

    func fetchGuideArticles() async throws -> [GuideArticle] {
        await store.guideArticles
            .filter { $0.moderationStatus == .approved && $0.status == .published }
            .sorted { lhs, rhs in
                if lhs.isPinned == rhs.isPinned {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.isPinned && !rhs.isPinned
            }
    }

    func fetchDraftGuideArticles() async throws -> [GuideArticle] {
        await store.draftGuideArticles()
    }

    func fetchInReviewGuideArticles() async throws -> [GuideArticle] {
        await store.inReviewGuideArticles()
    }

    func fetchApprovedGuideArticles() async throws -> [GuideArticle] {
        await store.approvedGuideArticles()
    }

    func createGuideArticle(from draft: GuideArticleDraft, authorId: String) async throws -> GuideArticle {
        try await store.createGuideArticle(from: draft, authorId: authorId)
    }

    func updateGuideArticle(id: String, from draft: GuideArticleDraft, editorId: String) async throws -> GuideArticle {
        try await store.updateGuideArticle(id: id, from: draft, editorId: editorId)
    }

    func submitGuideArticleForReview(id: String, submitterId: String) async throws {
        try await store.submitGuideArticleForReview(id: id, submitterId: submitterId)
    }

    func approveGuideArticle(id: String, reviewerId: String) async throws {
        try await store.approveGuideArticle(id: id, reviewerId: reviewerId)
    }

    func publishGuideArticle(id: String, publisherId: String) async throws {
        try await store.publishGuideArticle(id: id, publisherId: publisherId)
    }

    func archiveGuideArticle(id: String, editorId: String) async throws {
        try await store.archiveGuideArticle(id: id, editorId: editorId)
    }
}

typealias MockInfoRepository = MockGuideRepository

private extension AppUser {
    nonisolated var commentDisplayName: String {
        let display = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !display.isEmpty { return display }
        let full = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        return full.isEmpty ? "User" : full
    }
}

private extension Array where Element == Comment {
    nonisolated mutating func upsertByID(_ comment: Comment) {
        if let index = firstIndex(where: { $0.id == comment.id }) {
            self[index] = comment
        } else {
            append(comment)
        }
    }
}

private extension Array where Element == FeedbackMessage {
    nonisolated func deduplicatedByID() -> [FeedbackMessage] {
        var seenIDs = Set<String>()
        return filter { message in
            seenIDs.insert(message.id).inserted
        }
    }
}

private extension FeedbackMessage {
    nonisolated func isStoredInitialMessage(for feedback: FeedbackItem) -> Bool {
        senderRole == .user
            && senderId == feedback.userId
            && text == feedback.message
            && abs(createdAt.timeIntervalSince(feedback.createdAt)) < 2
    }
}
