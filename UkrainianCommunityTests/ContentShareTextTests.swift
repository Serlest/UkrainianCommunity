import XCTest
import UIKit
import LinkPresentation
@testable import UkrainianCommunity

final class ContentShareTextTests: XCTestCase {
    @MainActor func testActivityItemAlwaysProvidesTextWithTitleMetadata() {
        let text = ContentShareText.compose(title: "Title", introduction: "", body: "Full body",
                                           sources: ["https://example.org"], language: .ukrainian)
        let item = ContentTextShareSheet.Item(text: text, title: "Title")
        let controller = UIActivityViewController(activityItems: [item], applicationActivities: nil)
        XCTAssertEqual(item.activityViewControllerPlaceholderItem(controller) as? String, text)
        for receiver in [UIActivity.ActivityType.copyToPasteboard, .mail, .message] {
            XCTAssertEqual(item.activityViewController(controller, itemForActivityType: receiver) as? String, text)
            XCTAssertEqual(item.activityViewController(controller, subjectForActivityType: receiver), "Title")
        }
        XCTAssertEqual(item.activityViewControllerLinkMetadata(controller)?.title, "Title")
    }
    func testNewsKeepsEntireArticleSourceAndQuietFooterInOneItem() {
        let body = String(repeating: "Важлива інформація. ", count: 100)
        let text = ContentShareText.compose(title: "Новина", introduction: "Коротко", body: body,
                                            sources: ["https://example.org/article"], language: .ukrainian)
        XCTAssertTrue(text.hasPrefix("Новина\n\nКоротко\n\n"))
        XCTAssertTrue(text.contains(body.trimmingCharacters(in: .whitespacesAndNewlines)))
        XCTAssertTrue(text.contains("Джерело: https://example.org/article"))
        XCTAssertTrue(text.hasSuffix("Більше інформації — у застосунку UAC: \(ContentShareText.appURL)"))
        XCTAssertFalse(text.contains("…"))
    }

    func testRepeatedSummaryAndSourcesAreNotDuplicated() {
        let text = ContentShareText.compose(title: " Title ", introduction: " Summary ",
                                            body: "Summary\n\nDetails", facts: ["", " Venue ", "Venue"],
                                            sources: [nil, " https://example.org ", "https://example.org"], language: .german)
        XCTAssertEqual(text.components(separatedBy: "Summary").count, 2)
        XCTAssertEqual(text.components(separatedBy: "Venue").count, 2)
        XCTAssertEqual(text.components(separatedBy: "Quelle:").count, 2)
        XCTAssertTrue(text.contains("Weitere Informationen in der UAC-App:"))
        XCTAssertFalse(text.contains("Джерело"))
    }

    func testUnsafeAndMalformedSourcesNeverEnterPayload() {
        for value in ["javascript:alert(1)", "file:///private/test", "https:///", "https://user:password@example.org", " "] {
            XCTAssertNil(ContentShareText.safeWebURL(value))
        }
        XCTAssertNotNil(ContentShareText.safeWebURL("http://example.org"))
        let text = ContentShareText.compose(title: "Title", introduction: "", body: "",
                                            sources: ["javascript:bad"], language: .ukrainian)
        XCTAssertFalse(text.contains("javascript"))
        XCTAssertFalse(text.contains("Джерело:"))
    }

    func testEventFactsKeepScheduleAddressParticipationAndCancellation() {
        let facts = ["Захід скасовано", "Причина", "5 листопада, 18:00–20:00\n6 листопада, 17:00–19:00",
                     "Venue, Street 1, Wien", "Безкоштовно", "Реєстрація в застосунку"]
        let text = ContentShareText.compose(title: "Захід", introduction: "Summary", body: "Full details",
                                            facts: facts, sources: ["https://example.org/tickets"], language: .ukrainian)
        for fact in facts { XCTAssertTrue(text.contains(fact)) }
        XCTAssertTrue(text.contains("Full details"))
        XCTAssertLessThan(text.range(of: "Захід скасовано")!.lowerBound, text.range(of: "Summary")!.lowerBound)
    }

    func testPricesUseActualCurrencyAndDoNotInventUnspecifiedPrice() {
        XCTAssertEqual(ContentShareText.price(EventPricing(), language: .german), "")
        XCTAssertEqual(ContentShareText.price(EventPricing(kind: .free), language: .ukrainian), "Безкоштовно")
        let usd = ContentShareText.price(EventPricing(kind: .startingFrom, amount: 12.5, currencyCode: "USD"), language: .german)
        XCTAssertTrue(usd.hasPrefix("Preis ab ")); XCTAssertTrue(usd.contains("12,50"))
        XCTAssertFalse(usd.contains("€"))
        let range = ContentShareText.price(EventPricing(kind: .range, amount: 10, maximumAmount: 20), language: .ukrainian)
        XCTAssertTrue(range.contains("10")); XCTAssertTrue(range.contains("20")); XCTAssertTrue(range.contains("–"))
    }
}
