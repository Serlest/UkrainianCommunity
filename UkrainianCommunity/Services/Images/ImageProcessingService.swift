import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageProcessingService {
    static func process(data: Data, profile: ImageSelectionProfile) async throws -> ProcessedImageSelection {
        try await Task.detached(priority: .userInitiated) {
            try processSynchronously(data: data, profile: profile)
        }.value
    }

    static func process(cgImage: CGImage, profile: ImageSelectionProfile) async throws -> ProcessedImageSelection {
        try await Task.detached(priority: .userInitiated) {
            try processSynchronously(cgImage: cgImage, profile: profile)
        }.value
    }

    nonisolated static func readDimensions(from data: Data) throws -> ImageSourceDimensions {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImageProcessingError.invalidImageData
        }
        return try readDimensions(from: source)
    }

    nonisolated static func validateAspectRatio(_ dimensions: ImageSourceDimensions, profile: ImageSelectionProfile) throws {
        guard let range = profile.allowedAspectRatioRange else { return }
        guard range.contains(dimensions.displayedAspectRatio) else {
            throw ImageProcessingError.unsupportedAspectRatio(profile: profile)
        }
    }

    nonisolated private static func processSynchronously(data: Data, profile: ImageSelectionProfile) throws -> ProcessedImageSelection {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImageProcessingError.invalidImageData
        }

        let dimensions = try readDimensions(from: source)
        try validateAspectRatio(dimensions, profile: profile)

        let resizedImage = try normalizedImage(source: source, maxPixelDimension: profile.maxPixelDimension)
        let renderedImage = try renderedImageForOutput(resizedImage, profile: profile)
        let encodedData = try encodedDataUnderLimit(from: renderedImage, profile: profile)

        return ProcessedImageSelection(
            data: encodedData.data,
            outputFormat: profile.outputFormat,
            contentType: profile.outputFormat.contentType,
            dimensions: dimensions,
            renderedWidth: CGFloat(renderedImage.width),
            renderedHeight: CGFloat(renderedImage.height),
            compressionQuality: encodedData.quality
        )
    }

    nonisolated private static func processSynchronously(cgImage: CGImage, profile: ImageSelectionProfile) throws -> ProcessedImageSelection {
        let exactAspectImage = try imageRenderedToExactAspectIfNeeded(cgImage, profile: profile)
        let dimensions = ImageSourceDimensions(
            pixelWidth: CGFloat(exactAspectImage.width),
            pixelHeight: CGFloat(exactAspectImage.height),
            displayedWidth: CGFloat(exactAspectImage.width),
            displayedHeight: CGFloat(exactAspectImage.height),
            orientation: nil
        )
        try validateAspectRatio(dimensions, profile: profile)

        let renderedImage = try renderedImageForOutput(exactAspectImage, profile: profile)
        let encodedData = try encodedDataUnderLimit(from: renderedImage, profile: profile)

        return ProcessedImageSelection(
            data: encodedData.data,
            outputFormat: profile.outputFormat,
            contentType: profile.outputFormat.contentType,
            dimensions: dimensions,
            renderedWidth: CGFloat(renderedImage.width),
            renderedHeight: CGFloat(renderedImage.height),
            compressionQuality: encodedData.quality
        )
    }

    nonisolated private static func imageRenderedToExactAspectIfNeeded(_ image: CGImage, profile: ImageSelectionProfile) throws -> CGImage {
        guard let targetAspectRatio = profile.targetAspectRatio else {
            return try resizedImageIfNeeded(image, maxPixelDimension: profile.maxPixelDimension)
        }

        let targetSize = exactOutputSize(for: image, targetAspectRatio: targetAspectRatio, maxPixelDimension: profile.maxPixelDimension)
        guard targetSize.width > 0, targetSize.height > 0 else {
            throw ImageProcessingError.invalidImageData
        }

        if image.width == Int(targetSize.width) && image.height == Int(targetSize.height) {
            return image
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: Int(targetSize.width),
            height: Int(targetSize.height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw ImageProcessingError.invalidImageData
        }

        let drawRect = aspectFillRect(
            sourceSize: CGSize(width: image.width, height: image.height),
            targetSize: targetSize
        )
        context.interpolationQuality = CGInterpolationQuality.high
        context.draw(image, in: drawRect)

        guard let renderedImage = context.makeImage() else {
            throw ImageProcessingError.invalidImageData
        }
        return renderedImage
    }

    nonisolated private static func exactOutputSize(
        for image: CGImage,
        targetAspectRatio: CGFloat,
        maxPixelDimension: CGFloat
    ) -> CGSize {
        let sourceWidth = CGFloat(image.width)
        let sourceHeight = CGFloat(image.height)
        let sourceMaxDimension = max(sourceWidth, sourceHeight)
        let outputMaxDimension = max(1, min(maxPixelDimension, sourceMaxDimension))

        if targetAspectRatio >= 1 {
            var width = outputMaxDimension
            var height = (width / targetAspectRatio).rounded()
            if height > sourceHeight {
                height = min(sourceHeight, outputMaxDimension)
                width = (height * targetAspectRatio).rounded()
            }
            return CGSize(width: CGFloat(max(1, Int(width))), height: CGFloat(max(1, Int(height))))
        } else {
            var height = outputMaxDimension
            var width = (height * targetAspectRatio).rounded()
            if width > sourceWidth {
                width = min(sourceWidth, outputMaxDimension)
                height = (width / targetAspectRatio).rounded()
            }
            return CGSize(width: CGFloat(max(1, Int(width))), height: CGFloat(max(1, Int(height))))
        }
    }

    nonisolated private static func aspectFillRect(sourceSize: CGSize, targetSize: CGSize) -> CGRect {
        let scale = max(targetSize.width / sourceSize.width, targetSize.height / sourceSize.height)
        let scaledSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        return CGRect(
            x: (targetSize.width - scaledSize.width) / 2,
            y: (targetSize.height - scaledSize.height) / 2,
            width: scaledSize.width,
            height: scaledSize.height
        )
    }

    nonisolated private static func readDimensions(from source: CGImageSource) throws -> ImageSourceDimensions {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidthValue = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let pixelHeightValue = properties[kCGImagePropertyPixelHeight] as? NSNumber
        else {
            throw ImageProcessingError.invalidImageData
        }

        let pixelWidth = CGFloat(truncating: pixelWidthValue)
        let pixelHeight = CGFloat(truncating: pixelHeightValue)
        guard pixelWidth > 0, pixelHeight > 0 else {
            throw ImageProcessingError.invalidImageData
        }

        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue
        let swapsDimensions = [5, 6, 7, 8].contains(orientation)
        let displayedWidth = swapsDimensions ? pixelHeight : pixelWidth
        let displayedHeight = swapsDimensions ? pixelWidth : pixelHeight

        return ImageSourceDimensions(
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            displayedWidth: displayedWidth,
            displayedHeight: displayedHeight,
            orientation: orientation
        )
    }

    nonisolated private static func normalizedImage(source: CGImageSource, maxPixelDimension: CGFloat) throws -> CGImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceShouldCache: false,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixelDimension.rounded(.up))
        ]

        if let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return image
        }

        guard let fallbackImage = CGImageSourceCreateImageAtIndex(source, 0, [
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceShouldCache: false
        ] as CFDictionary) else {
            throw ImageProcessingError.invalidImageData
        }
        return fallbackImage
    }

    nonisolated private static func renderedImageForOutput(_ image: CGImage, profile: ImageSelectionProfile) throws -> CGImage {
        switch profile.outputFormat {
        case .jpeg:
            guard profile.rendersOpaqueJPEG else { return image }
            return try opaqueRGBImage(from: image)
        }
    }

    nonisolated private static func resizedImageIfNeeded(_ image: CGImage, maxPixelDimension: CGFloat) throws -> CGImage {
        let currentMaxDimension = max(image.width, image.height)
        guard CGFloat(currentMaxDimension) > maxPixelDimension else {
            return image
        }

        let scale = maxPixelDimension / CGFloat(currentMaxDimension)
        let targetWidth = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let targetHeight = max(1, Int((CGFloat(image.height) * scale).rounded()))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw ImageProcessingError.invalidImageData
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        guard let resizedImage = context.makeImage() else {
            throw ImageProcessingError.invalidImageData
        }
        return resizedImage
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
            throw ImageProcessingError.invalidImageData
        }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let opaqueImage = context.makeImage() else {
            throw ImageProcessingError.invalidImageData
        }
        return opaqueImage
    }

    nonisolated private static func encodedDataUnderLimit(from image: CGImage, profile: ImageSelectionProfile) throws -> (data: Data, quality: CGFloat) {
        let qualityCandidates = qualitySteps(from: profile.jpegQuality)
        for quality in qualityCandidates {
            guard let data = jpegData(from: image, compressionQuality: quality) else {
                throw ImageProcessingError.invalidImageData
            }
            if data.count < profile.maxBytes {
                return (data, quality)
            }
        }
        throw ImageProcessingError.imageTooLarge(profile: profile)
    }

    nonisolated private static func qualitySteps(from initialQuality: CGFloat) -> [CGFloat] {
        let clampedInitialQuality = min(max(initialQuality, 0.1), 1)
        var qualities: [CGFloat] = [clampedInitialQuality]
        var nextQuality = min(clampedInitialQuality - 0.07, 0.75)
        while nextQuality >= 0.40 {
            qualities.append(nextQuality)
            nextQuality -= 0.07
        }
        if !qualities.contains(0.35) {
            qualities.append(0.35)
        }
        return qualities
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

enum ImageProcessingError: LocalizedError {
    case invalidImageData
    case unsupportedAspectRatio(profile: ImageSelectionProfile)
    case imageTooLarge(profile: ImageSelectionProfile)

    var errorDescription: String? {
        switch self {
        case .invalidImageData:
            AppStrings.NewsEditor.imageProcessingFailed
        case let .unsupportedAspectRatio(profile):
            Self.localizedErrorMessage(for: profile.aspectRatioErrorKey) ?? AppStrings.NewsEditor.imageProcessingFailed
        case let .imageTooLarge(profile):
            Self.localizedErrorMessage(for: profile.imageTooLargeErrorKey) ?? AppStrings.NewsEditor.imageTooLarge
        }
    }

    private static func localizedErrorMessage(for key: String?) -> String? {
        switch key {
        case "image.validation.aspect_ratio.hero16x9":
            AppStrings.FeaturedEditor.validationImageAspectRatio
        case "image.validation.aspect_ratio.square":
            AppStrings.Images.Validation.squareAspectRatio
        case "image.validation.too_large":
            AppStrings.NewsEditor.imageTooLarge
        default:
            nil
        }
    }
}
