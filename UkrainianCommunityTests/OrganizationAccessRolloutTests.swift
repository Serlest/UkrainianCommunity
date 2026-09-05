import Foundation
import Testing
import FirebaseFunctions
@testable import UkrainianCommunity

@MainActor
struct OrganizationAccessRolloutTests {
    private func organization() -> Organization {
        Organization(id: "org", name: "Fixture", description: "Fixture", city: "Wien", ownerId: "a", adminIds: [], moderatorIds: [], createdAt: .now, updatedAt: .now, moderationStatus: .approved, likeCount: 0, likeState: .notLiked)
    }

    @Test func separateActionsAndRollbackSelectTheCorrectWriteRoute() async throws {
        var mode = "shadow"
        var commandCalls = 0
        var decisionsSent = false
        let store = OrganizationAccessStore(currentUID: { "a" }, call: { name, payload in
            if name == "updateOrganizationInfo" { commandCalls += 1; #expect(payload["principalId"] as? String == "a"); return [:] }
            decisionsSent = (payload["legacyDecisions"] as? [String: [String: Bool]])?["org"]?["editInfo"] == true
            return ["principalId": "a", "schemaVersion": 1, "mode": mode, "commandsEnabled": true,
                "actionModes": ["editInfo": mode, "manageTeam": "shadow", "managePhotos": "shadow"],
                "commands": ["updateOrganizationInfo": true, "saveOrganizationPhoto": false],
                "records": [["organizationId": "org", "actions": ["editInfo"]]]]
        })
        store.transition(to: "a")
        #expect(store.allows("editInfo", organizationID: "org", userID: "a", legacy: true))
        #expect(try await !store.saveIfEnabled(organization(), fields: ["name": "Name"]))
        #expect(decisionsSent)
        mode = "enforced"
        #expect(try await store.saveIfEnabled(organization(), fields: ["name": "Name"]))
        #expect(try await !store.preparePhotoCommand(organizationID: "org"))
        #expect(store.allows("manageTeam", organizationID: "org", userID: "a", legacy: true))
        mode = "shadow"
        #expect(try await !store.saveIfEnabled(organization(), fields: ["name": "Name"]))
        #expect(commandCalls == 1)
    }

    @Test func permissionFailureNeverFallsBackToADirectWrite() async {
        let error = NSError(domain: FunctionsErrorDomain, code: FunctionsErrorCode.permissionDenied.rawValue,
            userInfo: [FunctionsErrorDetailsKey: ["reasonCode": "role_missing", "correlationId": UUID().uuidString]])
        let store = OrganizationAccessStore(currentUID: { "a" }, call: { _, _ in throw error })
        do {
            _ = try await store.saveIfEnabled(organization(), fields: ["name": "Name"])
            Issue.record("Access denial must throw, not select the legacy route")
        } catch let failure as OrganizationAccessFailure {
            #expect(failure.reason == "role_missing")
            #expect(failure.correlationID != nil)
            #expect(failure.errorDescription != "role_missing")
        } catch { Issue.record("Unexpected error \(error)") }
    }

    @Test func missingEndpointFallsBackButStaleAccountResponseCannot() async throws {
        let missing = OrganizationAccessStore(currentUID: { "a" }, call: { _, _ in
            throw NSError(domain: FunctionsErrorDomain, code: FunctionsErrorCode.notFound.rawValue)
        })
        #expect(try await !missing.saveIfEnabled(organization(), fields: [:]))
        var uid = "a"
        var resume: CheckedContinuation<Void, Never>?
        let store = OrganizationAccessStore(currentUID: { uid }, call: { _, _ in
            await withCheckedContinuation { resume = $0 }
            return ["principalId": "a", "schemaVersion": 1, "mode": "enforced", "commandsEnabled": true,
                "records": [["organizationId": "org", "actions": ["managePhotos"]]], "commands": ["saveOrganizationPhoto": true]]
        })
        let task = Task { try await store.preparePhotoCommand(organizationID: "org") }
        while resume == nil { await Task.yield() }
        uid = "b"; store.transition(to: "b"); resume?.resume()
        do { _ = try await task.value; Issue.record("Old account response was applied") }
        catch is CancellationError {}
        catch { Issue.record("Unexpected error \(error)") }
        #expect(!store.allows("managePhotos", organizationID: "org", userID: "a", legacy: false))
    }

    @Test func capabilityReadsAreBatchedInsteadOfOneRequestPerRow() async throws {
        var requests: [[String]] = []
        let store = OrganizationAccessStore(currentUID: { "a" }, call: { _, payload in
            let ids = payload["organizationIds"] as! [String]; requests.append(ids)
            return ["principalId": "a", "schemaVersion": 1, "mode": "shadow", "records": ids.map { ["organizationId": $0, "actions": []] as [String: Any] }]
        })
        store.transition(to: "a")
        for i in 0..<70 { _ = store.allows("editInfo", organizationID: "org\(i)", userID: "a", legacy: true) }
        for _ in 0..<100 {
            if requests.flatMap({ $0 }).count == 70 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.count <= 50 })
        #expect(Set(requests.flatMap { $0 }).count == 70)
    }

