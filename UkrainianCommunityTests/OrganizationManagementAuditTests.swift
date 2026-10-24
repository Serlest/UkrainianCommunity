import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct OrganizationManagementAuditTests {
    @Test func createSubmissionIsBusyBeforeRulesAcceptanceAndRejectsDuplicate() async {
        var release: CheckedContinuation<Void, Error>?
        var acceptanceCalls = 0
        let editor = OrganizationEditorViewModel(rulesAcceptance: { _, _, _ in
            acceptanceCalls += 1
            try await withCheckedThrowingContinuation { release = $0 }
        })
        editor.name = "Audit Organization"
        editor.shortDescription = "Community support and cultural events for families."
        editor.city = "Innsbruck"; editor.selectedFederalState = .tirol
        let organizations = OrganizationsViewModel(repository: MockOrganizationRepository())
        let actor = MockContentBuilder.ownerUser()
        let first = Task { await editor.submit(with: organizations, user: actor, organizationRulesVersion: "test-version") }
        while release == nil { await Task.yield() }
        #expect(editor.isSubmitting)
        #expect(!(await editor.submit(with: organizations, user: actor, organizationRulesVersion: "test-version")))
        #expect(acceptanceCalls == 1)
        release?.resume()
        #expect(await first.value)
        #expect(!editor.isSubmitting)
    }

    @Test func failedRefreshKeepsWorkspaceRowsAndCounters() async {
        var fail = false
        let model = OrganizationWorkspaceListModel(read: { _ in
            if fail { throw AppError.network }
            return .init(counts: ["approved": 37], items: [.init(id: "one", title: "One", status: .approved, reason: "")])
        })
        let request = OrganizationWorkspaceRequest(action: "content", principalId: "owner", organizationId: "org", contentType: "news")
        await model.load(request)
        fail = true
        await model.load(request)
        #expect(model.items.map(\.id) == ["one"])
        #expect(model.counts["approved"] == 37)
        #expect(model.error != nil)
    }
    @Test func aDifferentRequestCannotReuseThePreviousPageCursor() async {
        var reads: [OrganizationWorkspaceRequest] = []
        let model = OrganizationWorkspaceListModel(read: { request in
            reads.append(request)
            return .init(cursor: "cursor-org-a", items: [.init(id: "one", title: "One", status: .approved, reason: "")])
        })
        await model.load(.init(action: "content", principalId: "owner", organizationId: "org-a", contentType: "news"))
        await model.load(.init(action: "content", principalId: "owner", organizationId: "org-b", contentType: "news"), more: true)
        #expect(reads.count == 1)
    }
    @Test func editingRequiresConfirmationOnlyAfterActualChanges() {
        let model = OrganizationEditorViewModel(mode: .edit(existing: MockContentBuilder.organizations()[0]))
        #expect(!model.shouldConfirmDraftBeforeDismiss)
        let original = model.name
        model.name = "Changed organization"
        #expect(model.shouldConfirmDraftBeforeDismiss)
        model.name = original
        #expect(!model.shouldConfirmDraftBeforeDismiss)
    }
    @Test func aFailedNextPageRetriesItsCursorAndKeepsRows() async {
        var cursors: [String?] = []
        let model = OrganizationWorkspaceListModel(read: { request in
            cursors.append(request.cursor)
            if cursors.count == 2 { throw AppError.network }
            return .init(cursor: request.cursor == nil ? "second" : nil, counts: ["approved": 37],
                items: [.init(id: request.cursor ?? "first", title: "Title", status: .approved, reason: "")])
        })
        let request = OrganizationWorkspaceRequest(action: "content", principalId: "owner", organizationId: "org", contentType: "news")
        await model.load(request); await model.load(request, more: true)
        #expect(model.items.map(\.id) == ["first"])
        await model.retry(request)
        #expect(cursors == [nil, "second", "second"])
        #expect(model.items.count == 2 && !model.hasMore)
    }
    @Test func resetRejectsALateWorkspaceResponse() async {
        var release: CheckedContinuation<OrganizationWorkspaceResponse, Error>?
        let model = OrganizationWorkspaceListModel(read: { _ in try await withCheckedThrowingContinuation { release = $0 } })
        let task = Task { await model.load(.init(action: "subscribers", principalId: "old", organizationId: "org")) }
        while release == nil { await Task.yield() }
        model.reset()
        release?.resume(returning: .init(users: [.init(id: "private", displayName: "Old account", city: "Wien", federalState: nil, avatarURL: nil)]))
        await task.value
        #expect(model.users.isEmpty && !model.loading && !model.hasLoaded)
    }
    @Test func slowGalleryRefreshCannotRestoreADeletedPhoto() async {
        let repository = ManagementGalleryFixture()
        let model = OrganizationPhotoGalleryViewModel(organizationId: "org", repository: repository)
        await model.refresh()
        repository.suspend = true
        let refresh = Task { await model.refresh() }
        while repository.release == nil { await Task.yield() }
        await model.deletePhoto(repository.photo)
        repository.release?.resume(returning: [repository.photo])
        await refresh.value
        #expect(model.photos.isEmpty && !model.isLoading)
    }

}

@MainActor
private final class ManagementGalleryFixture: OrganizationPhotoRepository {
    var suspend = false
    var release: CheckedContinuation<[OrganizationPhoto], Error>?
    let photo = OrganizationPhoto(id: "photo", organizationId: "org", imageURL: "https://example.org/photo.jpg", uploadedBy: "owner", createdAt: .now)
    func fetchPhotos(organizationId: String) async throws -> [OrganizationPhoto] {
        if suspend { return try await withCheckedThrowingContinuation { release = $0 } }
        return [photo]
    }
    func deletePhoto(_ photo: OrganizationPhoto) async throws {}
    func addPhoto(organizationId: String, imageData: Data, caption: String?, uploadedBy: String) async throws -> OrganizationPhoto { photo }
}
