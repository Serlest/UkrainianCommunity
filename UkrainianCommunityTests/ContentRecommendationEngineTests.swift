import Foundation
import Testing
@testable import UkrainianCommunity

@MainActor
struct ContentRecommendationEngineTests {
    private let now = Date(timeIntervalSince1970: 1_788_188_400)

    @Test func newsRecommendationsDoNotUseUnrelatedFreshContentAsFiller() {
        let source = news(id: "source", title: "Нові правила тимчасового захисту", category: .lawAndDocuments, tags: ["захист"])
        let related = news(
            id: "related",
            title: "Тимчасовий захист: важливе оновлення",
            category: .benefitsAndSupport,
            additionalCategories: [.lawAndDocuments],
            tags: ["ЗАХИСТ"],
            publishedAt: now.addingTimeInterval(-86_400)
        )
        let unrelated = news(
            id: "unrelated",
            title: "Відкриття нової мистецької виставки",
            category: .culture,
            tags: ["мистецтво"],
            publishedAt: now
        )

        let result = ContentRecommendationEngine.newsRecommendations(
            for: source,
            candidates: [unrelated, related],
            now: now
        )

        #expect(result.map(\.id) == ["related"])
        #expect(result.first?.reasons.contains(.sharedTopic) == true)
    }

    @Test func newsRecommendationsExcludeFutureModerationAndDuplicateHeadlines() {
        let source = news(id: "source", title: "Допомога з житлом у Тіролі", category: .housing)
        let future = news(id: "future", title: "Майбутня допомога з орендою", category: .housing, publishedAt: now.addingTimeInterval(3_600))
        let draft = news(id: "draft", title: "Нова житлова програма", category: .housing, moderationStatus: .draft)
        let duplicate = news(id: "duplicate", title: source.title, category: .housing, publisherID: "another")
        let nearDuplicate = news(
            id: "near-duplicate",
            title: "Допомога з житлом у Тіролі сьогодні",
            category: .housing,
            publisherID: "third"
        )

        let result = ContentRecommendationEngine.newsRecommendations(
            for: source,
            candidates: [future, draft, duplicate, nearDuplicate],
            now: now
        )

        #expect(result.isEmpty)
    }

    @Test func genericNewsCategoryAloneDoesNotManufactureARecommendation() {
        let source = news(id: "source", title: "Оновлення роботи сервісу", category: .news)
        let unrelated = news(id: "unrelated", title: "Відкрилася нова спортивна зала", category: .news)

        let result = ContentRecommendationEngine.newsRecommendations(
            for: source,
            candidates: [unrelated],
            now: now
        )

        #expect(result.isEmpty)
    }

    @Test func newsReRankingAvoidsNearDuplicateStoriesAndPublisherMonotony() {
        let source = news(id: "source", title: "Робота для українців у Тіролі", category: .work, tags: ["робота"])
        let first = news(
            id: "first",
            title: "Нові вакансії для українців в Інсбруку",
            category: .work,
            tags: ["робота", "вакансії"],
            publisherID: "publisher-a"
        )
        let duplicate = news(
            id: "duplicate",
            title: "Нові вакансії для українців в Інсбруку сьогодні",
            category: .work,
            tags: ["робота", "вакансії"],
            publisherID: "publisher-a"
        )
        let differentPublisher = news(
            id: "different",
            title: "Безкоштовна консультація щодо працевлаштування",
            category: .work,
            tags: ["робота"],
            publisherID: "publisher-b"
        )

        let result = ContentRecommendationEngine.newsRecommendations(
            for: source,
            candidates: [first, duplicate, differentPublisher],
            now: now,
            limit: 3
        )

        #expect(result.contains { $0.id == "different" })
        #expect(!(result.contains { $0.id == "first" } && result.contains { $0.id == "duplicate" }))
    }

