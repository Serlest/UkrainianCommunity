import Foundation

actor MockRepositoryStore {
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
            acceptedTermsVersion: user.acceptedTermsVersion,
            acceptedPrivacyVersion: user.acceptedPrivacyVersion,
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
            sourceName: item.sourceName,
            sourceURL: item.sourceURL,
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
        guard isEditableGuideArticle(existingArticle) else {
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

    func deleteGuideArticle(id: String, editorId: String) throws {
        let trimmedId = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEditorId = editorId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty, !trimmedEditorId.isEmpty else { throw AppError.permissionDenied }
        guard let index = guideArticles.firstIndex(where: { $0.id == trimmedId }) else { throw AppError.notFound }
        guard isEditableGuideArticle(guideArticles[index]) else { throw AppError.validationFailed }
        guideArticles.remove(at: index)
    }

    private func isEditableGuideArticle(_ article: GuideArticle) -> Bool {
        guard article.archivedAt == nil else { return false }

        let isDraft = article.moderationStatus == .draft
            && (article.status == nil || article.status == .draft)
        let isPublished = article.moderationStatus == .approved
            && article.status == .published
        return isDraft || isPublished
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
            organizerName: events[index].organizerName,
            organizerURL: events[index].organizerURL,
            contactPhone: events[index].contactPhone,
            contactEmail: events[index].contactEmail,
            contactURL: events[index].contactURL,
            imageURL: events[index].imageURL,
            startDate: events[index].startDate,
            endDate: events[index].endDate,
            createdAt: events[index].createdAt,
            updatedAt: events[index].updatedAt,
            requiresRegistration: events[index].requiresRegistration,
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
            tags: events[index].tags,
            isAllDay: events[index].isAllDay,
            isBookmarked: events[index].isBookmarked,
            commentCount: events[index].commentCount
        )
    }

    func eventRegistrations(eventID: String) throws -> [EventRegistrationAttendee] {
        guard let event = events.first(where: { $0.id == eventID }) else { throw AppError.notFound }

        var attendees: [EventRegistrationAttendee] = []
        if event.registrationState == .registered {
            attendees.append(EventRegistrationAttendee(
                id: "mock_registration_\(eventID)_\(user.id)",
                eventID: eventID,
                userID: user.id,
                registeredAt: .now,
                displayName: user.displayName.isEmpty ? user.fullName : user.displayName,
                email: user.email,
                avatarURL: user.avatarURL
            ))
        }

        let remainingCount = max(0, event.registeredCount - attendees.count)
        attendees += (0..<remainingCount).map { index in
            EventRegistrationAttendee(
                id: "mock_registration_\(eventID)_participant_\(index + 1)",
                eventID: eventID,
                userID: "participant-\(index + 1)",
                registeredAt: nil,
                displayName: nil,
                email: nil,
                avatarURL: nil
            )
        }

        return attendees
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
            organizerName: item.organizerName,
            organizerURL: item.organizerURL,
            contactPhone: item.contactPhone,
            contactEmail: item.contactEmail,
            contactURL: item.contactURL,
            imageURL: item.imageURL,
            startDate: item.startDate,
            endDate: item.endDate,
            createdAt: existingItem.createdAt,
            updatedAt: item.updatedAt,
            requiresRegistration: item.requiresRegistration,
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
            tags: item.tags,
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
            telegramURL: item.telegramURL,
            donationURL: item.donationURL,
            facebookURL: item.facebookURL,
            instagramURL: item.instagramURL,
            whatsappURL: item.whatsappURL,
            youtubeURL: item.youtubeURL,
            linkedinURL: item.linkedinURL,
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
            sourceName: sourceName,
            sourceURL: sourceURL,
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
            facebookURL: facebookURL,
            instagramURL: instagramURL,
            whatsappURL: whatsappURL,
            youtubeURL: youtubeURL,
            linkedinURL: linkedinURL,
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
            organizerName: organizerName,
            organizerURL: organizerURL,
            contactPhone: contactPhone,
            contactEmail: contactEmail,
            contactURL: contactURL,
            imageURL: imageURL,
            startDate: startDate,
            endDate: endDate,
            createdAt: createdAt,
            updatedAt: Date(),
            requiresRegistration: requiresRegistration,
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
            tags: tags,
            isAllDay: isAllDay,
            isBookmarked: isBookmarked,
            commentCount: commentCount
        )
    }
}

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
