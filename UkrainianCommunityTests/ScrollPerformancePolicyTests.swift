import CoreGraphics
import Testing
@testable import UkrainianCommunity

@Suite("Scroll performance policies")
struct ScrollPerformancePolicyTests {
    @Test
    func thumbnailDecodeUsesNearestPixelBucket() {
        let pixelSize = RemoteImageDecodePolicy.pixelSize(
            forMaximumDisplayDimension: 72,
            displayScale: 3
        )

        #expect(pixelSize == 256)
    }

    @Test
    func fullWidthImageDecodePreservesRetinaDetail() {
        let pixelSize = RemoteImageDecodePolicy.pixelSize(
            forMaximumDisplayDimension: 393,
            displayScale: 3
        )

        #expect(pixelSize == 1_216)
    }

    @Test
    func decodeSizeStaysWithinMemorySafetyBounds() {
        #expect(RemoteImageDecodePolicy.pixelSize(
            forMaximumDisplayDimension: 10,
            displayScale: 2
        ) == RemoteImageDecodePolicy.minimumPixelSize)

        #expect(RemoteImageDecodePolicy.pixelSize(
            forMaximumDisplayDimension: 2_000,
            displayScale: 3
        ) == RemoteImageDecodePolicy.maximumPixelSize)

        #expect(RemoteImageDecodePolicy.pixelSize(
            forMaximumDisplayDimension: .infinity,
            displayScale: 3
        ) == RemoteImageDecodePolicy.maximumPixelSize)
    }
}
