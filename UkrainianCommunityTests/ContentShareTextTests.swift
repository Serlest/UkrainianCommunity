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
    func testNewsSharesEditorialSummaryInsteadOfEntireArticle() {
        let body = String(repeating: "Важлива інформація. ", count: 100)
        let text = ContentShareText.compose(title: "Новина", introduction: "Коротко", body: body,
                                            sources: ["https://example.org/article"], language: .ukrainian)
        XCTAssertTrue(text.hasPrefix("Новина\n\nКоротко\n\n"))
        XCTAssertFalse(text.contains(body.trimmingCharacters(in: .whitespacesAndNewlines)))
        XCTAssertLessThan(text.count, 250)
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
        XCTAssertFalse(text.contains("Full details"))
        XCTAssertTrue(text.contains("Summary"))
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

    func testTextOnlySharingOmitsImageDisclosureWithoutRemovingNewsAboutAI() {
        let disclosure = "Зображення — тематична ШІ-ілюстрація, а не фото фактичного тоннелю чи події."
        XCTAssertEqual(ContentShareText.textWithoutImageDisclosure("Новина.\n\n\(disclosure)\n\nДжерело."), "Новина.\n\nДжерело.")
        XCTAssertEqual(ContentShareText.textWithoutImageDisclosure("Das Bild ist eine thematische KI-Illustration, kein Foto des Ereignisses."), "")
        let article = "ШІ-ілюстрація стала темою дискусії. Експерти пояснили ризики."
        XCTAssertEqual(ContentShareText.textWithoutImageDisclosure(article), article)
        let mixed = disclosure + " Важливе уточнення про рух."
        XCTAssertEqual(ContentShareText.textWithoutImageDisclosure(mixed), mixed, "Do not delete factual text that shares the line")
        let text = ContentShareText.compose(title: "Bosruck", introduction: "", body: "Тоннель закрито.\n\n" + disclosure,
                                           sources: ["https://routenplaner.asfinag.at/hamm/gate"], language: .ukrainian)
        XCTAssertTrue(text.contains("Тоннель закрито.")); XCTAssertFalse(text.contains("ілюстрація"))
    }

    func testSummaryFallbackIsShortAndDoesNotInventFacts() {
        XCTAssertEqual(ContentShareText.shortSummary(introduction: "", body: "Перше речення. Друге речення. Третє речення."), "Перше речення. Друге речення.")
        XCTAssertEqual(ContentShareText.shortSummary(introduction: "Коротко.", body: "Дуже довгий опис."), "Коротко.")
        let long = ContentShareText.shortSummary(introduction: String(repeating: "Довге слово ", count: 80), body: "")
        XCTAssertLessThanOrEqual(long.count, 320); XCTAssertTrue(long.hasSuffix("…"))
    }

    private var vienna: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Vienna")!
        return calendar
    }

    func testRoncalliUsesOnePeriodInsteadOfThirtySixDates() {
        let days = [(10,17),(10,18),(10,21),(10,22),(10,23),(10,24),(10,25),(10,26),(10,28),(10,29),(10,30),(10,31),(11,1),(11,4),(11,5),(11,6),(11,7),(11,8)]
        let occurrences = days.flatMap { month, day in [15, 19].map { hour in
            let start = vienna.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
            return EventOccurrence(startDate: start, endDate: start.addingTimeInterval(3600))
        } }
        for language in [AppLanguage.ukrainian, .german] {
            let text = ContentShareText.eventSchedule(occurrences: occurrences, detailedSchedule: Array(repeating: "UNWANTED SESSION", count: 36), language: language, hasOrganizerLink: true, calendar: vienna)
            XCTAssertFalse(text.contains("UNWANTED SESSION"))
            XCTAssertTrue(text.contains("17")); XCTAssertTrue(text.contains("8")); XCTAssertTrue(text.contains("2026"))
            XCTAssertEqual(text.components(separatedBy: "\n").count, 2)
            XCTAssertTrue(text.contains(language == .ukrainian ? "окремих сеансів" : "Einzelne Termine"))
        }
    }

    func testFewSeparateDatesKeepExactTimesAndIdenticalRowsAreDeduplicated() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let occurrences = [EventOccurrence(startDate: start, endDate: start.addingTimeInterval(3600))]
        XCTAssertEqual(ContentShareText.eventSchedule(occurrences: occurrences, detailedSchedule: ["5 листопада, 15:00", "5 листопада, 15:00"], language: .ukrainian, hasOrganizerLink: false), "5 листопада, 15:00")
    }

    func testPeriodKeepsBothYearsAndAllDayExclusiveEnd() {
        let first = vienna.date(from: DateComponents(year: 2026, month: 12, day: 30))!
        let occurrences = (0..<4).map { index in
            let start = vienna.date(byAdding: .day, value: index, to: first)!
            return EventOccurrence(startDate: start, endDate: vienna.date(byAdding: .day, value: 1, to: start)!, isAllDay: true)
        }
        let text = ContentShareText.eventSchedule(occurrences: occurrences, detailedSchedule: [], language: .ukrainian, hasOrganizerLink: false, calendar: vienna)
        XCTAssertTrue(text.contains("2026")); XCTAssertTrue(text.contains("2027")); XCTAssertTrue(text.contains("2 січня")); XCTAssertFalse(text.contains("3 січня"))
        XCTAssertTrue(text.contains("застосунку UAC"))
    }

    func testLocationDoesNotRepeatCityAlreadyInStreetAddress() {
        XCTAssertEqual(ContentShareText.location(venue: "Olympiaworld", address: "Olympiastraße 10, 6020 Innsbruck", city: "Innsbruck"), "Olympiaworld, Olympiastraße 10, 6020 Innsbruck")
        XCTAssertEqual(ContentShareText.location(venue: "Hall", address: "Street 1", city: "Wien"), "Hall, Street 1, Wien")
    }
}
