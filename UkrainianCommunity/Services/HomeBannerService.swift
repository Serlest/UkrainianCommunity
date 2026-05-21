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

enum AppHeroBannerSection: String, CaseIterable {
    case home
    case events
    case organizations
    case guide

    var documentID: String {
        switch self {
        case .home:
            "homeBanner"
        case .events:
            "eventsBanner"
        case .organizations:
            "organizationsBanner"
        case .guide:
            "guideBanner"
        }
    }

    var storagePath: String {
        "appConfig/\(documentID)/banner.jpg"
    }
}

protocol HomeBannerServiceProtocol {
    func fetchHomeBanner() async throws -> HomeBannerMetadata?
    func updateHomeBannerImage(data: Data, updatedBy userID: String) async throws -> HomeBannerMetadata
    func fetchBanner(for section: AppHeroBannerSection) async throws -> HomeBannerMetadata?
    func updateBannerImage(data: Data, for section: AppHeroBannerSection, updatedBy userID: String) async throws -> HomeBannerMetadata
}

final class FirestoreHomeBannerService: HomeBannerServiceProtocol {
    private let database = Firestore.firestore()
    private let imageUploadService: ImageUploadService

    init(imageUploadService: ImageUploadService = .shared) {
        self.imageUploadService = imageUploadService
    }

    func fetchHomeBanner() async throws -> HomeBannerMetadata? {
        try await fetchBanner(for: .home)
    }

    func updateHomeBannerImage(data: Data, updatedBy userID: String) async throws -> HomeBannerMetadata {
        try await updateBannerImage(data: data, for: .home, updatedBy: userID)
    }

    func fetchBanner(for section: AppHeroBannerSection) async throws -> HomeBannerMetadata? {
        do {
            let snapshot = try await bannerDocument(for: section).getDocument()
            guard snapshot.exists, let data = snapshot.data() else {
                return nil
            }

            guard let imageURL = data["imageURL"] as? String, !imageURL.isEmpty else {
                return nil
            }

            return HomeBannerMetadata(
                imageURL: imageURL,
                storagePath: data["storagePath"] as? String ?? section.storagePath,
                updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? .distantPast,
                updatedBy: data["updatedBy"] as? String ?? ""
            )
        } catch {
            throw mapFirestoreError(error)
        }
    }

    func updateBannerImage(data: Data, for section: AppHeroBannerSection, updatedBy userID: String) async throws -> HomeBannerMetadata {
        do {
            let uploadedURL = try await imageUploadService.uploadAppConfigBannerImage(data: data, storagePath: section.storagePath)
            let updatedAt = Date()
            let metadata = HomeBannerMetadata(
                imageURL: uploadedURL.absoluteString,
                storagePath: section.storagePath,
                updatedAt: updatedAt,
                updatedBy: userID
            )

            try await bannerDocument(for: section).setData([
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

    private func bannerDocument(for section: AppHeroBannerSection) -> DocumentReference {
        database
            .collection(HomeBannerMetadata.collectionPath)
            .document(section.documentID)
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
    private var metadataBySection: [AppHeroBannerSection: HomeBannerMetadata]

    init(metadata: HomeBannerMetadata? = nil) {
        if let metadata {
            metadataBySection = [.home: metadata]
        } else {
            metadataBySection = [:]
        }
    }

    func fetchHomeBanner() async throws -> HomeBannerMetadata? {
        try await fetchBanner(for: .home)
    }

    func updateHomeBannerImage(data: Data, updatedBy userID: String) async throws -> HomeBannerMetadata {
        try await updateBannerImage(data: data, for: .home, updatedBy: userID)
    }

    func fetchBanner(for section: AppHeroBannerSection) async throws -> HomeBannerMetadata? {
        metadataBySection[section]
    }

    func updateBannerImage(data: Data, for section: AppHeroBannerSection, updatedBy userID: String) async throws -> HomeBannerMetadata {
        let updatedMetadata = HomeBannerMetadata(
            imageURL: "https://example.com/\(section.documentID).jpg",
            storagePath: section.storagePath,
            updatedAt: Date(),
            updatedBy: userID
        )
        metadataBySection[section] = updatedMetadata
        return updatedMetadata
    }
}
