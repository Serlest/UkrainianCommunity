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
    private var history: [ContentReviewHistoryEntry] = []
    private var receipts: Set<String> = []
    var client: ContentModerationClient {
        .init(read: { [self] query in
            switch query.action {
            case "preview":
                guard let item = records.first(where: { $0.id == query.contentId }) else { throw AppError.notFound }
                return .init(item: item)
            case "history": return .init(history: history)
            default:
                let filtered = records.filter { $0.contentType == query.contentType }
                let offset = query.cursor.flatMap { cursor in filtered.firstIndex { $0.id == cursor.id }.map { $0 + 1 } } ?? 0
                let page = Array(filtered.dropFirst(offset).prefix(30))
                return .init(items: page, counts: ["news": records.count, "event": 0],
                    cursor: offset + page.count < filtered.count ? page.last.map { .init(seconds: 1792670000, nanoseconds: 123456000, id: $0.id) } : nil)
            }
        }, decide: { [self] item, status, reason, operation, _ in
            if receipts.contains(operation) { return }
            guard records.contains(where: { $0.id == item.id && $0.revision == item.revision }) else { throw AppError.validationFailed }
            receipts.insert(operation)
            records.removeAll { $0.id == item.id }
            history.insert(.init(id: operation, contentId: item.id, contentType: item.contentType, title: item.title,
                status: status, reason: reason, reviewerName: "Test Owner", organizationName: item.organizationName,
                createdAt: Date.now.timeIntervalSince1970 * 1000), at: 0)
        })
    }
}
#endif
