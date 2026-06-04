import Foundation

struct GuideSmartCollectionSet {
    let importantNow: [GuideArticle]
    let newcomers: [GuideArticle]
    let emergency: [GuideArticle]
    let popular: [GuideArticle]
    let recentlyUpdated: [GuideArticle]
}

@MainActor
extension LegacyGuideListViewModel {
    var newcomers: [GuideArticle] {
        newcomerCandidates
            .limitedForGuideCollections()
    }

    var popular: [GuideArticle] {
        popularCandidates
            .limitedForGuideCollections()
    }

    var importantNow: [GuideArticle] {
        importantNowCandidates
            .limitedForGuideCollections()
    }

    var recentlyUpdated: [GuideArticle] {
        recentlyUpdatedCandidates
            .limitedForGuideCollections()
    }

    var emergency: [GuideArticle] {
        emergencyCandidates
            .limitedForGuideCollections()
    }

    var smartCollections: GuideSmartCollectionSet {
        var displayedIDs = Set<String>()

        let importantNowArticles = importantNowCandidates.uniqueForGuideCollections(excluding: &displayedIDs)
        let newcomerArticles = newcomerCandidates.uniqueForGuideCollections(excluding: &displayedIDs)
        let emergencyArticles = emergencyCandidates.uniqueForGuideCollections(excluding: &displayedIDs)
        let popularArticles = popularCandidates.uniqueForGuideCollections(excluding: &displayedIDs)
        let recentArticles = recentlyUpdatedCandidates.uniqueForGuideCollections(excluding: &displayedIDs)

        return GuideSmartCollectionSet(
            importantNow: importantNowArticles,
            newcomers: newcomerArticles,
            emergency: emergencyArticles,
            popular: popularArticles,
            recentlyUpdated: recentArticles
        )
    }

    private var newcomerCandidates: [GuideArticle] {
        filteredArticles
            .filter { article in
                article.category == .firstSteps
                || article.category == .anmeldung
                || article.audienceContains("new arrivals")
            }
            .sortedForGuideCollections()
    }

    private var popularCandidates: [GuideArticle] {
        filteredArticles
            .filter { $0.isFeatured == true }
            .sortedForGuideCollections()
    }

    private var importantNowCandidates: [GuideArticle] {
        filteredArticles
            .filter { article in
                article.isPinned
                || article.reviewState == .dueSoon
                || article.reviewState == .overdue
                || article.status == .needsReview
            }
            .sortedForGuideCollections()
    }

    private var recentlyUpdatedCandidates: [GuideArticle] {
        filteredArticles
            .sorted { lhs, rhs in
                lhs.updatedAt > rhs.updatedAt
            }
    }

    private var emergencyCandidates: [GuideArticle] {
        filteredArticles
            .filter { article in
                article.category == .emergency || article.contentType == .contact
            }
            .sortedForGuideCollections()
    }
}

private extension GuideArticle {
    func audienceContains(_ value: String) -> Bool {
        audience?.contains { audienceValue in
            audienceValue.localizedCaseInsensitiveCompare(value) == .orderedSame
        } == true
    }
}

private extension Array where Element == GuideArticle {
    func sortedForGuideCollections() -> [GuideArticle] {
        sorted { lhs, rhs in
            let lhsPriority = lhs.priority ?? Int.max
            let rhsPriority = rhs.priority ?? Int.max

            if lhsPriority != rhsPriority {
                return lhsPriority < rhsPriority
            }

            return lhs.updatedAt > rhs.updatedAt
        }
    }

    func limitedForGuideCollections(limit: Int = 5) -> [GuideArticle] {
        Array(prefix(limit))
    }

    func uniqueForGuideCollections(excluding displayedIDs: inout Set<String>, limit: Int = 5) -> [GuideArticle] {
        var result: [GuideArticle] = []

        for article in self {
            guard !displayedIDs.contains(article.id) else { continue }

            displayedIDs.insert(article.id)
            result.append(article)

            if result.count == limit {
                break
            }
        }

        return result
    }
}
