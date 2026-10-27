import CoreImage
import SwiftUI
import Testing
import UIKit
@testable import UkrainianCommunity

@Suite("Featured banner artwork sizing")
@MainActor
struct FeaturedBannerArtworkLayoutTests {
    @Test func managementStackPreservesEditorTabBarPolicy() {
        // Nested editors request hidden tabs; their owning stack must agree.
        #expect(ProfileNavigationRoute.featuredBannerManagement.hidesRootTabBar)
        #expect(!ProfileNavigationRoute.savedContent.hidesRootTabBar)
    }

    @Test func offscreenAccessibilityHeightsCannotCreateBlankSpaceAfterRotation() {
        let old = FeaturedBannerHeightMeasurement(width: 408, height: 826, typeSize: .accessibility5, compact: false)
        let current = FeaturedBannerHeightMeasurement(width: 800, height: 310, typeSize: .large, compact: true)
        let removed = FeaturedBannerHeightMeasurement(width: 800, height: 900, typeSize: .large, compact: true)
        let measurements = ["offscreen": old, "visible": current, "removed": removed]
        let ids: Set<String> = ["offscreen", "visible"]
        #expect(FeaturedBannerHeightMeasurement.resolvedHeight(measurements, bannerIDs: ids,
            width: 800, typeSize: .large, compact: true) == 310)
        #expect(FeaturedBannerHeightMeasurement.resolvedHeight(measurements, bannerIDs: ids,
            width: 408, typeSize: .accessibility5, compact: false) == 826)
        #expect(FeaturedBannerHeightMeasurement.resolvedHeight(measurements, bannerIDs: ids,
            width: 408, typeSize: .large, compact: false) == 280)
        #expect(!current.matches(width: 800, typeSize: .large, compact: false))
        #expect(!current.matches(width: 700, typeSize: .large, compact: true))
    }

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

    @Test func titleAndSubtitleHaveIndependentColorsWithoutTextPanel() throws {
        let white = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 90)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 160, height: 90))
        }
        let style = FeaturedBannerTextAppearance(titleColorHex: "#0000FF", subtitleColorHex: "#FFFF00")
        let banner = FeaturedBanner(id: "text-colors", title: "A", subtitle: "B", imageURL: "https://example.com/banner.jpg", visibleSections: [.home], createdAt: .now, updatedAt: .now, createdBy: "fixture", textAppearance: style)
        let renderer = ImageRenderer(content: FeaturedBannerCardView(banner: banner, previewImage: white)
            .frame(width: width).environment(\.dynamicTypeSize, .large).environment(\.colorScheme, .light))
        renderer.scale = 1
        let image = try #require(renderer.uiImage)
        let sample = try color(image, x: 180, yFromTop: image.size.height - 35)
        #expect(sample.red > 0.82 && sample.blue > 0.82)
        let source = try #require(CIImage(image: image))
        let bounds = source.extent.integral
        let rowBytes = Int(bounds.width) * 4
        var pixels = [UInt8](repeating: 0, count: rowBytes * Int(bounds.height))
        pixels.withUnsafeMutableBytes { buffer in
            CIContext().render(source, toBitmap: buffer.baseAddress!, rowBytes: rowBytes,
                               bounds: bounds, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        }
        var blue = 0, yellow = 0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            if pixels[index] < 80 && pixels[index + 1] < 80 && pixels[index + 2] > 200 { blue += 1 }
            if pixels[index] > 200 && pixels[index + 1] > 200 && pixels[index + 2] < 80 { yellow += 1 }
        }
        #expect(blue > 5 && yellow > 5)
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
