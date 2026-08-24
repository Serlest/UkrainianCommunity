import Foundation
import FirebaseFirestore
import FirebaseFunctions

struct FirestoreOrganizationPhotoRepository: OrganizationPhotoRepository {
    private static let maxPhotosPerOrganization = 30
    private static let responseDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

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

    func addPhoto(organizationId: String, imageData: Data, caption: String?, uploadedBy _: String) async throws -> OrganizationPhoto {
        let photoReference = photosCollection(organizationId: organizationId).document()
        let imageURL = try await imageUploadService.uploadOrganizationPhoto(
            data: imageData,
            organizationID: organizationId,
            photoID: photoReference.documentID
        )

        let trimmedCaption = caption?.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let response = try await CloudFunctionsClient.shared.createOrganizationPhotoMetadata(
                organizationId: organizationId,
                photoId: photoReference.documentID,
                imageURL: imageURL.absoluteString,
                caption: trimmedCaption?.isEmpty == false ? trimmedCaption : nil
            )
            guard response.organizationId == organizationId,
                  response.photoId == photoReference.documentID,
                  let uploadedBy = response.uploadedBy,
                  let createdAtText = response.createdAt,
                  let createdAt = Self.responseDateFormatter.date(from: createdAtText) else {
                throw AppError.unknown
            }
            return OrganizationPhoto(
                id: response.photoId,
                organizationId: response.organizationId,
                imageURL: imageURL.absoluteString,
                caption: trimmedCaption?.isEmpty == false ? trimmedCaption : nil,
                uploadedBy: uploadedBy,
                createdAt: createdAt,
                updatedAt: nil
            )
        } catch {
            await SystemTechnicalErrorLoggingService.shared.logFailure(
                error,
                context: SystemTechnicalErrorContext(
                    moduleName: "Organizations",
                    operationName: "addOrganizationPhotoMetadata",
                    targetType: .organization,
                    targetId: photoReference.documentID,
                    organizationId: organizationId
                )
            )
            do {
                try await imageUploadService.deleteOrganizationPhoto(
                    organizationID: organizationId,
                    photoID: photoReference.documentID
                )
            } catch {}
            throw mapPhotoMutationError(error)
        }
    }

    func deletePhoto(_ photo: OrganizationPhoto) async throws {
        do {
            _ = try await CloudFunctionsClient.shared.deleteOrganizationPhotoMetadata(
                organizationId: photo.organizationId,
                photoId: photo.id
            )
        } catch {
            await SystemTechnicalErrorLoggingService.shared.logFailure(
                error,
                context: SystemTechnicalErrorContext(
                    moduleName: "Organizations",
                    operationName: "deleteOrganizationPhotoMetadata",
                    targetType: .organization,
                    targetId: photo.id,
                    organizationId: photo.organizationId
                )
            )
            throw mapPhotoMutationError(error)
        }

        // Metadata is authoritative. A failed object cleanup must not restore a
        // deleted photo or corrupt the atomic counter; it is logged by storage.
        do {
            try await imageUploadService.deleteOrganizationPhoto(
                organizationID: photo.organizationId,
                photoID: photo.id
            )
        } catch {}
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
}

private func mapPhotoMutationError(_ error: Error) -> Error {
    if let appError = error as? AppError {
        return appError
    }
    guard let code = FunctionsErrorCode(rawValue: (error as NSError).code) else {
        return error
    }
    switch code {
    case .resourceExhausted, .invalidArgument, .failedPrecondition:
        return AppError.validationFailed
    case .permissionDenied, .unauthenticated:
        return AppError.permissionDenied
    case .notFound:
        return AppError.notFound
    default:
        return error
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
