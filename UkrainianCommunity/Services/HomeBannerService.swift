import FirebaseFirestore
import Foundation

struct HomeBannerMetadata: Equatable {
    static let collectionPath = "appConfig"
    static let documentID = "homeBanner"
    static let storagePath = "appConfig/homeBanner/banner.jpg"

    let imageURL: String
    let storagePath: String
    let updatedAt: Date
    let updatedBy: String
}

protocol HomeBannerServiceProtocol {
    func fetchHomeBanner() async throws -> HomeBannerMetadata?
    func updateHomeBannerImage(data: Data, updatedBy userID: String) async throws -> HomeBannerMetadata
}

final class FirestoreHomeBannerService: HomeBannerServiceProtocol {
    private let database = Firestore.firestore()
    private let imageUploadService: ImageUploadService

    init(imageUploadService: ImageUploadService = .shared) {
        self.imageUploadService = imageUploadService
    }

    func fetchHomeBanner() async throws -> HomeBannerMetadata? {
        do {
            let snapshot = try await homeBannerDocument.getDocument()
            guard snapshot.exists, let data = snapshot.data() else {
                return nil
            }

            guard let imageURL = data["imageURL"] as? String, !imageURL.isEmpty else {
                return nil
            }

            return HomeBannerMetadata(
                imageURL: imageURL,
                storagePath: data["storagePath"] as? String ?? HomeBannerMetadata.storagePath,
                updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? .distantPast,
                updatedBy: data["updatedBy"] as? String ?? ""
            )
        } catch {
            throw mapFirestoreError(error)
        }
    }

    func updateHomeBannerImage(data: Data, updatedBy userID: String) async throws -> HomeBannerMetadata {
        do {
            let uploadedURL = try await imageUploadService.uploadHomeBannerImage(data: data)
            let updatedAt = Date()
            let metadata = HomeBannerMetadata(
                imageURL: uploadedURL.absoluteString,
                storagePath: HomeBannerMetadata.storagePath,
                updatedAt: updatedAt,
                updatedBy: userID
            )

            try await homeBannerDocument.setData([
                "imageURL": metadata.imageURL,
                "storagePath": metadata.storagePath,
                "updatedAt": Timestamp(date: metadata.updatedAt),
                "updatedBy": metadata.updatedBy
            ], merge: true)

            return metadata
        } catch let appError as AppError {
            throw appError
        } catch {
            throw mapFirestoreError(error)
        }
    }

    private var homeBannerDocument: DocumentReference {
        database
            .collection(HomeBannerMetadata.collectionPath)
            .document(HomeBannerMetadata.documentID)
    }

    private func mapFirestoreError(_ error: Error) -> AppError {
        let nsError = error as NSError
        guard let code = FirestoreErrorCode.Code(rawValue: nsError.code) else {
            return .unknown
        }

        switch code {
        case .permissionDenied:
            return .permissionDenied
        case .notFound:
            return .notFound
        case .unavailable, .deadlineExceeded:
            return .network
        default:
            return .unknown
        }
    }
}

final class MockHomeBannerService: HomeBannerServiceProtocol {
    private var metadata: HomeBannerMetadata?

    init(metadata: HomeBannerMetadata? = nil) {
        self.metadata = metadata
    }

    func fetchHomeBanner() async throws -> HomeBannerMetadata? {
        metadata
    }

    func updateHomeBannerImage(data: Data, updatedBy userID: String) async throws -> HomeBannerMetadata {
        let updatedMetadata = HomeBannerMetadata(
            imageURL: "https://example.com/home-banner.jpg",
            storagePath: HomeBannerMetadata.storagePath,
            updatedAt: Date(),
            updatedBy: userID
        )
        metadata = updatedMetadata
        return updatedMetadata
    }
}