    @Test func eventRecommendationsUseTopicLocationAudienceAndRealDistance() {
        let source = event(
            id: "source",
            title: "Український музичний вечір",
            category: .culture,
            additionalCategories: [.music],
            audience: .adults,
            latitude: 47.2692,
            longitude: 11.4041
        )
        let nearbyMusic = event(
            id: "nearby-music",
            title: "Жива музика в Інсбруку",
            category: .music,
            audience: .adults,
            latitude: 47.27,
            longitude: 11.41
        )
        let distantMusic = event(
            id: "distant-music",
            title: "Концерт української музики у Відні",
            category: .music,
            city: "Wien",
            state: .wien,
            audience: .adults,
            latitude: 48.2082,
            longitude: 16.3738
        )

        let result = ContentRecommendationEngine.eventRecommendations(
            for: source,
            candidates: [distantMusic, nearbyMusic],
            now: now
        )

        #expect(result.map(\.id).first == "nearby-music")
        #expect(result.first?.reasons.contains(.nearby) == true)
        #expect(result.first?.reasons.contains(.sharedTopic) == true)
    }

    @Test func eventRecommendationsExcludeCancelledPastAndUnrelatedEvents() {
        let source = event(id: "source", title: "Сімейний день", category: .childrenAndFamily, audience: .families)
        let cancelled = event(
            id: "cancelled",
            title: "Сімейний фестиваль",
            category: .childrenAndFamily,
            audience: .families,
            cancellationState: "cancelled"
        )
        let past = event(
            id: "past",
            title: "Дитяче свято",
            category: .childrenAndFamily,
            audience: .families,
            startDate: now.addingTimeInterval(-7_200)
        )
        let unrelated = event(id: "unrelated", title: "Бізнес зустріч", category: .businessAndNetworking, city: "Wien", state: .wien, audience: .adults)

        let result = ContentRecommendationEngine.eventRecommendations(
            for: source,
            candidates: [cancelled, past, unrelated],
            now: now
        )

        #expect(result.isEmpty)
    }

    private func news(
        id: String,
        title: String,
        category: NewsCategory,
        additionalCategories: [NewsCategory] = [],
        tags: [String] = [],
        publishedAt: Date? = nil,
        moderationStatus: ModerationStatus = .approved,
        publisherID: String = "publisher-source"
    ) -> NewsPost {
        NewsPost(
            id: id,
            title: title,
            subtitle: "Корисна інформація для української громади",
            regionScope: .federalState,
            federalState: .tirol,
            city: "Innsbruck",
            category: category,
            additionalCategories: additionalCategories,
            tags: tags,
            source: ContentSourceMetadata(sourceType: .organization, organizationId: publisherID),
            body: "Повний текст",
            authorName: "Author",
            publishedAt: publishedAt ?? now.addingTimeInterval(-3_600),
            createdAt: now.addingTimeInterval(-3_600),
            updatedAt: now.addingTimeInterval(-3_600),
            comments: [],
            moderationStatus: moderationStatus,
            likeCount: 0,
            likeState: .notLiked
        )
    }

    private func event(
        id: String,
        title: String,
        category: EventCategory,
        additionalCategories: [EventCategory] = [],
        city: String = "Innsbruck",
        state: AustrianFederalState = .tirol,
        audience: EventAudience = .everyone,
        latitude: Double? = nil,
        longitude: Double? = nil,
        startDate: Date? = nil,
        cancellationState: String? = nil
    ) -> Event {
        let start = startDate ?? now.addingTimeInterval(7 * 86_400)
        return Event(
            id: id,
            title: title,
            summary: "Подія для української громади",
            details: "Детальний опис події",
            regionScope: .city,
            federalState: state,
            source: ContentSourceMetadata(sourceType: .organization, organizationId: "event-publisher-\(id)"),
            city: city,
            venue: "Venue",
            latitude: latitude,
            longitude: longitude,
            startDate: start,
            endDate: start.addingTimeInterval(3_600),
            createdAt: now,
            updatedAt: now,
            capacity: 100,
            registeredCount: 0,
            comments: [],
            moderationStatus: .approved,
            registrationState: .notRegistered,
            likeCount: 0,
            likeState: .notLiked,
            category: category,
            additionalCategories: additionalCategories,
            audience: audience,
            cancellationState: cancellationState
        )
    }
}
