import Foundation
import CoreGraphics
import FirebaseStorage
import ImageIO
import UniformTypeIdentifiers
import UIKit

final class ImageUploadService {
    static let shared = ImageUploadService()

    private let storage = Storage.storage()
    private let preferredImageWidths: [CGFloat] = [1600, 1200, 900, 700]
    private let preferredCompressionQualities: [CGFloat] = [0.75, 0.65, 0.55, 0.45, 0.40]
    private let maxUploadBytes = 3_000_000

    private init() {}

    func uploadNewsCoverImage(data: Data, newsID: String) async throws -> URL {
        try await uploadCoverImage(data: data, storagePath: "news/\(newsID)/cover.jpg")
    }

    func uploadEventCoverImage(data: Data, eventID: String) async throws -> URL {
        try await uploadCoverImage(data: data, storagePath: "events/\(eventID)/cover.jpg")
    }

    private func uploadCoverImage(data: Data, storagePath: String) async throws -> URL {
        let processingStartedAt = CFAbsoluteTimeGetCurrent()
        print("Image processing started")
        let processedImage = try await prepareImageDataForUpload(from: data)
        let processingDuration = CFAbsoluteTimeGetCurrent() - processingStartedAt
        let reference = storage.reference().child(storagePath)
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        do {
            print("Image processing finished with duration: \(processingDuration)s")
            print("Original data size: \(data.count) bytes")
            print("Final size: \(processedImage.data.count) bytes")
            print("Selected width: \(Int(processedImage.width))")
            print("Selected quality: \(processedImage.quality)")
            print("Upload path: \(storagePath)")
            let uploadStartedAt = CFAbsoluteTimeGetCurrent()
            print("Upload started")
            _ = try await reference.putDataAsync(processedImage.data, metadata: metadata)
            let uploadDuration = CFAbsoluteTimeGetCurrent() - uploadStartedAt
            print("Upload finished with duration: \(uploadDuration)s")
            print("Getting download URL")
            return try await reference.downloadURL()
        } catch {
            print("Upload failed: \(error)")
            throw error
        }
    }

    private func prepareImageDataForUpload(from data: Data) async throws -> ProcessedImageUploadData {
        let preferredImageWidths = preferredImageWidths
        let preferredCompressionQualities = preferredCompressionQualities
        let maxUploadBytes = maxUploadBytes

        return try await Task.detached(priority: .userInitiated) {
            try ImageUploadService.processImageData(
                data,
                preferredImageWidths: preferredImageWidths,
                preferredCompressionQualities: preferredCompressionQualities,
                maxUploadBytes: maxUploadBytes
            )
        }.value
    }

    nonisolated private static func processImageData(
        _ data: Data,
        preferredImageWidths: [CGFloat],
        preferredCompressionQualities: [CGFloat],
        maxUploadBytes: Int
    ) throws -> ProcessedImageUploadData {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImageUploadError.invalidImageData
        }

        var smallestAttempt: ProcessedImageUploadData?

        for width in preferredImageWidths {
            let resizedImage = normalizedImage(source: source, maxWidth: width)

            for quality in preferredCompressionQualities {
                guard let jpegData = jpegData(from: resizedImage, compressionQuality: quality) else {
                    throw ImageUploadError.invalidImageData
                }

                let attempt = ProcessedImageUploadData(
                    data: jpegData,
                    width: CGFloat(resizedImage.width),
                    quality: quality
                )

                if smallestAttempt == nil || attempt.data.count < smallestAttempt?.data.count ?? .max {
                    smallestAttempt = attempt
                }

                if jpegData.count < maxUploadBytes {
                    return attempt
                }
            }
        }

        if let smallestAttempt {
            print("Final size: \(smallestAttempt.data.count) bytes")
            print("Selected width: \(Int(smallestAttempt.width))")
            print("Selected quality: \(smallestAttempt.quality)")
        }
        throw ImageUploadError.imageTooLarge
    }

    nonisolated private static func normalizedImage(source: CGImageSource, maxWidth: CGFloat) -> CGImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceShouldCache: false,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxWidth.rounded(.up))
        ]

        if let normalizedImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return normalizedImage
        }

        guard let fallbackImage = CGImageSourceCreateImageAtIndex(source, 0, [
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else {
            fatalError("Expected valid image source after earlier validation")
        }

        return fallbackImage
    }

    nonisolated private static func jpegData(from image: CGImage, compressionQuality: CGFloat) -> Data? {
        let size = CGSize(width: image.width, height: image.height)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let renderedImage = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: size))
        }

        return renderedImage.jpegData(compressionQuality: compressionQuality)
    }
}

private struct ProcessedImageUploadData: Sendable {
    let data: Data
    let width: CGFloat
    let quality: CGFloat
}

private enum ImageUploadError: LocalizedError {
    case invalidImageData
    case imageTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidImageData:
            AppStrings.NewsEditor.imageProcessingFailed
        case .imageTooLarge:
            AppStrings.NewsEditor.imageTooLarge
        }
    }
}
