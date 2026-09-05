import Foundation
import FirebaseFirestore
import FirebaseFunctions
import FirebaseAuth
import FirebaseStorage
import CryptoKit

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
        guard let principalID = Auth.auth().currentUser?.uid else { throw AppError.permissionDenied }
        if try await OrganizationAccessStore.shared.preparePhotoCommand(organizationID: organizationId) {
            guard Auth.auth().currentUser?.uid == principalID else { throw CancellationError() }
            return try await savePhotoCommand(organizationId: organizationId, replacing: nil, imageData: imageData, caption: caption, principalID: principalID)
        }
        guard Auth.auth().currentUser?.uid == principalID else { throw CancellationError() }
        let fingerprint = SHA256.hash(data: Data((principalID + "\u{0}" + organizationId + "\u{0}" + (caption ?? "")).utf8) + imageData)
            .map { String(format: "%02x", $0) }.joined()
        let operationKey = "organizationPhoto.pending.v1." + fingerprint
        let photoID = UserDefaults.standard.string(forKey: operationKey) ?? UUID().uuidString
        UserDefaults.standard.set(photoID, forKey: operationKey)
        let photoReference = photosCollection(organizationId: organizationId).document(photoID)
        func confirmedPhoto() async throws -> OrganizationPhoto? {
            let snapshot = try await photoReference.getDocument(source: .server)
            guard Auth.auth().currentUser?.uid == principalID else { throw CancellationError() }
            guard snapshot.exists else { return nil }
            let photo = try makePhoto(from: snapshot, organizationId: organizationId)
            UserDefaults.standard.removeObject(forKey: operationKey)
            return photo
        }
        // Recover an earlier committed operation before uploading anything again.
        if let photo = try await confirmedPhoto() { return photo }
        let object = Storage.storage().reference().child("organizations/\(organizationId)/photos/\(photoID).jpg")
        let imageURL: URL
        do {
            imageURL = try await object.downloadURL()
        } catch {
            guard StorageErrorCode(rawValue: (error as NSError).code) == .objectNotFound else { throw error }
            guard Auth.auth().currentUser?.uid == principalID else { throw CancellationError() }
            imageURL = try await imageUploadService.uploadOrganizationPhoto(
                data: imageData, organizationID: organizationId, photoID: photoID
            )
        }
        let trimmedCaption = caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            return try await PhotoMutationRecovery.commit(
                isCurrent: { Auth.auth().currentUser?.uid == principalID },
                readCommitted: confirmedPhoto,
                shouldRetry: { error in
                    let failure = error as NSError
                    guard failure.domain == FunctionsErrorDomain else { return false }
                    let code = FunctionsErrorCode(rawValue: failure.code)
                    return code == .unavailable || code == .deadlineExceeded
                },
                mutation: {
                    _ = try await CloudFunctionsClient.shared.createOrganizationPhotoMetadata(
                        organizationId: organizationId, photoId: photoID,
                        imageURL: imageURL.absoluteString,
                        caption: trimmedCaption?.isEmpty == false ? trimmedCaption : nil,
                        principalID: principalID
                    )
                }
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if OrganizationAccessFailure(error).reason == "operation_expired" {
                UserDefaults.standard.removeObject(forKey: operationKey)
            }
            await SystemTechnicalErrorLoggingService.shared.logFailure(error, context: SystemTechnicalErrorContext(
                moduleName: "Organizations", operationName: "addOrganizationPhotoMetadata",
                targetType: .organization, targetId: photoID, organizationId: organizationId
            ))
            // Keep both the operation ID and object for a later retry. An
            // ambiguous result is never sufficient evidence for deleting media.
            throw mapPhotoMutationError(error)
        }
    }

    func supportsPhotoReplacement(organizationId: String) async throws -> Bool {
        try await OrganizationAccessStore.shared.preparePhotoCommand(organizationID: organizationId)
    }

    func replacePhoto(_ photo: OrganizationPhoto, imageData: Data, caption: String?) async throws -> OrganizationPhoto {
        guard let principalID = Auth.auth().currentUser?.uid else { throw AppError.permissionDenied }
        guard try await supportsPhotoReplacement(organizationId: photo.organizationId) else { throw OrganizationAccessFailure(reason: "route_disabled") }
        guard Auth.auth().currentUser?.uid == principalID else { throw CancellationError() }
        return try await savePhotoCommand(organizationId: photo.organizationId, replacing: photo, imageData: imageData, caption: caption, principalID: principalID)
    }

    private func savePhotoCommand(organizationId: String, replacing photo: OrganizationPhoto?, imageData: Data, caption: String?, principalID: String) async throws -> OrganizationPhoto {
        let material = [principalID, organizationId, photo?.id ?? "new", photo?.imageURL ?? "", caption ?? ""].joined(separator: "\u{0}")
        let key = "organizationPhoto.pending.v2." + SHA256.hash(data: Data(material.utf8) + imageData).map { String(format: "%02x", $0) }.joined()
        let operationID = UserDefaults.standard.string(forKey: key) ?? UUID().uuidString
        UserDefaults.standard.set(operationID, forKey: key)
        let photoID = photo?.id ?? operationID
        let storageID = SHA256.hash(data: Data((principalID + "\u{0}" + operationID).utf8)).map { String(format: "%02x", $0) }.joined()
        let expectedPath = "organizations/\(organizationId)/photoVersions/\(storageID).jpg"
        func readCommitted() async throws -> OrganizationPhoto? {
            let snapshot = try await photosCollection(organizationId: organizationId).document(photoID).getDocument(source: .server)
            guard Auth.auth().currentUser?.uid == principalID else { throw CancellationError() }
            guard snapshot.exists else { return nil }
            let saved = try makePhoto(from: snapshot, organizationId: organizationId)
            guard URL(string: saved.imageURL)?.path.removingPercentEncoding?.hasSuffix("/o/" + expectedPath) == true else { return nil }
            UserDefaults.standard.removeObject(forKey: key)
            return saved
        }
        if let saved = try await readCommitted() { return saved }
        do {
            return try await PhotoMutationRecovery.commit(isCurrent: { Auth.auth().currentUser?.uid == principalID }, readCommitted: readCommitted,
                shouldRetry: { error in
                    let error = error as NSError
                    return error.domain == FunctionsErrorDomain && [.unavailable, .deadlineExceeded].contains(FunctionsErrorCode(rawValue: error.code))
                }, mutation: {
                    _ = try await Functions.functions(region: "europe-west3").httpsCallable("saveOrganizationPhoto").call([
                        "principalId": principalID, "organizationId": organizationId, "photoId": photoID, "operationId": operationID,
                        "expectedImageURL": photo?.imageURL as Any? ?? NSNull(), "imageBase64": imageData.base64EncodedString(),
                        "caption": caption as Any? ?? NSNull(), "clientVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                    ])
                })
        } catch is CancellationError { throw CancellationError() }
        catch {
            let failure = OrganizationAccessFailure(error)
            if failure.reason == "operation_expired" { UserDefaults.standard.removeObject(forKey: key) }
            await SystemTechnicalErrorLoggingService.shared.logFailure(error, context: SystemTechnicalErrorContext(moduleName: "Organizations", operationName: "saveOrganizationPhoto", metadata: failure.diagnosticMetadata))
            throw failure
        }
    }

    func deletePhoto(_ photo: OrganizationPhoto) async throws {
        guard let principalID = Auth.auth().currentUser?.uid else { throw AppError.permissionDenied }
        do {
            _ = try await CloudFunctionsClient.shared.deleteOrganizationPhotoMetadata(
                organizationId: photo.organizationId,
                photoId: photo.id,
                principalID: principalID
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

        guard Auth.auth().currentUser?.uid == principalID else { return }
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

    private func makePhoto(from document: DocumentSnapshot, organizationId: String) throws -> OrganizationPhoto {
        let data = document.data() ?? [:]
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
    if (error as NSError).userInfo[FunctionsErrorDetailsKey] != nil { return OrganizationAccessFailure(error) }
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
