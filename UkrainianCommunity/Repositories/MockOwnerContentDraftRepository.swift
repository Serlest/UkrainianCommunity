import Foundation

struct MockOwnerContentDraftRepository: OwnerContentDraftRepository {
    func fetchDraftPage(
        userID: String,
        section: OwnerContentPlanningSection,
        limit: Int,
        after cursor: OwnerContentDraftPageCursor?
    ) async throws -> OwnerContentDraftPage {
        OwnerContentDraftPage(items: [], nextCursor: nil, hasMore: false)
    }

    func fetchDraft(userID: String, draftID: String) async throws -> OwnerContentDraft {
        throw AppError.notFound
    }

    func beginPublication(
        userID: String,
        draftID: String,
        attemptID: String
    ) async throws -> OwnerContentPublicationLease {
        throw AppError.notFound
    }

    func finalizePublication(
        userID: String,
        draftID: String,
        publication: ContentPlanningPublicationResult
    ) async throws {}

    func failPublication(
        userID: String,
        draftID: String,
        leaseID: String,
        message: String
    ) async throws {}

    func archive(userID: String, draftID: String) async throws {}
    func delete(userID: String, draftID: String) async throws {}
}
