import Foundation

struct DirectorySearchMatch: Identifiable {
    let category: DirectoryCategory
    let topic: DirectoryTopic?
    let score: Int
    let order: Int

    var id: String { "\(category.id).\(topic?.id ?? "category")" }
    var route: DirectoryRoute {
        if let topic { .topic(categoryID: category.id, topicID: topic.id) }
        else { .category(category.id) }
    }
}

enum DirectorySearchIndex {
    static func search(_ rawQuery: String, language: AppLanguage) -> [DirectorySearchMatch] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return [] }

        var matches: [DirectorySearchMatch] = []
        var order = 0
        for category in DirectoryCatalog.categories {
            if category.title.value(for: language).compare(query, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
                matches.append(.init(category: category, topic: nil, score: 110, order: order))
                order += 1
                continue
            }

            for topic in category.topics {
                let title = topic.title.value(for: language)
                let startsWithQuery = title.range(of: query, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil
                var score = startsWithQuery ? 100 : (title.localizedStandardContains(query) ? 80 : 0)

                if let guide = DirectoryGuideCatalog.guide(categoryID: category.id, topicID: topic.id) {
                    if guide.sections.contains(where: { $0.title.value(for: language).localizedStandardContains(query) }) { score = max(score, 60) }
                    if guide.introduction.value(for: language).localizedStandardContains(query) { score = max(score, 40) }
                    if guide.sections.contains(where: { $0.body.value(for: language).localizedStandardContains(query) }) { score = max(score, 20) }
                } else if let guide = DirectorySafetyContent.guides[topic.id] {
                    if guide.sections.contains(where: { $0.title.value(for: language).localizedStandardContains(query) }) { score = max(score, 60) }
                    if guide.sections.contains(where: { $0.body.value(for: language).localizedStandardContains(query) }) { score = max(score, 20) }
                }

                if score > 0 { matches.append(.init(category: category, topic: topic, score: score, order: order)) }
                order += 1
            }
        }
        return matches.sorted { $0.score == $1.score ? $0.order < $1.order : $0.score > $1.score }
    }
}
