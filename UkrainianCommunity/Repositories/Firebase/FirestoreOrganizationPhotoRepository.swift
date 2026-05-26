import Foundation
import FirebaseFirestore

struct FirestoreOrganizationPhotoRepository: OrganizationPhotoRepository {
    // TODO: Enforce max photos server-side with organization.photoCount + transaction/rules
    // or a Cloud Function. Firestore rules cannot count subcollection documents directly.
    private static let maxPhotosPerOrganization = 30

    private let database = Firestore.firestore()
    private let imageUploadService = ImageUploadService.shared

    func fetchPhotos(organizationId: String) async throws -> [OrganizationPhoto] {
        let snapshot = try await photosCollection(organizationId: organizationId)
            .order(by: "createdAt", descending: true)
            .limit(to: Self.maxPhotosPerOrganization)
            .getDocuments()

        return try snapshot.documents.map { document in
            try makePhoto(from: document, organizationId: organizationId)
        }
    }

    func addPhoto(organizationId: String, imageData: Data, caption: String?, uploadedBy: String) async throws -> OrganizationPhoto {
        let existingSnapshot = try await photosCollection(organizationId: organizationId).limit(to: Self.maxPhotosPerOrganization + 1).getDocuments()
        guard existingSnapshot.documents.count < Self.maxPhotosPerOrganization else {
            throw AppError.validationFailed
        }

        let photoReference = photosCollection(organizationId: organizationId).document()
        let imageURL = try await imageUploadService.uploadOrganizationPhoto(
            data: imageData,
            organizationID: organizationId,
            photoID: photoReference.documentID
        )

        let trimmedCaption = caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        let photo = OrganizationPhoto(
            id: photoReference.documentID,
            organizationId: organizationId,
            imageURL: imageURL.absoluteString,
            caption: trimmedCaption?.isEmpty == false ? trimmedCaption : nil,
            uploadedBy: uploadedBy,
            createdAt: Date(),
            updatedAt: nil
        )

        do {
            try await photoReference.setData(makePhotoData(from: photo))
        } catch {
            do {
                try await imageUploadService.deleteOrganizationPhoto(
                    organizationID: organizationId,
                    photoID: photoReference.documentID
                )
            } catch {}
            throw error
        }

        return photo
    }

    func deletePhoto(_ photo: OrganizationPhoto) async throws {
        do {
            try await imageUploadService.deleteOrganizationPhoto(organizationID: photo.organizationId, photoID: photo.id)
        } catch {}

        try await photosCollection(organizationId: photo.organizationId).document(photo.id).delete()
    }

    private func photosCollection(organizationId: String) -> CollectionReference {
        database.collection("organizations").document(organizationId).collection("photos")
    }

    private func makePhoto(from document: QueryDocumentSnapshot, organizationId: String) throws -> OrganizationPhoto {
        let data = document.data()
        guard let imageURL = data["imageURL"] as? String,
              let uploadedBy = data["uploadedBy"] as? String,
              let createdAt = (data["createdAt"] as? Timestamp)?.dateValue() else {
            throw AppError.notFound
        }

        return OrganizationPhoto(
            id: data["id"] as? String ?? document.documentID,
            organizationId: data["organizationId"] as? String ?? organizationId,
            imageURL: imageURL,
            caption: (data["caption"] as? String)?.nilIfEmpty,
            uploadedBy: uploadedBy,
            createdAt: createdAt,
            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue()
        )
    }

    private func makePhotoData(from photo: OrganizationPhoto) -> [String: Any] {
        [
            "id": photo.id,
            "organizationId": photo.organizationId,
            "imageURL": photo.imageURL,
            "caption": photo.caption ?? NSNull(),
            "uploadedBy": photo.uploadedBy,
            "createdAt": Timestamp(date: photo.createdAt),
            "updatedAt": photo.updatedAt.map { Timestamp(date: $0) } ?? NSNull()
        ]
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
