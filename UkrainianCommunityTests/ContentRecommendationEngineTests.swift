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

    @Test func broadHealthCategoryAndGenericTagsDoNotConnectDifferentSubjects() {
        let source = news(id: "insurance", title: "Медичне страхування для родини", category: .health, tags: ["здоров’я", "Австрія"])
        let unrelated = news(id: "vaccine", title: "Нові правила вакцинації восени", category: .health, tags: ["здоров’я", "Австрія"])
        let related = news(id: "ecard", title: "Як отримати e-card у страховій касі", category: .lawAndDocuments)

        let result = ContentRecommendationEngine.newsRecommendations(for: source, candidates: [unrelated, related], now: now)
        #expect(result.map(\.id) == [related.id])
    }

    @Test func translatedGenericWordsDoNotManufactureSemanticOverlap() {
        let source = news(
            id: "generic-source", title: "Нові можливості в Австрії", category: .communityAndIntegration,
            localizations: ["de": NewsLocalizedContent(title: "Neue Möglichkeiten in Österreich", subtitle: "", body: "")]
        )
        let unrelated = news(
            id: "generic-other", title: "Нові зустрічі в Австрії", category: .communityAndIntegration,
            localizations: ["de": NewsLocalizedContent(title: "Neue Treffen in Österreich", subtitle: "", body: "")]
        )
        #expect(ContentRecommendationEngine.newsRecommendations(for: source, candidates: [unrelated], now: now).isEmpty)
    }

    @Test func specificSubjectMatchesAcrossLanguagesAndAdditionalCategories() {
        let source = news(id: "source-uk", title: "Як оформити медичне страхування", category: .health)
        let related = news(
            id: "candidate-de", title: "Krankenversicherung: Anmeldung bei der ÖGK",
            category: .lawAndDocuments, additionalCategories: [.health]
        )
        let result = ContentRecommendationEngine.newsRecommendations(for: source, candidates: [related], now: now)
        #expect(result.map(\.id) == [related.id])
        #expect(result.first?.primaryReason == .sharedTopic)
    }

    @Test func specificSubjectCanComeFromDescriptionWithoutUsingGenericBoilerplate() {
        let source = news(id: "description-source", title: "Важливі зміни з листопада", category: .health,
                          subtitle: "Нові умови медичного страхування для родин")
        let related = news(id: "description-related", title: "Anmeldung bei der Krankenkasse", category: .health)
        let unrelated = news(id: "description-other", title: "Мистецька виставка", category: .culture)
        #expect(ContentRecommendationEngine.newsRecommendations(for: source, candidates: [unrelated, related], now: now).map(\.id) == [related.id])
    }

    @Test func samePlaceAudienceAndDateNeverReplaceEventSubject() {
        let source = event(id: "yoga-source", title: "Ранкова йога в парку", category: .sportsAndWellness, audience: .adults)
        let unrelated = event(id: "football-other", title: "Футбольний турнір", category: .sportsAndWellness, audience: .adults)
        let related = event(id: "yoga-related", title: "Yoga am Abend", category: .training, audience: .adults)
        let result = ContentRecommendationEngine.eventRecommendations(for: source, candidates: [unrelated, related], now: now)
        #expect(result.map(\.id) == [related.id])
    }

    @Test func sameBroadCategoryWithoutConcreteConnectionProducesNoRecommendations() {
        let source = news(id: "broad-source", title: "Підтримка людей старшого віку", category: .benefitsAndSupport)
        let unrelated = news(id: "broad-other", title: "Допомога підприємцям-початківцям", category: .benefitsAndSupport)
        #expect(ContentRecommendationEngine.newsRecommendations(for: source, candidates: [unrelated], now: now).isEmpty)
    }

    @Test func olderRelevantCandidateSurvivesMoreThanTwelveUnrelatedItems() {
        let source = news(id: "wide-source", title: "Медичне страхування", category: .health)
        let unrelated = (0..<25).map { news(id: "unrelated-\($0)", title: "Вакцинація: оновлення номер \($0)", category: .health) }
        let related = news(id: "older-related", title: "Krankenversicherung für Familien", category: .health,
                           publishedAt: now.addingTimeInterval(-20 * 86_400))
        #expect(ContentRecommendationEngine.newsRecommendations(for: source, candidates: unrelated + [related], now: now).map(\.id) == [related.id])
    }

    @Test func regionTagsAndPublisherCannotConnectUnrelatedNews() {
        let source = news(id: "region-source", title: "Оновлення міських послуг", category: .news, tags: ["Niederösterreich"])
        let unrelated = news(id: "region-other", title: "Відкриття мистецької галереї", category: .news, tags: ["Niederösterreich"])
        #expect(ContentRecommendationEngine.newsRecommendations(for: source, candidates: [unrelated], now: now).isEmpty)
    }

    @Test func austriaInGermanIsNotAnEasterSubject() {
        let source = news(id: "austria-source", title: "Neue Angebote in Österreich", category: .news)
        let unrelated = news(id: "austria-other", title: "Osterfest für Familien", category: .culture)
        #expect(ContentRecommendationEngine.newsRecommendations(for: source, candidates: [unrelated], now: now).isEmpty)
    }

    private func news(
        id: String,
        title: String,
        category: NewsCategory,
        additionalCategories: [NewsCategory] = [],
        tags: [String] = [],
        publishedAt: Date? = nil,
        moderationStatus: ModerationStatus = .approved,
        publisherID: String = "publisher-source",
        subtitle: String = "Корисна інформація для української громади",
        localizations: [String: NewsLocalizedContent] = [:]
    ) -> NewsPost {
        NewsPost(
            id: id,
            localizations: localizations,
            title: title,
            subtitle: subtitle,
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
