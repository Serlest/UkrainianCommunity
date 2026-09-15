import CoreImage
import SwiftUI
import Testing
import UIKit
@testable import UkrainianCommunity

@Suite("Adaptive banner image")
@MainActor
struct AdaptiveBannerImageTests {
    @Test
    func preservesTopAndBottomArtworkInWideViewport() throws {
        let sourceImage = makeVerticalTestImage()
        let renderer = ImageRenderer(
            content: AdaptiveBannerImage(image: sourceImage)
                .frame(width: 300, height: 120)
        )
        renderer.scale = 1

        let renderedImage = try #require(renderer.uiImage)
        let topColor = try sampledColor(in: renderedImage, x: 150, yFromTop: 10)
        let bottomColor = try sampledColor(in: renderedImage, x: 150, yFromTop: 110)

        #expect(topColor.red > 0.75)
        #expect(topColor.green < 0.25)
        #expect(topColor.blue < 0.25)
        #expect(bottomColor.red < 0.25)
        #expect(bottomColor.green < 0.25)
        #expect(bottomColor.blue > 0.75)
    }

    private func makeVerticalTestImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 60, height: 180)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 60, height: 60))

            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: 60, width: 60, height: 60))

            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 120, width: 60, height: 60))
        }
    }

    private func sampledColor(
        in image: UIImage,
        x: CGFloat,
        yFromTop: CGFloat
    ) throws -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        let ciImage = try #require(CIImage(image: image))
        let color = try #require(
            CIContext().createCGImage(
                ciImage,
                from: CGRect(x: x, y: image.size.height - yFromTop - 1, width: 1, height: 1)
            )
        )
        let data = try #require(color.dataProvider?.data)
        let bytes = try #require(CFDataGetBytePtr(data))

        return (
            red: CGFloat(bytes[0]) / 255,
            green: CGFloat(bytes[1]) / 255,
            blue: CGFloat(bytes[2]) / 255
        )
    }
}
