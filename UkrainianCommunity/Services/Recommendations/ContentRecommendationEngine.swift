import Foundation

enum ContentRecommendationReason: Hashable {
    case sharedTopic
    case sharedTags
    case nearby
    case nationwide
    case sameRegion
    case samePublisher
    case similarAudience
    case nearbyDate

    var title: String {
        switch self {
        case .sharedTopic:
            AppStrings.Recommendations.sharedTopic
        case .sharedTags:
            AppStrings.Recommendations.sharedTags
        case .nearby:
            AppStrings.Recommendations.nearby
        case .nationwide:
            AppStrings.Recommendations.nationwide
        case .sameRegion:
            AppStrings.Recommendations.sameRegion
        case .samePublisher:
            AppStrings.Recommendations.samePublisher
        case .similarAudience:
            AppStrings.Recommendations.similarAudience
        case .nearbyDate:
            AppStrings.Recommendations.nearbyDate
        }
    }

    var systemImage: String {
        switch self {
        case .sharedTopic: "sparkles"
        case .sharedTags: "tag"
        case .nearby: "location"
        case .nationwide: "map.fill"
        case .sameRegion: "map"
        case .samePublisher: "building.2"
        case .similarAudience: "person.2"
        case .nearbyDate: "calendar.badge.clock"
        }
    }
}

struct NewsContentRecommendation: Identifiable {
    let post: NewsPost
    let score: Int
    let reasons: [ContentRecommendationReason]

    var id: String { post.id }
    var primaryReason: ContentRecommendationReason { reasons[0] }
}

struct EventContentRecommendation: Identifiable {
    let event: Event
    let score: Int
    let reasons: [ContentRecommendationReason]

    var id: String { event.id }
    var primaryReason: ContentRecommendationReason { reasons[0] }
}

/// A deterministic, privacy-preserving related-content ranker.
///
/// The engine follows three explicit stages: eligibility filtering, contextual
/// scoring and diversity re-ranking. It intentionally does not pretend to be
/// behaviorally personalized; all signals come from published content metadata.
struct ContentRecommendationEngine {
    private static let minimumNewsScore = 30
    private static let minimumEventScore = 30
    private static let minute: TimeInterval = 60
    private static let day: TimeInterval = 24 * 60 * minute

    static func newsRecommendations(
        for source: NewsPost,
        candidates: [NewsPost],
        now: Date = Date(),
        limit: Int = 4
    ) -> [NewsContentRecommendation] {
        guard limit > 0 else { return [] }

        let scored = candidates.compactMap { candidate -> NewsContentRecommendation? in
            guard candidate.id != source.id,
                  candidate.moderationStatus == .approved,
                  candidate.publishedAt <= now.addingTimeInterval(5 * minute),
                  !nearDuplicate(candidate, source),
                  let result = newsScore(candidate, comparedTo: source, now: now),
                  result.score >= minimumNewsScore else {
                return nil
            }
            return NewsContentRecommendation(post: candidate, score: result.score, reasons: result.reasons)
        }

        return diversifyNews(scored, limit: limit)
    }

    static func eventRecommendations(
        for source: Event,
        candidates: [Event],
        now: Date = Date(),
        limit: Int = 4
    ) -> [EventContentRecommendation] {
        guard limit > 0 else { return [] }

        let scored = candidates.compactMap { candidate -> EventContentRecommendation? in
            guard candidate.id != source.id,
                  candidate.moderationStatus == .approved,
                  !candidate.isCancelled,
                  candidate.nextOccurrence(relativeTo: now) != nil,
                  !nearDuplicate(candidate, source),
                  let result = eventScore(candidate, comparedTo: source, now: now),
                  result.score >= minimumEventScore else {
                return nil
            }
            return EventContentRecommendation(event: candidate, score: result.score, reasons: result.reasons)
        }

        return diversifyEvents(scored, limit: limit)
    }
}

