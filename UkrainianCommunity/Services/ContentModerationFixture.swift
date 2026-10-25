#if DEBUG && targetEnvironment(simulator)
import Foundation

@MainActor
final class ContentModerationFixture {
    static let shared = ContentModerationFixture()
    private var records: [ContentReviewItem] = (0..<37).map { index in
        ContentReviewItem(id: "moderation-news-\(index)", contentType: "news", revision: "1792670000:123456000", status: .pendingReview,
            title: "Community publication \(index)", translations: [
                "uk": .init(title: "Новина громади \(index)", summary: "Матеріал для перевірки перед публікацією на всю Австрію.", body: "Повний текст матеріалу. Перевірте обидві мови, джерело та зміст перед публікацією."),
                "de": .init(title: "Nachricht der Gemeinschaft \(index)", summary: "Inhalt zur Prüfung vor der österreichweiten Veröffentlichung.", body: "Vollständiger Inhalt. Prüfen Sie beide Sprachen, Quelle und Inhalt vor der Veröffentlichung.")],
            organizationId: "org-1", organizationName: "Community Centre", authorName: "Test Author", createdAt: 1792670000000 - Double(index * 1000),
            imageURL: "", sourceName: "Official source", sourceURL: "https://example.org", region: "tirol", venue: "", city: "Innsbruck", address: "", startDate: nil, endDate: nil, reason: "", canReview: true)
    }
    init() {
        if ProcessInfo.processInfo.environment["UITestModerationRich"] == "1" { records.append(Self.richEvent()) }
        if ProcessInfo.processInfo.environment["UITestModerationEmpty"] == "1" { records = [] }
    }
    private var failedOnce = false
    private var previewFailedOnce = false
    static func richEvent() -> ContentReviewItem {
        let payload: [String: Any] = [
            "regionScope": "austria", "category": "culture", "additionalCategories": ["education"], "tags": ["family", "music"],
            "locationNote": "Second floor · Eingang im Hof", "organizerName": "Community organizer", "organizerURL": "https://example.org/organizer",
            "contactPhone": "+431234567", "contactEmail": "fixture@example.org", "contactURL": "https://example.org/contact", "latitude": 47.26, "longitude": 11.4,
            "participationMode": "externalTickets", "requiresRegistration": true, "isAllDay": false,
            "price": 12, "pricing": ["kind": "range", "amount": 12, "maximumAmount": 20, "currencyCode": "EUR", "note": "Child discount"],
            "capacity": 60, "audience": "families", "minimumAge": 6, "maximumAge": 99,
            "externalAction": ["title": "Tickets", "url": "https://example.org/tickets"],
            "mediaMetadata": ["caption": "Community stage", "alternativeText": "Accessible description", "credit": "Fixture author"],
            "occurrences": [["id": "session-1", "startDate": 1792670000000, "endDate": 1792673600000, "isAllDay": false, "status": "scheduled"],
                            ["id": "session-2", "startDate": 1792756400000, "endDate": 1792760000000, "isAllDay": false, "status": "cancelled"]]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let publication = try? JSONDecoder().decode(ContentReviewPublication.self, from: data) else { preconditionFailure("Invalid fixed moderation event fixture") }
        return .init(id: "moderation-event-0", contentType: "event", revision: "1792670000:123456000", status: .pendingReview,
            title: "Community event", translations: [
                "uk": .init(title: "Подія громади з кількома датами та зовнішніми квитками", summary: "Перевірте всі умови участі.", body: "Повний опис події для перевірки."),
                "de": .init(title: "Gemeinschaftsveranstaltung mit mehreren Terminen und externen Tickets", summary: "Prüfe alle Teilnahmebedingungen.", body: "Vollständige Beschreibung zur Prüfung.")],
            organizationId: "org-1", organizationName: "Community Centre", authorName: "Test Author", createdAt: 1792670000000,
            imageURL: "https://127.0.0.1:1/moderation-missing.jpg", sourceName: "", sourceURL: "", region: "tirol", venue: "Community hall", city: "", address: "Fixture Straße 1",
            startDate: 1792670000000, endDate: 1792673600000, reason: "", canReview: true, publication: publication)
    }
    private var history: [ContentReviewHistoryEntry] = []
    private var receipts: Set<String> = []
    var client: ContentModerationClient {
        .init(read: { [self] query in
            if query.action == "list", ProcessInfo.processInfo.environment["UITestModerationFailure"] == "1", !failedOnce {
                failedOnce = true; throw AppError.network
            }
            if query.action == "preview", ProcessInfo.processInfo.environment["UITestModerationMissingMaterial"] == "1" { throw AppError.notFound }
            if query.action == "preview", ProcessInfo.processInfo.environment["UITestModerationPreviewFailure"] == "1", !previewFailedOnce {
                previewFailedOnce = true; throw AppError.network
            }
            if ProcessInfo.processInfo.environment["UITestModerationSlow"] == "1" { try await Task.sleep(for: .seconds(3)) }
            switch query.action {
            case "preview":
                guard let item = records.first(where: { $0.id == query.contentId }) else { throw AppError.notFound }
                return .init(item: item)
            case "history": return .init(history: history)
            default:
                let filtered = records.filter { $0.contentType == query.contentType && $0.status == .pendingReview }
                let offset = query.cursor.flatMap { cursor in filtered.firstIndex { $0.id == cursor.id }.map { $0 + 1 } } ?? 0
                let page = Array(filtered.dropFirst(offset).prefix(30))
                return .init(items: page, counts: query.includeCounts == false ? nil : ["news": records.filter { $0.contentType == "news" && $0.status == .pendingReview }.count, "event": records.filter { $0.contentType == "event" && $0.status == .pendingReview }.count],
                    cursor: offset + page.count < filtered.count ? page.last.map { .init(seconds: 1792670000, nanoseconds: 123456000, id: $0.id) } : nil)
            }
        }, decide: { [self] item, status, reason, operation, _ in
            if receipts.contains(operation) { return }
            guard let index = records.firstIndex(where: { $0.id == item.id && $0.revision == item.revision && $0.status == .pendingReview }) else { throw AppError.validationFailed }
            receipts.insert(operation)
            records[index] = .init(id: item.id, contentType: item.contentType, revision: item.revision, status: status,
                title: item.title, translations: item.translations, organizationId: item.organizationId, organizationName: item.organizationName,
                authorName: item.authorName, createdAt: item.createdAt, imageURL: item.imageURL, sourceName: item.sourceName, sourceURL: item.sourceURL,
                region: item.region, venue: item.venue, city: item.city, address: item.address, startDate: item.startDate, endDate: item.endDate,
                reason: reason, canReview: false, canEdit: item.canEdit, publication: item.publication)
            history.insert(.init(id: operation, contentId: item.id, contentType: item.contentType, title: item.title,
                status: status, reason: reason, reviewerName: "Test Owner", organizationName: item.organizationName,
                createdAt: Date.now.timeIntervalSince1970 * 1000), at: 0)
        })
    }
}
#endif
