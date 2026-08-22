import Combine
import Foundation

@MainActor
final class OrganizationsViewModel: ObservableObject {
    @Published var organizations: [Organization]
    @Published private(set) var isLoading: Bool
    @Published private(set) var error: AppError?
    @Published private(set) var isLoadingNextPage = false
    @Published private(set) var hasMorePages = false
    @Published private(set) var contentVersion = 0
    @Published private(set) var pendingOrganizationLikeIDs = Set<String>()
    @Published private(set) var pendingOrganizationSubscriptionIDs = Set<String>()
    @Published private(set) var pendingOrganizationBookmarkIDs = Set<String>()
    @Published private(set) var pendingOrganizationDeleteIDs = Set<String>()
    @Published private(set) var organizationRequests: [Organization] = []
    @Published private(set) var organizationCommentsByID: [String: [Comment]] = [:]
    @Published private(set) var pendingOrganizationCommentIDs = Set<String>()
    @Published private(set) var isSavingOrganization = false
    @Published private(set) var isUploadingOrganizationImage = false
    @Published private(set) var validationErrorMessage: String?
    private let repository: OrganizationRepository
    private let notificationInboxRepository: NotificationInboxRepository?
    private let analyticsService: AnalyticsTracking
    private let listenerBag = RealtimeListenerBag()
    private var loadTask: Task<Void, Never>?
    private var nextPageTask: Task<Void, Never>?
    private var hasLoaded = false
    private var lastLoadedAt: Date?
    private var nextPageCursor: OrganizationPageCursor?
    private var trackedOrganizationViewIDs = Set<String>()