private extension ContentRecommendationEngine {
    struct ScoreResult {
        let score: Int
        let reasons: [ContentRecommendationReason]
    }

    static func newsScore(_ candidate: NewsPost, comparedTo source: NewsPost, now: Date) -> ScoreResult? {
        var score = 0
        var reasonWeights: [(ContentRecommendationReason, Int)] = []
        var hasSemanticAnchor = false

        let topicScore = newsTopicScore(candidate, source)
        if topicScore > 0 {
            score += topicScore
            reasonWeights.append((.sharedTopic, topicScore))
            hasSemanticAnchor = true
        }

        let sharedTagCount = normalizedTags(candidate.tags).intersection(normalizedTags(source.tags)).count
        if sharedTagCount > 0 {
            let value = min(sharedTagCount, 2) * 18
            score += value
            reasonWeights.append((.sharedTags, value))
            hasSemanticAnchor = true
        }

        let sharedTerms = newsTerms(candidate).intersection(newsTerms(source)).count
        if sharedTerms >= 2 {
            let value = min(sharedTerms, 4) * 5
            score += value
            reasonWeights.append((.sharedTopic, value))
            hasSemanticAnchor = true
        }

        guard hasSemanticAnchor else { return nil }

        let location = locationScore(
            candidateScope: candidate.regionScope,
            candidateState: candidate.federalState,
            candidateCity: candidate.city,
            sourceScope: source.regionScope,
            sourceState: source.federalState,
            sourceCity: source.city
        )
        score += location.score
        if let reason = location.reason, location.score > 0 {
            reasonWeights.append((reason, location.score))
        }

        if samePublisher(candidate.source, source.source) {
            score += 8
            reasonWeights.append((.samePublisher, 8))
        }

        let age = max(0, now.timeIntervalSince(candidate.publishedAt))
        switch age {
        case ..<(7 * day): score += 12
        case ..<(30 * day): score += 9
        case ..<(90 * day): score += 5
        case ..<(180 * day): score += 2
        default: break
        }

        return ScoreResult(score: score, reasons: orderedReasons(reasonWeights))
    }

    static func eventScore(_ candidate: Event, comparedTo source: Event, now: Date) -> ScoreResult? {
        var score = 0
        var reasonWeights: [(ContentRecommendationReason, Int)] = []
        var hasSemanticAnchor = false

        let topicScore = eventTopicScore(candidate, source)
        if topicScore > 0 {
            score += topicScore
            reasonWeights.append((.sharedTopic, topicScore))
            hasSemanticAnchor = true
        }

        let sharedTagCount = normalizedTags(candidate.tags).intersection(normalizedTags(source.tags)).count
        if sharedTagCount > 0 {
            let value = min(sharedTagCount, 2) * 18
            score += value
            reasonWeights.append((.sharedTags, value))
            hasSemanticAnchor = true
        }

        let sharedTerms = eventTerms(candidate).intersection(eventTerms(source)).count
        if sharedTerms >= 2 {
            let value = min(sharedTerms, 4) * 5
            score += value
            reasonWeights.append((.sharedTopic, value))
            hasSemanticAnchor = true
        }

        let location = eventLocationScore(candidate, source)
        score += location.score
        if let reason = location.reason, location.score > 0 {
            reasonWeights.append((reason, location.score))
        }

        let audienceScore = compatibleAudienceScore(candidate, source)
        if audienceScore > 0 {
            score += audienceScore
            reasonWeights.append((.similarAudience, audienceScore))
        }

        // A local event for the same audience is useful even when an organizer
        // selected only broad/legacy categories. Everything else needs a real
        // topic, tag or title connection.
        guard hasSemanticAnchor || (location.score >= 18 && audienceScore > 0) else { return nil }

        if samePublisher(candidate.source, source.source) {
            score += 8
            reasonWeights.append((.samePublisher, 8))
        }

        let sourceDate = source.nextOccurrence(relativeTo: now)?.startDate ?? source.startDate
        let candidateDate = candidate.nextOccurrence(relativeTo: now)?.startDate ?? candidate.startDate
        let dateDistance = abs(candidateDate.timeIntervalSince(sourceDate))
        let dateScore: Int
        switch dateDistance {
        case ..<(7 * day): dateScore = 12
        case ..<(30 * day): dateScore = 8
        case ..<(90 * day): dateScore = 3
        default: dateScore = 0
        }
        if dateScore > 0 {
            score += dateScore
            reasonWeights.append((.nearbyDate, dateScore))
        }

        return ScoreResult(score: score, reasons: orderedReasons(reasonWeights))
    }

