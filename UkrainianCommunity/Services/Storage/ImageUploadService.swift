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

    func uploadOrganizationNewsDraftImage(data: Data, organizationID: String, newsID: String) async throws -> URL {
        try await uploadCoverImage(
            data: data,
            storagePath: organizationNewsDraftImagePath(organizationID: organizationID, newsID: newsID)
        )
    }

    func deleteOrganizationNewsDraftImage(organizationID: String, newsID: String) async throws {
        try await storage.reference()
            .child(organizationNewsDraftImagePath(organizationID: organizationID, newsID: newsID))
            .delete()
    }

    func uploadEventCoverImage(data: Data, eventID: String) async throws -> URL {
        try await uploadCoverImage(data: data, storagePath: "events/\(eventID)/cover.jpg")
    }

    func uploadOrganizationEventDraftImage(data: Data, organizationID: String, eventID: String) async throws -> URL {
        try await uploadCoverImage(
            data: data,
            storagePath: organizationEventDraftImagePath(organizationID: organizationID, eventID: eventID)
        )
    }

    func deleteOrganizationEventDraftImage(organizationID: String, eventID: String) async throws {
        try await storage.reference()
            .child(organizationEventDraftImagePath(organizationID: organizationID, eventID: eventID))
            .delete()
    }

    func uploadOrganizationLogoImage(data: Data, organizationID: String) async throws -> URL {
        try await uploadCoverImage(
            data: data,
            storagePath: "organizations/\(organizationID)/logo.jpg",
            rendersOpaqueJPEG: true
        )
    }

    func uploadOrganizationPhoto(data: Data, organizationID: String, photoID: String) async throws -> URL {
        try await uploadCoverImage(data: data, storagePath: "organizations/\(organizationID)/photos/\(photoID).jpg")
    }

    func deleteOrganizationPhoto(organizationID: String, photoID: String) async throws {
        try await storage.reference().child("organizations/\(organizationID)/photos/\(photoID).jpg").delete()
    }

    func uploadProfileAvatarImage(data: Data, userID: String) async throws -> URL {
        try await uploadCoverImage(data: data, storagePath: "profileImages/\(userID)/avatar.jpg")
    }

    func uploadHomeBannerImage(data: Data) async throws -> URL {
        try await uploadCoverImage(data: data, storagePath: HomeBannerMetadata.storagePath)
    }

    func uploadAppConfigBannerImage(data: Data, storagePath: String) async throws -> URL {
        try await uploadCoverImage(data: data, storagePath: storagePath)
    }

    func prepareEditorPreviewImageData(from data: Data) async throws -> Data {
        let preferredPreviewWidths: [CGFloat] = [1600, 1400, 1200]
        let preferredPreviewQualities: [CGFloat] = [0.82, 0.78, 0.75]
        let maxPreviewBytes = 2_500_000

        return try await Task.detached(priority: .userInitiated) {
            try ImageUploadService.processImageData(
                data,
                preferredImageWidths: preferredPreviewWidths,
                preferredCompressionQualities: preferredPreviewQualities,
                maxUploadBytes: maxPreviewBytes
            ).data
        }.value
    }

    func prepareEditorImageSelection(from data: Data) async throws -> PreparedEditorImageSelection {
        let preferredPreviewWidths: [CGFloat] = [1600, 1400, 1200]
        let preferredPreviewQualities: [CGFloat] = [0.82, 0.78, 0.75]
        let maxPreviewBytes = 2_500_000

        return try await Task.detached(priority: .userInitiated) {
            let processedImage = try ImageUploadService.processImageData(
                data,
                preferredImageWidths: preferredPreviewWidths,
                preferredCompressionQualities: preferredPreviewQualities,
                maxUploadBytes: maxPreviewBytes
            )
            guard let previewImage = UIImage(data: processedImage.data) else {
                throw ImageUploadError.invalidImageData
            }
            return PreparedEditorImageSelection(data: processedImage.data, previewImage: previewImage)
        }.value
    }

    func prepareOrganizationLogoSelection(from data: Data) async throws -> PreparedEditorImageSelection {
        let preferredLogoWidths: [CGFloat] = [1024, 768]
        let preferredLogoQualities: [CGFloat] = [0.82, 0.76, 0.70]
        let maxLogoBytes = 1_500_000

        return try await Task.detached(priority: .userInitiated) {
            let processedImage = try ImageUploadService.processImageData(
                data,
                preferredImageWidths: preferredLogoWidths,
                preferredCompressionQualities: preferredLogoQualities,
                maxUploadBytes: maxLogoBytes,
                rendersOpaqueJPEG: true
            )
            guard let previewImage = UIImage(data: processedImage.data) else {
                throw ImageUploadError.invalidImageData
            }
            return PreparedEditorImageSelection(data: processedImage.data, previewImage: previewImage)
        }.value
    }

    private func uploadCoverImage(
        data: Data,
        storagePath: String,
        rendersOpaqueJPEG: Bool = false
    ) async throws -> URL {
        let processedImage = try await prepareImageDataForUpload(from: data, rendersOpaqueJPEG: rendersOpaqueJPEG)
        let reference = storage.reference().child(storagePath)
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        _ = try await reference.putDataAsync(processedImage.data, metadata: metadata)
        return try await reference.downloadURL()
    }

    private func organizationNewsDraftImagePath(organizationID: String, newsID: String) -> String {
        "organizations/\(organizationID)/draftUploads/news/\(newsID)_cover.jpg"
    }

    private func organizationEventDraftImagePath(organizationID: String, eventID: String) -> String {
        "organizations/\(organizationID)/draftUploads/events/\(eventID)_cover.jpg"
    }

    private func prepareImageDataForUpload(
        from data: Data,
        rendersOpaqueJPEG: Bool = false
    ) async throws -> ProcessedImageUploadData {
        let preferredImageWidths = preferredImageWidths
        let preferredCompressionQualities = preferredCompressionQualities
        let maxUploadBytes = maxUploadBytes

        return try await Task.detached(priority: .userInitiated) {
            try ImageUploadService.processImageData(
                data,
                preferredImageWidths: preferredImageWidths,
                preferredCompressionQualities: preferredCompressionQualities,
                maxUploadBytes: maxUploadBytes,
                rendersOpaqueJPEG: rendersOpaqueJPEG
            )
        }.value
    }

    nonisolated private static func processImageData(
        _ data: Data,
        preferredImageWidths: [CGFloat],
        preferredCompressionQualities: [CGFloat],
        maxUploadBytes: Int,
        rendersOpaqueJPEG: Bool = false
    ) throws -> ProcessedImageUploadData {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImageUploadError.invalidImageData
        }

        for width in preferredImageWidths {
            let resizedImage = try normalizedImage(source: source, maxWidth: width)
            let uploadImage = rendersOpaqueJPEG ? try opaqueRGBImage(from: resizedImage) : resizedImage

            for quality in preferredCompressionQualities {
                guard let jpegData = jpegData(from: uploadImage, compressionQuality: quality) else {
                    throw ImageUploadError.invalidImageData
                }

                let attempt = ProcessedImageUploadData(
                    data: jpegData,
                    width: CGFloat(uploadImage.width),
                    quality: quality
                )

                if jpegData.count < maxUploadBytes {
                    return attempt
                }
            }
        }

        throw ImageUploadError.imageTooLarge
    }

    nonisolated private static func normalizedImage(source: CGImageSource, maxWidth: CGFloat) throws -> CGImage {
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
            throw ImageUploadError.invalidImageData
        }

        return fallbackImage
    }

    nonisolated private static func opaqueRGBImage(from image: CGImage) throws -> CGImage {
        let width = image.width
        let height = image.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw ImageUploadError.invalidImageData
        }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let opaqueImage = context.makeImage() else {
            throw ImageUploadError.invalidImageData
        }

        return opaqueImage
    }

    nonisolated private static func jpegData(from image: CGImage, compressionQuality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: compressionQuality
        ]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            return nil
        }

        return data as Data
    }
}

private struct ProcessedImageUploadData: Sendable {
    let data: Data
    let width: CGFloat
    let quality: CGFloat
}

struct PreparedEditorImageSelection: @unchecked Sendable {
    let data: Data
    let previewImage: UIImage
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