    init(
        repository: OrganizationRepository,
        notificationInboxRepository: NotificationInboxRepository? = nil,
        analyticsService: AnalyticsTracking = NoopAnalyticsService()
    ) {
        self.repository = repository
        self.notificationInboxRepository = notificationInboxRepository
        self.analyticsService = analyticsService
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

    func refreshIfStale(maxAge: TimeInterval = organizationRefreshStaleInterval) async {
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

    func resetForAuthChange() {
        loadTask?.cancel()
        nextPageTask?.cancel()
        loadTask = nil
        nextPageTask = nil
        organizations = []
        isLoading = false
        isLoadingNextPage = false
        hasMorePages = false
        error = nil
        contentVersion &+= 1
        pendingOrganizationLikeIDs = []
        pendingOrganizationSubscriptionIDs = []
        pendingOrganizationBookmarkIDs = []
        pendingOrganizationDeleteIDs = []
        trackedOrganizationViewIDs = []
        organizationRequests = []
        organizationCommentsByID = [:]
        pendingOrganizationCommentIDs = []
        listenerBag.removeAll()
        isSavingOrganization = false
        isUploadingOrganizationImage = false
        validationErrorMessage = nil
        hasLoaded = false
        lastLoadedAt = nil
        nextPageCursor = nil
    }

    func toggleLike(for organizationID: String) {
        guard let index = organizations.firstIndex(where: { $0.id == organizationID }) else { return }
        guard !pendingOrganizationLikeIDs.contains(organizationID) else { return }
        let shouldLike = organizations[index].likeState == .notLiked
        let previousLikeState = organizations[index].likeState
        let previousLikeCount = organizations[index].likeCount

        organizations[index].likeState = shouldLike ? .liked : .notLiked
        organizations[index].likeCount = max(0, previousLikeCount + (shouldLike ? 1 : -1))
        contentVersion &+= 1

        Task {
            pendingOrganizationLikeIDs.insert(organizationID)
            defer { pendingOrganizationLikeIDs.remove(organizationID) }

            do {
                if shouldLike {
                    try await repository.likeOrganization(id: organizationID)
                } else {
                    try await repository.unlikeOrganization(id: organizationID)
                }

                error = nil
            } catch let appError as AppError {
                organizations[index].likeState = previousLikeState
                organizations[index].likeCount = previousLikeCount
                contentVersion &+= 1
                error = appError
            } catch {
                organizations[index].likeState = previousLikeState
                organizations[index].likeCount = previousLikeCount
                contentVersion &+= 1
                self.error = .unknown
            }
        }
    }

    func toggleSubscription(for organizationID: String) {
        guard let index = organizations.firstIndex(where: { $0.id == organizationID }) else { return }
        guard !pendingOrganizationSubscriptionIDs.contains(organizationID) else { return }
        let shouldSubscribe = !organizations[index].isSubscribed
        let organization = organizations[index]
        let previousSubscriptionState = organizations[index].isSubscribed
        let previousSubscriberCount = organizations[index].subscriberCount

        pendingOrganizationSubscriptionIDs.insert(organizationID)
        organizations[index].isSubscribed = shouldSubscribe
        organizations[index].subscriberCount = max(0, previousSubscriberCount + (shouldSubscribe ? 1 : -1))
        contentVersion &+= 1

        Task {
            defer { pendingOrganizationSubscriptionIDs.remove(organizationID) }

            do {
                if shouldSubscribe {
                    try await repository.subscribeOrganization(id: organizationID)
                } else {
                    try await repository.unsubscribeOrganization(id: organizationID)
                }

                ActivityLogRecorder.recordOrganization(organization, actionType: shouldSubscribe ? .followedOrganization : .unfollowedOrganization)
                analyticsService.track(shouldSubscribe ? .organizationFollow(organization: organization) : .organizationUnfollow(organization: organization))
                error = nil
            } catch let appError as AppError {
                organizations[index].isSubscribed = previousSubscriptionState
                organizations[index].subscriberCount = previousSubscriberCount
                contentVersion &+= 1
                error = appError
            } catch {
                organizations[index].isSubscribed = previousSubscriptionState
                organizations[index].subscriberCount = previousSubscriberCount
                contentVersion &+= 1
                self.error = .unknown
            }
        }
    }

    func toggleBookmark(for organizationID: String) {
        guard let index = organizations.firstIndex(where: { $0.id == organizationID }) else { return }
        guard !pendingOrganizationBookmarkIDs.contains(organizationID) else { return }
        let shouldBookmark = !organizations[index].isBookmarked
        let organization = organizations[index]
        let previousBookmarkState = organizations[index].isBookmarked

        pendingOrganizationBookmarkIDs.insert(organizationID)
        organizations[index].isBookmarked = shouldBookmark
        contentVersion &+= 1

        Task {
            defer { pendingOrganizationBookmarkIDs.remove(organizationID) }

            do {
                if shouldBookmark {
                    try await repository.bookmarkOrganization(id: organizationID)
                } else {
                    try await repository.unbookmarkOrganization(id: organizationID)
                }

                ActivityLogRecorder.recordOrganization(organization, actionType: shouldBookmark ? .savedOrganization : .unsavedOrganization)
                if shouldBookmark {
                    analyticsService.track(.organizationBookmark(organization: organization))
                }
                error = nil
            } catch let appError as AppError {
                organizations[index].isBookmarked = previousBookmarkState
                contentVersion &+= 1
                error = appError
            } catch {
                organizations[index].isBookmarked = previousBookmarkState
                contentVersion &+= 1
                self.error = .unknown
            }
        }
    }

    func organization(for organizationID: String) -> Organization? {
        return organizations.first(where: { $0.id == organizationID })
    }

    func trackViewIfNeeded(for organization: Organization, sourceScreen: String = "organization_detail") {
        guard !trackedOrganizationViewIDs.contains(organization.id) else { return }
        trackedOrganizationViewIDs.insert(organization.id)
        analyticsService.track(.organizationView(
            organizationID: organization.id,
            organizationName: organization.name,
            federalState: organization.federalState,
            regionScope: organization.regionScope,
            sourceScreen: sourceScreen
        ))
    }

    func resolveOrganization(id organizationID: String) async -> Organization? {
        let trimmedID = organizationID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { return nil }

        if let organization = organization(for: trimmedID) {
            return organization
        }

        do {
            let organization = try await repository.fetchOrganization(id: trimmedID)
            organizations.upsertOrganizationByID(organization)
            contentVersion &+= 1
            error = nil
            return organization
        } catch let appError as AppError {
            error = appError
            return nil
        } catch {
            self.error = .unknown
            return nil
        }
    }

    func comments(for organizationID: String) -> [Comment] {
        organizationCommentsByID[organizationID] ?? []
    }

    func loadComments(for organizationID: String, forceRefresh: Bool = false) async {
        startListeningComments(for: organizationID)
        guard forceRefresh || !(repository is OrganizationRealtimeRepository) else { return }
        do {
            organizationCommentsByID[organizationID] = try await repository.fetchOrganizationComments(organizationID: organizationID).deduplicatedCommentsByID()
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    func stopListeningComments(for organizationID: String) {
        listenerBag.remove("organizationComments:\(organizationID)")
    }

    private func startListeningComments(for organizationID: String) {
        let key = "organizationComments:\(organizationID)"
        guard !listenerBag.contains(key),
              let realtimeRepository = repository as? OrganizationRealtimeRepository else { return }

        listenerBag.set(realtimeRepository.listenOrganizationComments(organizationID: organizationID) { [weak self] comments in
            self?.organizationCommentsByID[organizationID] = comments.deduplicatedCommentsByID()
            self?.error = nil
        } onError: { [weak self] appError in
            self?.listenerBag.remove(key)
            self?.error = appError
            #if DEBUG
            print("Realtime listener failed: purpose=organizationComments key=\(key) error=\(appError)")
            #endif
        }, for: key)
    }

    func addComment(to organizationID: String, text: String, author: AppUser) async {
        guard !pendingOrganizationCommentIDs.contains(organizationID) else { return }
        pendingOrganizationCommentIDs.insert(organizationID)
        defer { pendingOrganizationCommentIDs.remove(organizationID) }

        do {
            let comment = try await repository.addOrganizationComment(organizationID: organizationID, text: text, author: author)
            organizationCommentsByID[organizationID, default: []].upsertCommentByID(comment)
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    func updateComment(organizationID: String, commentID: String, text: String) async {
        guard !pendingOrganizationCommentIDs.contains(organizationID) else { return }
        pendingOrganizationCommentIDs.insert(organizationID)
        defer { pendingOrganizationCommentIDs.remove(organizationID) }

        do {
            let updated = try await repository.updateOrganizationComment(organizationID: organizationID, commentID: commentID, text: text)
            if let index = organizationCommentsByID[organizationID]?.firstIndex(where: { $0.id == commentID }) {
                organizationCommentsByID[organizationID]?[index] = updated
                organizationCommentsByID[organizationID] = organizationCommentsByID[organizationID]?.deduplicatedCommentsByID()
            }
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    func deleteComment(organizationID: String, commentID: String) async {
        guard !pendingOrganizationCommentIDs.contains(organizationID) else { return }
        pendingOrganizationCommentIDs.insert(organizationID)
        defer { pendingOrganizationCommentIDs.remove(organizationID) }

        do {
            try await repository.deleteOrganizationComment(organizationID: organizationID, commentID: commentID)
            organizationCommentsByID[organizationID]?.removeAll { $0.id == commentID }
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
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

    func loadOrganizationRequests(for user: AppUser?) async {
        guard let user else {
            organizationRequests = []
            listenerBag.removeAll(matchingPrefix: "submittedOrganizationRequests:")
            return
        }

        if startListeningOrganizationRequests(for: user.id) {
            return
        }

        await fetchOrganizationRequestsOnce(userID: user.id)
    }

    private func fetchOrganizationRequestsOnce(userID: String) async {
        do {
            organizationRequests = try await repository.fetchOrganizationRequests(submittedByUserID: userID).deduplicatedOrganizationsByID()
            error = nil
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown
        }
    }

    private func startListeningOrganizationRequests(for userID: String) -> Bool {
        let key = "submittedOrganizationRequests:\(userID)"
        listenerBag.removeAll(except: key, matchingPrefix: "submittedOrganizationRequests:")
        guard let realtimeRepository = repository as? OrganizationRealtimeRepository else { return false }
        guard !listenerBag.contains(key) else { return true }

        listenerBag.set(realtimeRepository.listenSubmittedOrganizationRequests(userID: userID) { [weak self] requests in
            self?.organizationRequests = requests.deduplicatedOrganizationsByID()
            self?.error = nil
        } onError: { [weak self] appError in
            self?.listenerBag.remove(key)
            self?.error = appError
            Task { await self?.fetchOrganizationRequestsOnce(userID: userID) }
            #if DEBUG
            print("Realtime listener failed: purpose=submittedOrganizationRequests key=\(key) error=\(appError)")
            #endif
        }, for: key)
        return true
    }

    func updateOrganization(
        _ organization: Organization,
        imageData: Data?,
        user: AppUser?
    ) async throws {
        guard PermissionService.canEditOrganizationInfo(organization, user: user) else {
            validationErrorMessage = AppStrings.Organizations.actionPermissionError
            throw AppError.permissionDenied
        }

        try await saveOrganization(organization, imageData: imageData, isEditing: true)
    }

    func deleteOrganization(id: String, user: AppUser?) async throws {
        guard id != Organization.systemOrganizationID else {
            validationErrorMessage = AppStrings.Organizations.actionPermissionError
            throw AppError.permissionDenied
        }
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
            removeDeletedOrganization(id: id)
            organizationRequests.removeAll { $0.id == id }
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
        guard id != Organization.systemOrganizationID else { return }
        organizations.removeAll { $0.id == id }
        contentVersion &+= 1
    }

    private func startLoad(force: Bool) async {
        guard force || !hasLoaded else { return }
        if force {
            nextPageTask?.cancel()
            nextPageTask = nil
            isLoadingNextPage = false
        }

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

    func loadNextPageIfNeeded(currentItemID: String? = nil) async {
        guard hasLoaded, hasMorePages, !isLoading, !isLoadingNextPage else { return }
        if let currentItemID, organizations.suffix(5).contains(where: { $0.id == currentItemID }) == false {
            return
        }

        if let nextPageTask {
            await nextPageTask.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoadNextPage()
        }
        nextPageTask = task
        await task.value
        nextPageTask = nil
    }

    private func performLoad() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let page = try await repository.fetchOrganizationsPage(limit: publicFeedPageSize, after: nil)
            guard !Task.isCancelled else { return }
            organizations = page.items
            nextPageCursor = page.nextCursor
            hasMorePages = page.hasMore
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

    private func performLoadNextPage() async {
        guard let nextPageCursor else { return }
        isLoadingNextPage = true
        defer { isLoadingNextPage = false }

        do {
            let page = try await repository.fetchOrganizationsPage(limit: publicFeedPageSize, after: nextPageCursor)
            guard !Task.isCancelled else { return }
            appendUniqueOrganizations(page.items)
            self.nextPageCursor = page.nextCursor
            hasMorePages = page.hasMore
            contentVersion &+= 1
            error = nil
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

    private func appendUniqueOrganizations(_ newOrganizations: [Organization]) {
        let existingIDs = Set(organizations.map(\.id))
        organizations.append(contentsOf: newOrganizations.filter { !existingIDs.contains($0.id) })
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
            if isEditing {
                try await ensureOrganizationRequestIsStillEditable(organization)
            }

            if !isEditing && organization.moderationStatus != .approved {
                try await repository.createOrganization(organization)
                var organizationToInsert = organization

                if let imageData {
                    do {
                        isUploadingOrganizationImage = true
                        let uploadedURL = try await repository.uploadOrganizationImage(data: imageData, organizationID: organization.id)
                        isUploadingOrganizationImage = false
                        organizationToInsert = organization.settingOrganizationImageURL(uploadedURL.absoluteString)
                        try await repository.updateOrganization(organizationToInsert)
                    } catch {
                        isUploadingOrganizationImage = false
                        do {
                            try await repository.deleteOrganization(id: organization.id)
                        } catch {}
                        throw error
                    }
                }

                organizationRequests.upsertOrganizationByID(organizationToInsert)
                contentVersion &+= 1
                error = nil
                AppContentChangeBus.postOrganizationsChanged(organizationID: organizationToInsert.id)
                return
            }

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
                shortDescription: organization.shortDescription,
                fullDescription: organization.fullDescription,
                regionScope: organization.regionScope,
                federalState: organization.federalState,
                city: organization.city,
                imageURL: resolvedImageURL,
                logoURL: resolvedImageURL ?? organization.logoURL,
                coverURL: organization.coverURL,
                contactEmail: organization.contactEmail,
                email: organization.email,
                phone: organization.phone,
                website: organization.website,
                address: organization.address,
                latitude: organization.latitude,
                longitude: organization.longitude,
                organizationType: organization.organizationType,
                foundedYear: organization.foundedYear,
                foundedMonth: organization.foundedMonth,
                languages: organization.languages,
                socialLinks: organization.socialLinks,
                telegramURL: organization.telegramURL,
                donationURL: organization.donationURL,
                facebookURL: organization.facebookURL,
                instagramURL: organization.instagramURL,
                whatsappURL: organization.whatsappURL,
                youtubeURL: organization.youtubeURL,
                linkedinURL: organization.linkedinURL,
                missionStatement: organization.missionStatement,
                contactPerson: organization.contactPerson,
                subscriberCount: organization.subscriberCount,
                eventsHeldCount: organization.eventsHeldCount,
                volunteersCount: organization.volunteersCount,
                helpedPeopleCount: organization.helpedPeopleCount,
                ownerId: organization.ownerId,
                adminIds: organization.adminIds,
                moderatorIds: organization.moderatorIds,
                isSystemManaged: organization.isSystemManaged,
                sourceType: organization.sourceType,
                pinnedNewsId: organization.pinnedNewsId,
                pinnedEventId: organization.pinnedEventId,
                submittedByUserId: organization.submittedByUserId,
                submittedByDisplayName: organization.submittedByDisplayName,
                submittedAt: organization.submittedAt,
                reviewMessage: organization.reviewMessage,
                reviewedByUserId: organization.reviewedByUserId,
                reviewedAt: organization.reviewedAt,
                rejectionReason: organization.rejectionReason,
                createdAt: organization.createdAt,
                updatedAt: organization.updatedAt,
                moderationStatus: organization.moderationStatus,
                likeCount: organization.likeCount,
                likeState: organization.likeState,
                isSubscribed: organization.isSubscribed,
                isBookmarked: organization.isBookmarked
            )

            if isEditing {
                try await repository.updateOrganization(organizationToSave)
                replaceOrganization(organizationToSave)
                replaceOrganizationRequest(organizationToSave)
            } else {
                try await repository.createOrganization(organizationToSave)
                if organizationToSave.moderationStatus == .approved {
                    organizations.insert(organizationToSave, at: 0)
                } else {
                    organizationRequests.upsertOrganizationByID(organizationToSave)
                }
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

    private func ensureOrganizationRequestIsStillEditable(_ organization: Organization) async throws {
        guard organization.submittedByUserId != nil else { return }
        guard [.pendingReview, .needsRevision, .rejected].contains(organization.moderationStatus) else { return }

        do {
            let latest = try await repository.fetchOrganization(id: organization.id)
            guard latest.submittedByUserId == organization.submittedByUserId,
                  [.pendingReview, .needsRevision, .rejected].contains(latest.moderationStatus) else {
                validationErrorMessage = AppStrings.Organizations.requestAlreadyReviewed
                throw AppError.validationFailed
            }
        } catch AppError.notFound {
            validationErrorMessage = AppStrings.Organizations.requestAlreadyReviewed
            throw AppError.validationFailed
        }
    }

    private func replaceOrganization(_ organization: Organization) {
        guard let index = organizations.firstIndex(where: { $0.id == organization.id }) else { return }
        organizations[index] = organization
    }

    private func replaceOrganizationRequest(_ organization: Organization) {
        guard let index = organizationRequests.firstIndex(where: { $0.id == organization.id }) else { return }
        if organization.moderationStatus == .approved {
            organizationRequests.remove(at: index)
        } else {
            organizationRequests[index] = organization
        }
    }

    func approveOrganizationRequest(id: String, reviewerID: String) async throws {
        try await repository.approveOrganizationRequest(id: id, reviewerID: reviewerID)
        organizationRequests.removeAll { $0.id == id }
        AppContentChangeBus.postOrganizationsChanged(organizationID: id)
    }

    func requestOrganizationRevision(id: String, message: String, reviewerID: String) async throws {
        try await repository.requestOrganizationRevision(id: id, message: message, reviewerID: reviewerID)
        AppContentChangeBus.postOrganizationsChanged(organizationID: id)
    }

    func rejectOrganizationRequest(id: String, reason: String, reviewerID: String) async throws {
        try await repository.rejectOrganizationRequest(id: id, reason: reason, reviewerID: reviewerID)
        organizationRequests.removeAll { $0.id == id }
        AppContentChangeBus.postOrganizationsChanged(organizationID: id)
    }

}

private extension Organization {
    func settingOrganizationImageURL(_ imageURL: String?) -> Organization {
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
            logoURL: imageURL ?? logoURL,
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
            ownerId: ownerId,
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
            reviewedAt: reviewedAt,
            rejectionReason: rejectionReason,
            createdAt: createdAt,
            updatedAt: updatedAt,
            moderationStatus: moderationStatus,
            likeCount: likeCount,
            likeState: likeState,
            isSubscribed: isSubscribed,
            isBookmarked: isBookmarked
        )
    }
}