    static func newsTopicScore(_ candidate: NewsPost, _ source: NewsPost) -> Int {
        if candidate.category == source.category {
            return [.news, .other].contains(source.category) ? 0 : 42
        }

        if candidate.additionalCategories.contains(source.category)
            || source.additionalCategories.contains(candidate.category) {
            return 30
        }

        let overlap = Set(candidate.additionalCategories).intersection(source.additionalCategories).count
        return min(overlap, 2) * 16
    }

    static func eventTopicScore(_ candidate: Event, _ source: Event) -> Int {
        if candidate.category == source.category {
            return [.unspecified, .other].contains(source.category) ? 0 : 42
        }

        if candidate.additionalCategories.contains(source.category)
            || source.additionalCategories.contains(candidate.category) {
            return 30
        }

        let overlap = Set(candidate.additionalCategories).intersection(source.additionalCategories).count
        return min(overlap, 2) * 16
    }

    static func locationScore(
        candidateScope: RegionScope?,
        candidateState: AustrianFederalState?,
        candidateCity: String?,
        sourceScope: RegionScope?,
        sourceState: AustrianFederalState?,
        sourceCity: String?
    ) -> (score: Int, reason: ContentRecommendationReason?) {
        if normalizedPhrase(candidateCity) != "",
           normalizedPhrase(candidateCity) == normalizedPhrase(sourceCity) {
            return (22, .nearby)
        }
        if let candidateState, candidateState == sourceState {
            return (14, .sameRegion)
        }
        if candidateScope == .austria {
            return (sourceScope == .austria ? 8 : 4, .nationwide)
        }
        return (0, nil)
    }

    static func eventLocationScore(_ candidate: Event, _ source: Event) -> (score: Int, reason: ContentRecommendationReason?) {
        if let distance = distanceInKilometers(candidate, source) {
            switch distance {
            case ...15: return (26, .nearby)
            case ...50: return (18, .nearby)
            case ...120: return (10, .sameRegion)
            default: break
            }
        }

        return locationScore(
            candidateScope: candidate.regionScope,
            candidateState: candidate.federalState,
            candidateCity: candidate.city,
            sourceScope: source.regionScope,
            sourceState: source.federalState,
            sourceCity: source.city
        )
    }

    static func compatibleAudienceScore(_ candidate: Event, _ source: Event) -> Int {
        if candidate.audience == source.audience {
            return candidate.audience == .everyone ? 5 : 12
        }
        if candidate.audience == .everyone || source.audience == .everyone {
            return 5
        }

        guard candidate.minimumAge != nil || candidate.maximumAge != nil,
              source.minimumAge != nil || source.maximumAge != nil else {
            return 0
        }
        let candidateRange = (candidate.minimumAge ?? 0)...(candidate.maximumAge ?? 120)
        let sourceRange = (source.minimumAge ?? 0)...(source.maximumAge ?? 120)
        return candidateRange.overlaps(sourceRange) ? 8 : 0
    }

