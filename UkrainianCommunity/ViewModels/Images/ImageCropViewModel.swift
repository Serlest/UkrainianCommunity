import Combine
import CoreGraphics
import Foundation
import UIKit

@MainActor
final class ImageCropViewModel: ObservableObject {
    @Published var scale: CGFloat = 1
    @Published var offset: CGSize = .zero
    @Published private(set) var cropFrameSize: CGSize = CGSize(width: 1600, height: 900)
    @Published var isProcessing = false
    @Published var errorMessage: String?

    let sourceImage: UIImage
    let profile: ImageSelectionProfile

    private let normalizedImage: UIImage
    private var dragStartOffset: CGSize?
    private var scaleStartValue: CGFloat?

    init(sourceImage: UIImage, profile: ImageSelectionProfile) {
        self.sourceImage = sourceImage
        self.profile = profile
        self.normalizedImage = sourceImage.normalizedForCropping()
    }

    var targetAspectRatio: CGFloat {
        profile.targetAspectRatio ?? 1
    }

    var previewImage: UIImage {
        normalizedImage
    }

    func setCropFrameSize(_ frameSize: CGSize) {
        guard frameSize.width > 0, frameSize.height > 0 else { return }
        cropFrameSize = frameSize
        clampOffset(in: frameSize)
    }

    func reset() {
        scale = 1
        offset = .zero
        dragStartOffset = nil
        scaleStartValue = nil
        errorMessage = nil
    }

    func imageDisplaySize(in frameSize: CGSize) -> CGSize {
        let baseScale = baseImageScale(in: frameSize)
        let totalScale = baseScale * scale
        return CGSize(
            width: normalizedImage.size.width * totalScale,
            height: normalizedImage.size.height * totalScale
        )
    }

    func updateDrag(translation: CGSize, in frameSize: CGSize) {
        if dragStartOffset == nil {
            dragStartOffset = offset
        }
        let start = dragStartOffset ?? .zero
        offset = CGSize(width: start.width + translation.width, height: start.height + translation.height)
        clampOffset(in: frameSize)
    }

    func endDrag(in frameSize: CGSize) {
        dragStartOffset = nil
        clampOffset(in: frameSize)
    }

    func updateMagnification(_ value: CGFloat, in frameSize: CGSize) {
        if scaleStartValue == nil {
            scaleStartValue = scale
        }
        let start = scaleStartValue ?? 1
        scale = min(max(start * value, 1), 5)
        clampOffset(in: frameSize)
    }

    func endMagnification(in frameSize: CGSize) {
        scaleStartValue = nil
        clampOffset(in: frameSize)
    }

    func applyCrop() async throws -> ProcessedImageSelection {
        isProcessing = true
        errorMessage = nil
        defer { isProcessing = false }

        guard let croppedImage = croppedCGImage(frameSize: cropFrameSize) else {
            throw ImageProcessingError.invalidImageData
        }
        return try await ImageProcessingService.process(cgImage: croppedImage, profile: profile)
    }

    private func baseImageScale(in frameSize: CGSize) -> CGFloat {
        guard normalizedImage.size.width > 0, normalizedImage.size.height > 0 else { return 1 }
        return max(
            frameSize.width / normalizedImage.size.width,
            frameSize.height / normalizedImage.size.height
        )
    }

    private func clampOffset(in frameSize: CGSize) {
        let displaySize = imageDisplaySize(in: frameSize)
        let maxX = max(0, (displaySize.width - frameSize.width) / 2)
        let maxY = max(0, (displaySize.height - frameSize.height) / 2)
        offset = CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }

    private func croppedCGImage(frameSize: CGSize) -> CGImage? {
        guard let cgImage = normalizedImage.cgImage else { return nil }

        let imageSize = normalizedImage.size
        let displaySize = imageDisplaySize(in: frameSize)
        let imageLeft = (frameSize.width - displaySize.width) / 2 + offset.width
        let imageTop = (frameSize.height - displaySize.height) / 2 + offset.height
        let pointsPerPixelX = imageSize.width / CGFloat(cgImage.width)
        let pointsPerPixelY = imageSize.height / CGFloat(cgImage.height)
        let cropInImagePoints = CGRect(
            x: (0 - imageLeft) / (displaySize.width / imageSize.width),
            y: (0 - imageTop) / (displaySize.height / imageSize.height),
            width: frameSize.width / (displaySize.width / imageSize.width),
            height: frameSize.height / (displaySize.height / imageSize.height)
        )
        let cropInPixels = CGRect(
            x: cropInImagePoints.origin.x / pointsPerPixelX,
            y: cropInImagePoints.origin.y / pointsPerPixelY,
            width: cropInImagePoints.width / pointsPerPixelX,
            height: cropInImagePoints.height / pointsPerPixelY
        ).integral
        let imageBounds = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        let clampedCrop = cropInPixels.intersection(imageBounds)

        guard clampedCrop.width > 0, clampedCrop.height > 0 else { return nil }
        return cgImage.cropping(to: clampedCrop)
    }
}

private extension UIImage {
    func normalizedForCropping() -> UIImage {
        guard imageOrientation != .up else { return self }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
