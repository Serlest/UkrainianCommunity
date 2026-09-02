import Combine
import Foundation

struct OwnerContentPlanningSectionSnapshot: Equatable {
    var items: [OwnerContentDraft] = []
    var nextCursor: OwnerContentDraftPageCursor?
    var hasMore = false
    var hasLoaded = false
    var isLoading = false
    var isLoadingNextPage = false
    var error: AppError?
}

@MainActor
final class OwnerContentPlanningViewModel: ObservableObject {
    static let pageSize = 15

    @Published private(set) var sections = Dictionary(
        uniqueKeysWithValues: OwnerContentPlanningSection.allCases.map {
            ($0, OwnerContentPlanningSectionSnapshot())
        }
    )
    @Published private(set) var actionDraftIDs = Set<String>()
    @Published private(set) var actionErrorMessage: String?
    @Published private(set) var deepLinkError: AppError?

    private let repository: OwnerContentDraftRepository
    private var activeUserID: String?
    private var publicationAttemptIDs: [String: String] = [:]
    private var publicationLeases: [String: OwnerContentPublicationLease] = [:]

    init(repository: OwnerContentDraftRepository) {
        self.repository = repository
    }

    func snapshot(for section: OwnerContentPlanningSection) -> OwnerContentPlanningSectionSnapshot {
        sections[section] ?? OwnerContentPlanningSectionSnapshot()
    }

    func start(userID: String) {
        guard activeUserID != userID else { return }
        activeUserID = userID
        resetAllSections()
        actionDraftIDs.removeAll()
        actionErrorMessage = nil
        deepLinkError = nil
        publicationAttemptIDs.removeAll()
        publicationLeases.removeAll()
    }

    func stop() {
        activeUserID = nil
        resetAllSections()
        actionDraftIDs.removeAll()
        actionErrorMessage = nil
        deepLinkError = nil
        publicationAttemptIDs.removeAll()
        publicationLeases.removeAll()
    }

    func load(_ section: OwnerContentPlanningSection, userID: String, force: Bool = false) async {
        start(userID: userID)
        var state = snapshot(for: section)
        guard !state.isLoading, !state.isLoadingNextPage else { return }
        guard force || !state.hasLoaded else { return }

        state.isLoading = true
        state.error = nil
        sections[section] = state
        do {
            let page = try await repository.fetchDraftPage(
                userID: userID,
                section: section,
                limit: Self.pageSize,
                after: nil
            )
            guard !Task.isCancelled, activeUserID == userID else { return }
            sections[section] = OwnerContentPlanningSectionSnapshot(
                items: page.items,
                nextCursor: page.nextCursor,
                hasMore: page.hasMore,
                hasLoaded: true,
                isLoading: false,
                isLoadingNextPage: false,
                error: nil
            )
        } catch is CancellationError {
            guard activeUserID == userID else { return }
            sections[section]?.isLoading = false
        } catch {
            guard activeUserID == userID else { return }
            sections[section]?.isLoading = false
            sections[section]?.hasLoaded = true
            sections[section]?.error = (error as? AppError) ?? .unknown
        }
    }

    func refresh(_ section: OwnerContentPlanningSection) async {
        guard let activeUserID else { return }
        await load(section, userID: activeUserID, force: true)
    }

    func loadNextPageIfNeeded(
        _ section: OwnerContentPlanningSection,
        currentItemID: String
    ) async {
        guard let activeUserID else { return }
        var state = snapshot(for: section)
        guard state.hasLoaded, state.hasMore,
              !state.isLoading, !state.isLoadingNextPage,
              let cursor = state.nextCursor else { return }
        let triggerIDs = state.items.suffix(3).map(\.id)
        guard triggerIDs.contains(currentItemID) else { return }

        state.isLoadingNextPage = true
        state.error = nil
        sections[section] = state
        do {
            let page = try await repository.fetchDraftPage(
                userID: activeUserID,
                section: section,
                limit: Self.pageSize,
                after: cursor
            )
            guard !Task.isCancelled, self.activeUserID == activeUserID else { return }
            var updated = snapshot(for: section)
            let existingIDs = Set(updated.items.map(\.id))
            updated.items.append(contentsOf: page.items.filter { !existingIDs.contains($0.id) })
            updated.nextCursor = page.nextCursor
            updated.hasMore = page.hasMore
            updated.isLoadingNextPage = false
            updated.error = nil
            sections[section] = updated
        } catch is CancellationError {
            guard self.activeUserID == activeUserID else { return }
            sections[section]?.isLoadingNextPage = false
        } catch {
            guard self.activeUserID == activeUserID else { return }
            sections[section]?.isLoadingNextPage = false
            sections[section]?.error = (error as? AppError) ?? .unknown
        }
    }

    func fetchDraftForDeepLink(_ draftID: String) async -> OwnerContentDraft? {
        guard let activeUserID else { return nil }
        deepLinkError = nil
        do {
            return try await repository.fetchDraft(userID: activeUserID, draftID: draftID)
        } catch is CancellationError {
            return nil
        } catch {
            deepLinkError = (error as? AppError) ?? .unknown
            return nil
        }
    }

    func reveal(_ draft: OwnerContentDraft) {
        let section = draft.planningSection
        var state = snapshot(for: section)
        state.items.removeAll { $0.id == draft.id }
        state.items.insert(draft, at: 0)
        sections[section] = state
    }

