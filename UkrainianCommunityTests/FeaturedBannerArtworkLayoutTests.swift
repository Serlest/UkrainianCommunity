import CoreImage
import SwiftUI
import Testing
import UIKit
@testable import UkrainianCommunity

@Suite("Featured banner artwork sizing")
@MainActor
struct FeaturedBannerArtworkLayoutTests {
    private let width: CGFloat = 358

    @Test func countdownRetainsOriginalFullWidthImageAndUncroppedEdges() throws {
        let plain = try render(countdown: nil, typeSize: .large)
        let timer = FeaturedBannerCountdown(targetDate: Date().addingTimeInterval(3600), label: "До події", germanLabel: "", completion: .showStarted)
        let timed = try render(countdown: timer, typeSize: .large)
        let expectedHeight = width / FeaturedBannerLayoutPolicy.artworkAspectRatio
        #expect(abs(plain.size.height - expectedHeight) < 1)
        #expect(abs(timed.size.height - plain.size.height) < 1)
        let top = try color(timed, x: 60, yFromTop: 5)
        let bottom = try color(timed, x: 60, yFromTop: timed.size.height - 5)
        #expect(top.red > 0.7 && top.blue < 0.3)
        #expect(bottom.blue > 0.7 && bottom.red < 0.3)
    }

    @Test func largestTextRetainsFullArtworkHeightInsteadOf120Points() throws {
        let image = try render(countdown: nil, typeSize: .accessibility5)
        let expectedHeight = width / FeaturedBannerLayoutPolicy.artworkAspectRatio
        #expect(abs(image.size.height - expectedHeight) < 1)
    }

    @Test func countdownHasNoDarkPanelBehindItsNumbers() throws {
        let white = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 90)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 160, height: 90))
        }
        let timer = FeaturedBannerCountdown(targetDate: Date().addingTimeInterval(3600), label: "До події", germanLabel: "", completion: .showStarted)
        let image = try render(countdown: timer, typeSize: .large, artwork: white)
        // Inside the former panel, away from glyphs: only the original light
        // artwork should remain, rather than a translucent black rectangle.
        let sample = try color(image, x: 180, yFromTop: 30)
        #expect(sample.red > 0.85 && sample.blue > 0.85)
    }

    private func render(countdown: FeaturedBannerCountdown?, typeSize: DynamicTypeSize, artwork: UIImage? = nil) throws -> UIImage {
        let defaultImage = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 90)).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 160, height: 30))
            UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 30, width: 160, height: 30))
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 60, width: 160, height: 30))
        }
        let image = artwork ?? defaultImage
        let banner = FeaturedBanner(id: "sizing", title: "", imageURL: "https://example.com/banner.jpg", visibleSections: [.home], createdAt: .now, updatedAt: .now, createdBy: "fixture", countdown: countdown)
        let view = FeaturedBannerCardView(banner: banner, previewImage: image)
            .frame(width: width).environment(\.dynamicTypeSize, typeSize).environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return try #require(renderer.uiImage)
    }

    private func color(_ image: UIImage, x: CGFloat, yFromTop: CGFloat) throws -> (red: CGFloat, blue: CGFloat) {
        let source = try #require(CIImage(image: image))
        let pixel = try #require(CIContext().createCGImage(source, from: CGRect(x: x, y: image.size.height - yFromTop - 1, width: 1, height: 1)))
        let data = try #require(pixel.dataProvider?.data)
        let bytes = try #require(CFDataGetBytePtr(data))
        return (CGFloat(bytes[0]) / 255, CGFloat(bytes[2]) / 255)
    }
}
