import Foundation

/// A published category is one atomic editorial snapshot. The bundled catalog
/// remains the fallback until a category is first edited.
struct DirectoryManagedCategory: Codable, Identifiable, Equatable {
    enum Placement: String, Codable, CaseIterable {
        case start, life, support
    }

    var id: String
    var placement: Placement
    var order: Int
    var isHidden: Bool
    var title: DirectoryText
    var summary: DirectoryText
    var symbol: String
    var groups: [DirectoryManagedGroup]
    var topics: [DirectoryManagedTopic]

    var visibleCategory: DirectoryCategory? {
        guard !isHidden else { return nil }
        return DirectoryCategory(
            id: id, title: title, summary: summary, symbol: symbol,
            topics: topics.filter { !$0.isHidden }.sorted { $0.order < $1.order }
                .map { DirectoryTopic(id: $0.id, title: $0.title) }
        )
    }

    func topic(_ id: String) -> DirectoryManagedTopic? {
        topics.first { $0.id == id && !$0.isHidden }
    }

    static func bundled(_ category: DirectoryCategory) -> Self {
        let placement: Placement = DirectoryCatalog.startCategories.contains { $0.id == category.id }
            ? .start : (DirectoryCatalog.lifeCategories.contains { $0.id == category.id } ? .life : .support)
        let order = (DirectoryCatalog.categories.firstIndex { $0.id == category.id } ?? 0) * 10
        let staticGroups = DirectoryTopicGroups.forCategory(category)
        let groups = staticGroups.isEmpty
            ? [DirectoryManagedGroup(id: "general", title: category.title, order: 0, isHidden: false)]
            : staticGroups.enumerated().map {
                DirectoryManagedGroup(id: $0.element.id, title: $0.element.title,
                                      order: $0.offset, isHidden: false)
            }
        let topics = category.topics.enumerated().map { index, topic in
            let groupID = staticGroups.first { $0.topicIDs.contains(topic.id) }?.id ?? "general"
            return DirectoryManagedTopic.bundled(topic, categoryID: category.id,
                                                 groupID: groupID, order: index)
        }
        return .init(id: category.id, placement: placement, order: order, isHidden: false,
                     title: category.title, summary: category.summary, symbol: category.symbol,
                     groups: groups, topics: topics)
    }
}

struct DirectoryManagedGroup: Codable, Identifiable, Equatable {
    var id: String
    var title: DirectoryText
    var order: Int
    var isHidden: Bool
}

struct DirectoryManagedTopic: Codable, Identifiable, Equatable {
    var id: String
    var groupID: String
    var order: Int
    var isHidden: Bool
    var title: DirectoryText
    var summary: DirectoryText
    var sections: [DirectoryManagedSection]
    var sources: [DirectoryManagedSource]
    var regionalSections: [String: [DirectoryManagedSection]]

    static func bundled(_ topic: DirectoryTopic, categoryID: String,
                        groupID: String, order: Int) -> Self {
        if categoryID == "safety", let guide = DirectorySafetyContent.guides[topic.id] {
            return .init(
                id: topic.id, groupID: groupID, order: order, isHidden: false,
                title: topic.title, summary: guide.summary,
                sections: guide.sections.enumerated().map { index, section in
                    .init(id: section.id, order: index, isHidden: false,
                          title: section.title, body: section.body, symbol: section.symbol,
                          phoneNumber: nil, source: nil,
                          contacts: section.contacts.map(DirectoryManagedContact.init))
                },
                sources: guide.sources.map(DirectoryManagedSource.init),
                regionalSections: bundledRegionalSections(categoryID: categoryID, topicID: topic.id)
            )
        }
        let guide = DirectoryGuideCatalog.guide(categoryID: categoryID, topicID: topic.id)
        return .init(
            id: topic.id, groupID: groupID, order: order, isHidden: false,
            title: topic.title, summary: guide?.introduction ?? .init(ukrainian: "", german: ""),
            sections: (guide?.sections ?? []).enumerated().map { index, section in
                .init(id: section.id, order: index, isHidden: false,
                      title: section.title, body: section.body, symbol: section.symbol,
                      phoneNumber: section.phoneNumber,
                      source: section.source.map(DirectoryManagedSource.init), contacts: [])
            },
            sources: (guide?.sources ?? []).map(DirectoryManagedSource.init),
            regionalSections: bundledRegionalSections(categoryID: categoryID, topicID: topic.id)
        )
    }

    private static func bundledRegionalSections(categoryID: String, topicID: String) -> [String: [DirectoryManagedSection]] {
        guard DirectoryRegionalContent.applies(categoryID: categoryID, topicID: topicID) else { return [:] }
        return Dictionary(uniqueKeysWithValues: AustrianFederalState.allCases.map { state in
            (state.rawValue, DirectoryRegionalContent.sections(categoryID: categoryID, topicID: topicID,
                                                                state: state).enumerated().map { index, section in
                DirectoryManagedSection(
                    id: section.id, order: index, isHidden: false,
                    title: section.title, body: section.body, symbol: section.symbol,
                    phoneNumber: section.phoneNumber,
                    source: section.source.map(DirectoryManagedSource.init), contacts: []
                )
            })
        })
    }
}

struct DirectoryManagedSection: Codable, Identifiable, Equatable {
    var id: String
    var order: Int
    var isHidden: Bool
    var title: DirectoryText
    var body: DirectoryText
    var symbol: String
    var phoneNumber: String?
    var source: DirectoryManagedSource?
    var contacts: [DirectoryManagedContact]
}

struct DirectoryManagedSource: Codable, Identifiable, Equatable {
    var name: String
    var url: String
    var id: String { url }

    init(name: String, url: String) {
        self.name = name
        self.url = url
    }

    init(_ source: DirectorySource) {
        self.init(name: source.name, url: source.url.absoluteString)
    }

    var displaySource: DirectorySource? {
        guard let parsed = URL(string: url), parsed.scheme == "https",
              parsed.host != nil else { return nil }
        return DirectorySource(name: name, url: url)
    }
}

struct DirectoryManagedContact: Codable, Identifiable, Equatable {
    var number: String
    var title: DirectoryText
    var detail: DirectoryText
    var id: String { number }

    init(number: String, title: DirectoryText, detail: DirectoryText) {
        self.number = number
        self.title = title
        self.detail = detail
    }

    init(_ contact: SafetyContact) {
        self.init(number: contact.number, title: contact.title, detail: contact.detail)
    }
}