    static func diversifyNews(_ input: [NewsContentRecommendation], limit: Int) -> [NewsContentRecommendation] {
        var remaining = input
        var selected: [NewsContentRecommendation] = []

        while selected.count < limit, !remaining.isEmpty {
            let ranked = remaining.map { candidate in
                (candidate, candidate.score - newsRedundancyPenalty(candidate.post, selected.map(\.post)))
            }.sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                if lhs.0.score != rhs.0.score { return lhs.0.score > rhs.0.score }
                if lhs.0.post.publishedAt != rhs.0.post.publishedAt { return lhs.0.post.publishedAt > rhs.0.post.publishedAt }
                return lhs.0.id < rhs.0.id
            }

            guard let best = ranked.first else { break }
            selected.append(best.0)
            remaining.removeAll { $0.id == best.0.id || nearDuplicate($0.post, best.0.post) }
        }
        return selected
    }

    static func diversifyEvents(_ input: [EventContentRecommendation], limit: Int) -> [EventContentRecommendation] {
        var remaining = input
        var selected: [EventContentRecommendation] = []

        while selected.count < limit, !remaining.isEmpty {
            let ranked = remaining.map { candidate in
                (candidate, candidate.score - eventRedundancyPenalty(candidate.event, selected.map(\.event)))
            }.sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                if lhs.0.score != rhs.0.score { return lhs.0.score > rhs.0.score }
                let lhsDate = lhs.0.event.nextOccurrence()?.startDate ?? lhs.0.event.startDate
                let rhsDate = rhs.0.event.nextOccurrence()?.startDate ?? rhs.0.event.startDate
                if lhsDate != rhsDate { return lhsDate < rhsDate }
                return lhs.0.id < rhs.0.id
            }

            guard let best = ranked.first else { break }
            selected.append(best.0)
            remaining.removeAll { $0.id == best.0.id || nearDuplicate($0.event, best.0.event) }
        }
        return selected
    }

    static func newsRedundancyPenalty(_ candidate: NewsPost, _ selected: [NewsPost]) -> Int {
        selected.map { item in
            var penalty = 0
            if samePublisher(candidate.source, item.source) { penalty += 14 }
            if candidate.category == item.category { penalty += 7 }
            penalty += min(normalizedTags(candidate.tags).intersection(normalizedTags(item.tags)).count, 3) * 3
            return penalty
        }.max() ?? 0
    }

    static func eventRedundancyPenalty(_ candidate: Event, _ selected: [Event]) -> Int {
        selected.map { item in
            var penalty = 0
            if samePublisher(candidate.source, item.source) { penalty += 16 }
            if candidate.category == item.category { penalty += 8 }
            if normalizedPhrase(candidate.city) == normalizedPhrase(item.city) { penalty += 4 }
            penalty += min(normalizedTags(candidate.tags).intersection(normalizedTags(item.tags)).count, 3) * 3
            return penalty
        }.max() ?? 0
    }

    static func nearDuplicate(_ lhs: NewsPost, _ rhs: NewsPost) -> Bool {
        let leftHeadline = normalizedPhrase(lhs.title)
        if !leftHeadline.isEmpty, leftHeadline == normalizedPhrase(rhs.title) { return true }
        return phraseSimilarity(newsTerms(lhs), newsTerms(rhs)) >= 0.75
    }

    static func nearDuplicate(_ lhs: Event, _ rhs: Event) -> Bool {
        let leftHeadline = normalizedPhrase(lhs.title)
        if !leftHeadline.isEmpty, leftHeadline == normalizedPhrase(rhs.title) { return true }
        return phraseSimilarity(eventTerms(lhs), eventTerms(rhs)) >= 0.88
            && abs(lhs.startDate.timeIntervalSince(rhs.startDate)) < 2 * day
    }

    static func phraseSimilarity(_ lhs: Set<String>, _ rhs: Set<String>) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        let union = lhs.union(rhs).count
        guard union > 0 else { return 0 }
        return Double(lhs.intersection(rhs).count) / Double(union)
    }

    static func newsTerms(_ post: NewsPost) -> Set<String> {
        // Summaries often contain generic community boilerplate. Restrict the
        // fallback text signal to headlines so it cannot manufacture relevance.
        let localizedTitles = post.localizations.values.map(\.title)
        return normalizedTerms(([post.title] + localizedTitles).joined(separator: " "))
    }

    static func eventTerms(_ event: Event) -> Set<String> {
        let localizedTitles = event.localizations.values.map(\.title)
        return normalizedTerms(([event.title] + localizedTitles).joined(separator: " "))
    }

    static func normalizedTerms(_ text: String) -> Set<String> {
        let components = normalizedPhrase(text)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 && !stopWords.contains($0) }
        return Set(components)
    }

    static func normalizedTags(_ tags: [String]) -> Set<String> {
        Set(tags.map { normalizedPhrase($0) }.filter { !$0.isEmpty })
    }

    static func normalizedPhrase(_ value: String?) -> String {
        value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "uk_UA"))
            .lowercased() ?? ""
    }

    static func samePublisher(_ lhs: ContentSourceMetadata, _ rhs: ContentSourceMetadata) -> Bool {
        guard let lhsID = lhs.displayOrganizationId, let rhsID = rhs.displayOrganizationId else { return false }
        return lhsID == rhsID
    }

    static func orderedReasons(_ weighted: [(ContentRecommendationReason, Int)]) -> [ContentRecommendationReason] {
        var seen = Set<ContentRecommendationReason>()
        let reasons = weighted.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return reasonPriority(lhs.0) < reasonPriority(rhs.0)
        }.compactMap { reason, _ in
            seen.insert(reason).inserted ? reason : nil
        }
        return reasons.isEmpty ? [.sharedTopic] : reasons
    }

    static func reasonPriority(_ reason: ContentRecommendationReason) -> Int {
        switch reason {
        case .sharedTopic: 0
        case .sharedTags: 1
        case .nearby: 2
        case .nationwide: 3
        case .sameRegion: 4
        case .similarAudience: 5
        case .nearbyDate: 6
        case .samePublisher: 7
        }
    }

    static func distanceInKilometers(_ lhs: Event, _ rhs: Event) -> Double? {
        guard let lhsLatitude = lhs.latitude,
              let lhsLongitude = lhs.longitude,
              let rhsLatitude = rhs.latitude,
              let rhsLongitude = rhs.longitude,
              (-90...90).contains(lhsLatitude),
              (-180...180).contains(lhsLongitude),
              (-90...90).contains(rhsLatitude),
              (-180...180).contains(rhsLongitude) else {
            return nil
        }

        let earthRadius = 6_371.0
        let latitudeDelta = degreesToRadians(rhsLatitude - lhsLatitude)
        let longitudeDelta = degreesToRadians(rhsLongitude - lhsLongitude)
        let lhsLatitudeRadians = degreesToRadians(lhsLatitude)
        let rhsLatitudeRadians = degreesToRadians(rhsLatitude)
        let haversine = sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
            + cos(lhsLatitudeRadians) * cos(rhsLatitudeRadians)
            * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        return earthRadius * 2 * atan2(sqrt(haversine), sqrt(max(0, 1 - haversine)))
    }

    static func degreesToRadians(_ value: Double) -> Double {
        value * .pi / 180
    }

    static let stopWords: Set<String> = [
        // Ukrainian
        "адже", "але", "буде", "бути", "вас", "вам", "для", "його", "коли", "може", "нова", "новини",
        "після", "понад", "про", "року", "свою", "також", "того", "україни", "українців", "цей", "цієї", "щодо",
        // German (diacritics are folded by normalizedPhrase)
        "aber", "auch", "dass", "eine", "einer", "eines", "einem", "einen", "fur", "haben", "mehr", "nach",
        "nicht", "oder", "sich", "uber", "unter", "vom", "werden", "wird", "zwischen",
        // English and generic content words
        "about", "after", "also", "event", "events", "from", "into", "news", "that", "their", "this", "with"
    ]
}
