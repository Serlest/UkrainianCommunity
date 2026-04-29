import Foundation
import FirebaseStorage

final class ImageUploadService {
    static let shared = ImageUploadService()

    private let storage = Storage.storage()

    private init() {}

    func uploadNewsCoverImage(data: Data, newsID: String) async throws -> URL {
        let reference = storage.reference().child("news/\(newsID)/cover.jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        do {
            print("Upload started")
            _ = try await reference.putDataAsync(data, metadata: metadata)
            print("Upload completed")
            print("Getting download URL")
            return try await reference.downloadURL()
        } catch {
            print("Upload failed: \(error)")
            throw error
        }
    }
}