    @Test func galleryConflictKeepsTheOriginalPhotoAndSuccessfulReplacementKeepsCount() async {
        let repository = ReplacementFixture()
        let viewModel = OrganizationPhotoGalleryViewModel(organizationId: "org", repository: repository)
        await viewModel.refresh()
        await viewModel.refreshReplacementAvailability()
        #expect(viewModel.supportsReplacement)
        let original = repository.photo
        repository.conflict = true
        await viewModel.replacePhoto(original, imageData: Data(), caption: "Edited")
        #expect(viewModel.photos == [original])
        #expect(viewModel.errorMessage == OrganizationAccessFailure(reason: "object_changed").localizedDescription)
        repository.conflict = false
        await viewModel.replacePhoto(original, imageData: Data(), caption: "Edited")
        #expect(viewModel.photos.count == 1)
        #expect(viewModel.photos.first?.id == original.id)
        #expect(viewModel.photos.first?.imageURL == "https://example.invalid/new.jpg")
        #expect(viewModel.errorMessage == nil)
    }

    @Test func galleryConflictReloadUsesLatestVersionAndHandlesOfflineOrDeletedPhoto() async {
        let repository = ReplacementFixture()
        let viewModel = OrganizationPhotoGalleryViewModel(organizationId: "org", repository: repository)
        await viewModel.refresh()
        repository.conflict = true
        await viewModel.replacePhoto(repository.photo, imageData: Data(), caption: "Draft")
        #expect(viewModel.hasReplacementConflict)
        let latest = OrganizationPhoto(id: repository.photo.id, organizationId: "org", imageURL: "https://example.invalid/concurrent.jpg", uploadedBy: "a", createdAt: .now)
        repository.fetchedPhotos = [latest]
        #expect(await viewModel.reloadReplacementTarget(id: latest.id) == latest)
        #expect(!viewModel.hasReplacementConflict)
        #expect(viewModel.photos == [latest])
        await viewModel.replacePhoto(latest, imageData: Data(), caption: "Draft")
        repository.failFetch = true
        #expect(await viewModel.reloadReplacementTarget(id: latest.id) == nil)
        #expect(viewModel.hasReplacementConflict)
        #expect(viewModel.photos == [latest])
        repository.failFetch = false
        repository.fetchedPhotos = []
        #expect(await viewModel.reloadReplacementTarget(id: latest.id) == nil)
        #expect(!viewModel.hasReplacementConflict)
        #expect(viewModel.errorMessage == OrganizationAccessFailure(reason: "object_missing").localizedDescription)
    }
}

@MainActor
private final class ReplacementFixture: OrganizationPhotoRepository {
    var conflict = false
    var failFetch = false
    var fetchedPhotos: [OrganizationPhoto]?
    let photo = OrganizationPhoto(id: "photo", organizationId: "org", imageURL: "https://example.invalid/old.jpg", uploadedBy: "a", createdAt: .now)
    func fetchPhotos(organizationId: String) async throws -> [OrganizationPhoto] {
        if failFetch { throw URLError(.notConnectedToInternet) }
        return fetchedPhotos ?? [photo]
    }
    func addPhoto(organizationId: String, imageData: Data, caption: String?, uploadedBy: String) async throws -> OrganizationPhoto { photo }
    func deletePhoto(_ photo: OrganizationPhoto) async throws {}
    func supportsPhotoReplacement(organizationId: String) async throws -> Bool { true }
    func replacePhoto(_ photo: OrganizationPhoto, imageData: Data, caption: String?) async throws -> OrganizationPhoto {
        if conflict { throw OrganizationAccessFailure(reason: "object_changed") }
        return OrganizationPhoto(id: photo.id, organizationId: photo.organizationId, imageURL: "https://example.invalid/new.jpg", caption: caption, uploadedBy: "a", createdAt: photo.createdAt, updatedAt: .now)
    }
}
