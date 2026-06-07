import Foundation
import CoreGraphics
import FirebaseStorage
import ImageIO
import UniformTypeIdentifiers

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

    func uploadNewsCoverImage(processedImage: ProcessedImageSelection, newsID: String) async throws -> URL {
        try await uploadProcessedImage(
            data: processedImage.data,
            contentType: processedImage.contentType,
            storagePath: "news/\(newsID)/cover.jpg"
        )
    }

    func uploadOrganizationNewsDraftImage(data: Data, organizationID: String, newsID: String) async throws -> URL {
        try await uploadCoverImage(
            data: data,
            storagePath: organizationNewsDraftImagePath(organizationID: organizationID, newsID: newsID)
        )
    }

    func uploadOrganizationNewsDraftImage(processedImage: ProcessedImageSelection, organizationID: String, newsID: String) async throws -> URL {
        try await uploadProcessedImage(
            data: processedImage.data,
            contentType: processedImage.contentType,
            storagePath: organizationNewsDraftImagePath(organizationID: organizationID, newsID: newsID)
        )
    }

    func deleteOrganizationNewsDraftImage(organizationID: String, newsID: String) async throws {
        do {
            try await storage.reference()
                .child(organizationNewsDraftImagePath(organizationID: organizationID, newsID: newsID))
                .delete()
        } catch {
            await SystemTechnicalErrorLoggingService.shared.logFailure(
                error,
                context: SystemTechnicalErrorContext(
                    moduleName: "Storage",
                    operationName: "deleteOrganizationNewsDraftImage",
                    targetType: .newsPost,
                    targetId: newsID,
                    organizationId: organizationID,
                    metadata: ["storageArea": "organizationNewsDraftImage"]
                )
            )
            throw error
        }
    }

    func uploadEventCoverImage(data: Data, eventID: String) async throws -> URL {
        try await uploadCoverImage(data: data, storagePath: "events/\(eventID)/cover.jpg")
    }

    func uploadEventCoverImage(processedImage: ProcessedImageSelection, eventID: String) async throws -> URL {
        try await uploadProcessedImage(
            data: processedImage.data,
            contentType: processedImage.contentType,
            storagePath: "events/\(eventID)/cover.jpg"
        )
    }

    func uploadOrganizationEventDraftImage(data: Data, organizationID: String, eventID: String) async throws -> URL {
        try await uploadCoverImage(
            data: data,
            storagePath: organizationEventDraftImagePath(organizationID: organizationID, eventID: eventID)
        )
    }

    func uploadOrganizationEventDraftImage(processedImage: ProcessedImageSelection, organizationID: String, eventID: String) async throws -> URL {
        try await uploadProcessedImage(
            data: processedImage.data,
            contentType: processedImage.contentType,
            storagePath: organizationEventDraftImagePath(organizationID: organizationID, eventID: eventID)
        )
    }

    func deleteOrganizationEventDraftImage(organizationID: String, eventID: String) async throws {
        do {
            try await storage.reference()
                .child(organizationEventDraftImagePath(organizationID: organizationID, eventID: eventID))
                .delete()
        } catch {
            await SystemTechnicalErrorLoggingService.shared.logFailure(
                error,
                context: SystemTechnicalErrorContext(
                    moduleName: "Storage",
                    operationName: "deleteOrganizationEventDraftImage",
                    targetType: .event,
                    targetId: eventID,
                    organizationId: organizationID,
                    metadata: ["storageArea": "organizationEventDraftImage"]
                )
            )
            throw error
        }
    }

    func uploadOrganizationLogoImage(data: Data, organizationID: String) async throws -> URL {
        try await uploadCoverImage(
            data: data,
            storagePath: "organizations/\(organizationID)/logo.jpg",
            rendersOpaqueJPEG: true
        )
    }

    func uploadOrganizationLogoImage(processedImage: ProcessedImageSelection, organizationID: String) async throws -> URL {
        try await uploadProcessedImage(
            data: processedImage.data,
            contentType: processedImage.contentType,
            storagePath: "organizations/\(organizationID)/logo.jpg"
        )
    }

    func uploadOrganizationPhoto(data: Data, organizationID: String, photoID: String) async throws -> URL {
        try await uploadCoverImage(data: data, storagePath: "organizations/\(organizationID)/photos/\(photoID).jpg")
    }

    func uploadOrganizationPhoto(processedImage: ProcessedImageSelection, organizationID: String, photoID: String) async throws -> URL {
        try await uploadProcessedImage(
            data: processedImage.data,
            contentType: processedImage.contentType,
            storagePath: "organizations/\(organizationID)/photos/\(photoID).jpg"
        )
    }

    func deleteOrganizationPhoto(organizationID: String, photoID: String) async throws {
        do {
            try await storage.reference().child("organizations/\(organizationID)/photos/\(photoID).jpg").delete()
        } catch {
            await SystemTechnicalErrorLoggingService.shared.logFailure(
                error,
                context: SystemTechnicalErrorContext(
                    moduleName: "Storage",
                    operationName: "deleteOrganizationPhoto",
                    targetType: .organization,
                    targetId: photoID,
                    organizationId: organizationID,
                    metadata: ["storageArea": "organizationPhoto"]
                )
            )
            throw error
        }
    }

    func uploadProfileAvatarImage(data: Data, userID: String) async throws -> URL {
        try await uploadCoverImage(data: data, storagePath: "profileImages/\(userID)/avatar.jpg")
    }

    func uploadProfileAvatarImage(processedImage: ProcessedImageSelection, userID: String) async throws -> URL {
        try await uploadProcessedImage(
            data: processedImage.data,
            contentType: processedImage.contentType,
            storagePath: "profileImages/\(userID)/avatar.jpg"
        )
    }

    func uploadFeaturedBannerImage(bannerId: String, imageData: Data) async throws -> URL {
        let processedImage = try await ImageProcessingService.process(data: imageData, profile: .hero16x9)
        return try await uploadFeaturedBannerImage(bannerId: bannerId, processedImage: processedImage)
    }

    func uploadFeaturedBannerImage(bannerId: String, processedImage: ProcessedImageSelection) async throws -> URL {
        return try await uploadProcessedImage(
            data: processedImage.data,
            contentType: processedImage.contentType,
            storagePath: "featuredBanners/\(bannerId)/hero.jpg",
        )
    }

    private func uploadCoverImage(
        data: Data,
        storagePath: String,
        rendersOpaqueJPEG: Bool = false
    ) async throws -> URL {
        let processedImage = try await prepareImageDataForUpload(from: data, rendersOpaqueJPEG: rendersOpaqueJPEG)
        return try await uploadProcessedImage(data: processedImage.data, contentType: "image/jpeg", storagePath: storagePath)
    }

    private func uploadProcessedImage(data: Data, contentType: String, storagePath: String) async throws -> URL {
        let reference = storage.reference().child(storagePath)
        let metadata = StorageMetadata()
        metadata.contentType = contentType

        do {
            _ = try await reference.putDataAsync(data, metadata: metadata)
            return try await reference.downloadURL()
        } catch {
            await SystemTechnicalErrorLoggingService.shared.logFailure(
                error,
                context: SystemTechnicalErrorContext(
                    moduleName: "Storage",
                    operationName: "uploadProcessedImage",
                    targetType: storageTargetType(for: storagePath),
                    targetId: storageTargetId(for: storagePath),
                    organizationId: storageOrganizationId(for: storagePath),
                    metadata: [
                        "storageArea": storageArea(for: storagePath),
                        "contentType": contentType,
                        "byteCount": "\(data.count)"
                    ]
                )
            )
            throw error
        }
    }

    private func storageArea(for storagePath: String) -> String {
        if storagePath.hasPrefix("news/") { return "news" }
        if storagePath.hasPrefix("events/") { return "events" }
        if storagePath.hasPrefix("organizations/") { return "organizations" }
        if storagePath.hasPrefix("profileImages/") { return "profileImages" }
        if storagePath.hasPrefix("featuredBanners/") { return "featuredBanners" }
        return "unknown"
    }

    private func storageTargetType(for storagePath: String) -> SystemLogTargetType {
        if storagePath.hasPrefix("news/") { return .newsPost }
        if storagePath.hasPrefix("events/") { return .event }
        if storagePath.hasPrefix("organizations/") { return .organization }
        if storagePath.hasPrefix("profileImages/") { return .userProfile }
        if storagePath.hasPrefix("featuredBanners/") { return .systemConfiguration }
        return .unknown
    }

    private func storageTargetId(for storagePath: String) -> String? {
        let parts = storagePath.split(separator: "/").map(String.init)
        guard parts.count > 1 else { return nil }

        if parts.first == "organizations", parts.count >= 4, parts[2] == "photos" {
            return parts[3].replacingOccurrences(of: ".jpg", with: "")
        }

        return parts[1]
            .replacingOccurrences(of: ".jpg", with: "")
            .replacingOccurrences(of: "_cover", with: "")
    }

    private func storageOrganizationId(for storagePath: String) -> String? {
        let parts = storagePath.split(separator: "/").map(String.init)
        guard parts.first == "organizations", parts.count > 1 else { return nil }
        return parts[1]
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
