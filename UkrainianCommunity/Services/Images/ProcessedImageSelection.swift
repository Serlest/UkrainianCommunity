import CoreGraphics
import Foundation

struct ImageSourceDimensions: Sendable {
    let pixelWidth: CGFloat
    let pixelHeight: CGFloat
    let displayedWidth: CGFloat
    let displayedHeight: CGFloat
    let orientation: Int?

    nonisolated var displayedAspectRatio: CGFloat {
        displayedWidth / displayedHeight
    }
}

struct ProcessedImageSelection: Sendable {
    let data: Data
    let outputFormat: ImageOutputFormat
    let contentType: String
    let dimensions: ImageSourceDimensions
    let renderedWidth: CGFloat
    let renderedHeight: CGFloat
    let compressionQuality: CGFloat

    nonisolated var byteCount: Int {
        data.count
    }
}