    func beginPublishing(_ draft: OwnerContentDraft) async -> OwnerContentPublicationLease? {
        guard let activeUserID else { return nil }
        actionErrorMessage = nil
        if let existingLease = publicationLeases[draft.id], existingLease.expiresAt > Date() {
            return OwnerContentPublicationLease(
                draftID: existingLease.draftID,
                kind: existingLease.kind,
                contentID: existingLease.contentID,
                leaseID: existingLease.leaseID,
                expiresAt: existingLease.expiresAt,
                contentAlreadyExists: existingLease.contentAlreadyExists,
                existingModerationStatus: existingLease.existingModerationStatus,
                existingScheduledAt: existingLease.existingScheduledAt
            )
        }
        let attemptID = publicationAttemptIDs[draft.id] ?? UUID().uuidString
        publicationAttemptIDs[draft.id] = attemptID
        actionDraftIDs.insert(draft.id)
        do {
            let lease = try await repository.beginPublication(
                userID: activeUserID,
                draftID: draft.id,
                attemptID: attemptID
            )
            publicationLeases[draft.id] = lease
            actionDraftIDs.remove(draft.id)
            return lease
        } catch is CancellationError {
            actionDraftIDs.remove(draft.id)
            return nil
        } catch {
            actionDraftIDs.remove(draft.id)
            actionErrorMessage = AppStrings.ContentPlanning.publicationBeginFailed
            return nil
        }
    }

    func finishPublishing(
        _ draft: OwnerContentDraft,
        publication: ContentPlanningPublicationResult
    ) async -> Bool {
        guard let activeUserID,
              let lease = publicationLeases[draft.id],
              lease.contentID == publication.contentID,
              lease.kind == publication.kind,
              publication.publicationLeaseID == nil || publication.publicationLeaseID == lease.leaseID else {
            actionErrorMessage = AppStrings.ContentPlanning.updateFailed
            return false
        }
        actionDraftIDs.insert(draft.id)
        actionErrorMessage = nil
        let linkedPublication = ContentPlanningPublicationResult(
            kind: publication.kind,
            contentID: publication.contentID,
            scheduledAt: publication.scheduledAt,
            publicationLeaseID: lease.leaseID
        )
        publicationLeases[draft.id] = OwnerContentPublicationLease(
            draftID: lease.draftID,
            kind: lease.kind,
            contentID: lease.contentID,
            leaseID: lease.leaseID,
            expiresAt: lease.expiresAt,
            contentAlreadyExists: true,
            existingModerationStatus: lease.existingModerationStatus,
            existingScheduledAt: lease.existingScheduledAt
        )
        do {
            try await repository.finalizePublication(
                userID: activeUserID,
                draftID: draft.id,
                publication: linkedPublication
            )
            clearPublicationAttempt(draft.id)
            removeDraftFromAllSections(draft.id)
            invalidate(publication.isScheduled ? .scheduled : .history)
            actionDraftIDs.remove(draft.id)
            return true
        } catch is CancellationError {
            actionDraftIDs.remove(draft.id)
            return false
        } catch {
            actionDraftIDs.remove(draft.id)
            actionErrorMessage = AppStrings.ContentPlanning.updateFailed
            return false
        }
    }

    func failPublishing(_ draft: OwnerContentDraft, message: String) async {
        guard let activeUserID, let lease = publicationLeases[draft.id] else { return }
        do {
            try await repository.failPublication(
                userID: activeUserID,
                draftID: draft.id,
                leaseID: lease.leaseID,
                message: message
            )
            clearPublicationAttempt(draft.id)
            removeDraftFromAllSections(draft.id)
            invalidate(.attention)
        } catch {
            actionErrorMessage = AppStrings.ContentPlanning.updateFailed
        }
    }

    func archive(_ draft: OwnerContentDraft) async -> Bool {
        guard let activeUserID else { return false }
        actionDraftIDs.insert(draft.id)
        actionErrorMessage = nil
        do {
            try await repository.archive(userID: activeUserID, draftID: draft.id)
            removeDraftFromAllSections(draft.id)
            invalidate(.history)
            actionDraftIDs.remove(draft.id)
            return true
        } catch {
            actionDraftIDs.remove(draft.id)
            actionErrorMessage = AppStrings.ContentPlanning.updateFailed
            return false
        }
    }

    func delete(_ draft: OwnerContentDraft) async -> Bool {
        guard let activeUserID else { return false }
        actionDraftIDs.insert(draft.id)
        actionErrorMessage = nil
        do {
            try await repository.delete(userID: activeUserID, draftID: draft.id)
            removeDraftFromAllSections(draft.id)
            actionDraftIDs.remove(draft.id)
            return true
        } catch {
            actionDraftIDs.remove(draft.id)
            actionErrorMessage = AppStrings.ContentPlanning.deleteFailed
            return false
        }
    }

    func isPerformingAction(on draftID: String) -> Bool {
        actionDraftIDs.contains(draftID)
    }

    private func clearPublicationAttempt(_ draftID: String) {
        publicationAttemptIDs[draftID] = nil
        publicationLeases[draftID] = nil
    }

    private func removeDraftFromAllSections(_ draftID: String) {
        for section in OwnerContentPlanningSection.allCases {
            sections[section]?.items.removeAll { $0.id == draftID }
        }
    }

    private func invalidate(_ section: OwnerContentPlanningSection) {
        sections[section]?.hasLoaded = false
        sections[section]?.nextCursor = nil
        sections[section]?.hasMore = false
    }

    private func resetAllSections() {
        sections = Dictionary(
            uniqueKeysWithValues: OwnerContentPlanningSection.allCases.map {
                ($0, OwnerContentPlanningSectionSnapshot())
            }
        )
    }
}
