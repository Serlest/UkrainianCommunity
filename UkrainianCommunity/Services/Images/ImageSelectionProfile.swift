import CoreGraphics
import Foundation

enum ImageOutputFormat: String, Sendable {
    case jpeg

    nonisolated var contentType: String {
        switch self {
        case .jpeg:
            "image/jpeg"
        }
    }
}

struct ImageSelectionProfile: Identifiable, Sendable {
    let id: String
    let name: String
    let targetAspectRatio: CGFloat?
    let allowedAspectRatioRange: ClosedRange<CGFloat>?
    let maxBytes: Int
    let maxPixelDimension: CGFloat
    let jpegQuality: CGFloat
    let outputFormat: ImageOutputFormat
    let rendersOpaqueJPEG: Bool
    let cropCornerRadius: CGFloat
    let aspectRatioErrorKey: String?
    let imageTooLargeErrorKey: String?

    init(
        id: String,
        name: String,
        targetAspectRatio: CGFloat?,
        allowedAspectRatioRange: ClosedRange<CGFloat>?,
        maxBytes: Int,
        maxPixelDimension: CGFloat,
        jpegQuality: CGFloat,
        outputFormat: ImageOutputFormat = .jpeg,
        rendersOpaqueJPEG: Bool = true,
        cropCornerRadius: CGFloat = AppTheme.imageRadius,
        aspectRatioErrorKey: String? = nil,
        imageTooLargeErrorKey: String? = nil
    ) {
        self.id = id
        self.name = name
        self.targetAspectRatio = targetAspectRatio
        self.allowedAspectRatioRange = allowedAspectRatioRange
        self.maxBytes = maxBytes
        self.maxPixelDimension = maxPixelDimension
        self.jpegQuality = jpegQuality
        self.outputFormat = outputFormat
        self.rendersOpaqueJPEG = rendersOpaqueJPEG
        self.cropCornerRadius = cropCornerRadius
        self.aspectRatioErrorKey = aspectRatioErrorKey
        self.imageTooLargeErrorKey = imageTooLargeErrorKey
    }
}

extension ImageSelectionProfile {
    static let hero16x9 = ImageSelectionProfile(
        id: "hero16x9",
        name: "Hero 16:9",
        targetAspectRatio: 16.0 / 9.0,
        allowedAspectRatioRange: 1.65...1.90,
        maxBytes: 3_000_000,
        maxPixelDimension: 1600,
        jpegQuality: 0.82,
        cropCornerRadius: AppTheme.heroRadius,
        aspectRatioErrorKey: "image.validation.aspect_ratio.hero16x9",
        imageTooLargeErrorKey: "image.validation.too_large"
    )

    static let squareAvatar = ImageSelectionProfile(
        id: "squareAvatar",
        name: "Square avatar",
        targetAspectRatio: 1,
        allowedAspectRatioRange: 0.90...1.10,
        maxBytes: 1_500_000,
        maxPixelDimension: 1024,
        jpegQuality: 0.82,
        cropCornerRadius: 999,
        aspectRatioErrorKey: "image.validation.aspect_ratio.square",
        imageTooLargeErrorKey: "image.validation.too_large"
    )

    static let squareLogo = ImageSelectionProfile(
        id: "squareLogo",
        name: "Square logo",
        targetAspectRatio: 1,
        allowedAspectRatioRange: 0.90...1.10,
        maxBytes: 1_500_000,
        maxPixelDimension: 1024,
        jpegQuality: 0.82,
        cropCornerRadius: AppTheme.cardRadius,
        aspectRatioErrorKey: "image.validation.aspect_ratio.square",
        imageTooLargeErrorKey: "image.validation.too_large"
    )

    static let galleryPhoto = ImageSelectionProfile(
        id: "galleryPhoto",
        name: "Gallery photo",
        targetAspectRatio: nil,
        allowedAspectRatioRange: nil,
        maxBytes: 3_000_000,
        maxPixelDimension: 1600,
        jpegQuality: 0.82,
        imageTooLargeErrorKey: "image.validation.too_large"
    )
}
