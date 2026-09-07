import SwiftUI
import UIKit
import XCTest
@testable import UkrainianCommunity

@MainActor
final class ContentFeedCardRenderingTests: XCTestCase {
    func testCompleteCardsWithLongCategoryAndLargestText() throws {
        let originalLanguage = LocalizationStore.language
        defer { LocalizationStore.language = originalLanguage }
        for code in ["uk", "de"] {
        LocalizationStore.language = try XCTUnwrap(AppLanguage(rawValue: code))
        var news = HomeFeedItem(post: try XCTUnwrap(MockContentBuilder.newsPosts().first))
        news.newsCategory = .financeTaxesAndConsumerRights
        let items = [news,
                     HomeFeedItem(event: try XCTUnwrap(MockContentBuilder.events().first)),
                     HomeFeedItem(organization: try XCTUnwrap(MockContentBuilder.organizations().first))]
        for size in [DynamicTypeSize.large, .accessibility5] {
            for item in items {
                let renderer = ImageRenderer(content:
                    ContentFeedCard(item: item)
                        .frame(width: 340)
                        .padding(16)
                        .background(Color.gray.opacity(0.2))
                        .environment(\.dynamicTypeSize, size)
                        .environment(\.colorScheme, .dark)
                )
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.uiImage)
                XCTAssertEqual(image.size.width, 372, accuracy: 1)
                XCTAssertGreaterThan(image.size.height, 100)
                let attachment = XCTAttachment(image: image)
                attachment.name = "complete-card-\(code)-\(item.itemType.rawValue)-\(size == .large ? "standard" : "AX")"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
        }
    }
}
