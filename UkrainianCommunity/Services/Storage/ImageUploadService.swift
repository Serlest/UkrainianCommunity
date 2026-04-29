import Foundation
import FirebaseStorage
import UIKit

final class ImageUploadService {
    static let shared = ImageUploadService()

    private let storage = Storage.storage()
    private let preferredImageWidths: [CGFloat] = [1600, 1200, 900]
    private let preferredCompressionQualities: [CGFloat] = [0.75, 0.65, 0.55, 0.45]
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

        for width in preferredImageWidths {
            let resizedImage = resizedImageIfNeeded(image, maxWidth: width)

            for quality in preferredCompressionQualities {
                guard let jpegData = resizedImage.jpegData(compressionQuality: quality) else {
                    throw ImageUploadError.invalidImageData
                }

                if jpegData.count < maxUploadBytes {
                    print("Compression width used: \(Int(width))")
                    print("Compression quality used: \(quality)")
                    print("Compression final size: \(jpegData.count) bytes")
                    return jpegData
                }
            }
        }

        throw ImageUploadError.imageTooLarge
    }

    private func resizedImageIfNeeded(_ image: UIImage, maxWidth: CGFloat) -> UIImage {
        let originalSize = image.size
        guard originalSize.width > maxWidth else {
            return image
        }

        let scale = maxWidth / originalSize.width
        let targetSize = CGSize(
            width: maxWidth,
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
