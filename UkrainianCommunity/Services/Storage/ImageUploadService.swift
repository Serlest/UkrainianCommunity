import Foundation
import FirebaseStorage
import UIKit

final class ImageUploadService {
    static let shared = ImageUploadService()

    private let storage = Storage.storage()
    private let maxImageWidth: CGFloat = 1600
    private let maxUploadBytes = 1_000_000

    private init() {}

    func uploadNewsCoverImage(data: Data, newsID: String) async throws -> URL {
        let processedData = try prepareImageDataForUpload(from: data)
        let reference = storage.reference().child("news/\(newsID)/cover.jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        do {
            print("Original data size: \(data.count) bytes")
            print("Compressed data size: \(processedData.count) bytes")
            print("Upload path: news/\(newsID)/cover.jpg")
            print("Upload started")
            _ = try await reference.putDataAsync(processedData, metadata: metadata)
            print("Upload completed")
            print("Getting download URL")
            return try await reference.downloadURL()
        } catch {
            print("Upload failed: \(error)")
            throw error
        }
    }

    private func prepareImageDataForUpload(from data: Data) throws -> Data {
        guard let image = UIImage(data: data) else {
            throw ImageUploadError.invalidImageData
        }

        let resizedImage = resizedImageIfNeeded(image)

        guard let jpegData = resizedImage.jpegData(compressionQuality: 0.75) else {
            throw ImageUploadError.invalidImageData
        }

        guard jpegData.count < maxUploadBytes else {
            throw ImageUploadError.imageTooLarge
        }

        return jpegData
    }

    private func resizedImageIfNeeded(_ image: UIImage) -> UIImage {
        let originalSize = image.size
        guard originalSize.width > maxImageWidth else {
            return image
        }

        let scale = maxImageWidth / originalSize.width
        let targetSize = CGSize(
            width: maxImageWidth,
            height: originalSize.height * scale
        )

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

private enum ImageUploadError: LocalizedError {
    case invalidImageData
    case imageTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidImageData:
            "Failed to process the selected image."
        case .imageTooLarge:
            "Image is too large. Please choose a smaller photo."
        }
    }
}
