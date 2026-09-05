#if DEBUG
import Foundation

@MainActor
final class UITestOrganizationPhotoRepository: OrganizationPhotoRepository {
    private var items: [OrganizationPhoto] = []
    private var didSimulateConflict = false
    func fetchPhotos(organizationId: String) async throws -> [OrganizationPhoto] {
        if items.isEmpty {
            items = [OrganizationPhoto(id: "photo-fixture", organizationId: organizationId,
                imageURL: "https://example.invalid/fixture.jpg", caption: "Audit photo", uploadedBy: "fixture", createdAt: .now)]
        }
        return items
    }
    func supportsPhotoReplacement(organizationId: String) async throws -> Bool { true }
    func addPhoto(organizationId: String, imageData: Data, caption: String?, uploadedBy: String) async throws -> OrganizationPhoto {
        let photo = OrganizationPhoto(id: UUID().uuidString, organizationId: organizationId, imageURL: "https://example.invalid/new.jpg", caption: caption, uploadedBy: uploadedBy, createdAt: .now)
        items.append(photo); return photo
    }
    func replacePhoto(_ photo: OrganizationPhoto, imageData: Data, caption: String?) async throws -> OrganizationPhoto {
        if photo.imageURL != items.first(where: { $0.id == photo.id })?.imageURL {
            throw OrganizationAccessFailure(reason: "object_changed")
        }
        if ProcessInfo.processInfo.environment["UITestGalleryConflict"] == "1", !didSimulateConflict {
            didSimulateConflict = true
            items = [OrganizationPhoto(id: photo.id, organizationId: photo.organizationId, imageURL: "https://example.invalid/concurrent.jpg", caption: "Remote edit", uploadedBy: photo.uploadedBy, createdAt: photo.createdAt)]
            throw OrganizationAccessFailure(reason: "object_changed")
        }
        let result = OrganizationPhoto(id: photo.id, organizationId: photo.organizationId, imageURL: "https://example.invalid/replacement.jpg", caption: caption, uploadedBy: photo.uploadedBy, createdAt: photo.createdAt, updatedAt: .now)
        items = items.map { $0.id == photo.id ? result : $0 }; return result
    }
    func deletePhoto(_ photo: OrganizationPhoto) async throws { items.removeAll { $0.id == photo.id } }
}
#endif

enum OrganizationPhotoRepositoryFactory {
    static func make() -> OrganizationPhotoRepository {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") && ProcessInfo.processInfo.environment["UITestGallery"] == "1" {
            return UITestOrganizationPhotoRepository()
        }
        #endif
        return FirestoreOrganizationPhotoRepository()
    }
}
