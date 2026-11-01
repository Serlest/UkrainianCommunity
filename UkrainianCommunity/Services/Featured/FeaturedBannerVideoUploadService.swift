import FirebaseAuth
import FirebaseCore
import FirebaseFunctions
import FirebaseStorage
import Foundation

@MainActor final class FeaturedBannerVideoUploadService {
    static let shared = FeaturedBannerVideoUploadService()
    func copy(_ video: FeaturedBannerVideoPresentation, from sourceID: String, to bannerID: String,
              uploadID: String, principal: String) async throws -> FeaturedBannerVideoPresentation {
        guard Auth.auth().currentUser?.uid == principal, let bucket = FirebaseApp.app()?.options.storageBucket,
              video.isValid(for: sourceID, bucket: bucket) else { throw AppError.permissionDenied }
        // Duplication uses the same bounded, checksum-verified downloader as playback.
        // Its cached file remains owned by the cache, never by this upload attempt.
        let file = try await FeaturedBannerVideoCache.shared.file(for: video, allowsConstrainedNetwork: true)
        try Task.checkCancellation()
        return try await upload(file: file, bannerID: bannerID, uploadID: uploadID, principal: principal, resuming: true)
    }

    /// A stable upload ID must be reused after a lost callable reply.
    func upload(file: URL, bannerID: String, uploadID: String, principal: String, resuming: Bool = false) async throws -> FeaturedBannerVideoPresentation {
        guard Auth.auth().currentUser?.uid == principal,
              FeaturedBannerVideoPolicy.isSafeComponent(bannerID), FeaturedBannerVideoPolicy.isSafeComponent(uploadID),
              let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              (1...FeaturedBannerVideoPolicy.maximumRenditionBytes).contains(size) else { throw AppError.validationFailed }
        let reference = Storage.storage().reference(withPath: "featuredBannerVideoUploads/\(principal)/\(bannerID)/\(uploadID).mp4")
        let metadata = StorageMetadata(); metadata.contentType = "video/mp4"
        // A previous upload can already have been consumed; the callable receipt resolves retries.
        let function = Functions.functions(region: "europe-west3").httpsCallable("prepareFeaturedBannerVideo")
        function.timeoutInterval = 60
        func verify(_ raw: Any) throws -> FeaturedBannerVideoPresentation {
            let data = try JSONSerialization.data(withJSONObject: raw)
            let value = try JSONDecoder().decode(FeaturedBannerVideoPresentation.self, from: data)
            guard let bucket = FirebaseApp.app()?.options.storageBucket,
                  value.isValid(for: bannerID, bucket: bucket), Auth.auth().currentUser?.uid == principal else { throw AppError.permissionDenied }
            return value
        }
        // Prepare may succeed from an existing receipt without uploading a second copy.
        if resuming {
            do { let result = try await function.call(["bannerID": bannerID, "uploadID": uploadID]); return try verify(result.data) }
            catch {
                let failure = error as NSError
                guard failure.domain == FunctionsErrorDomain,
                      FunctionsErrorCode(rawValue: failure.code) == .notFound else { throw error }
            }
        }
        try Task.checkCancellation()
        _ = try await reference.putFileAsync(from: file, metadata: metadata)
        try Task.checkCancellation()
        guard Auth.auth().currentUser?.uid == principal else { throw AppError.permissionDenied }
        let result = try await function.call(["bannerID": bannerID, "uploadID": uploadID])
        return try verify(result.data)
    }
}
