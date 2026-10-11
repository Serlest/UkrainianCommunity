import Foundation

enum DirectoryEditorDrafts {
    static func category(placement: DirectoryManagedCategory.Placement,
                         order: Int) -> DirectoryManagedCategory {
        .init(
            id: "custom-" + UUID().uuidString.lowercased(),
            placement: placement, order: order, isHidden: false,
            title: .init(ukrainian: "", german: ""),
            summary: .init(ukrainian: "", german: ""),
            symbol: "books.vertical.fill",
            groups: [.init(id: "general",
                           title: .init(ukrainian: "Основне", german: "Allgemein"),
                           order: 0, isHidden: false)],
            topics: [topic(groupID: "general", order: 0)]
        )
    }

    static func firstMissingLanguage(in texts: [DirectoryText]) -> AppLanguage? {
        for language in [AppLanguage.ukrainian, .german] {
            if texts.contains(where: {
                $0.value(for: language).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }) {
                return language
            }
        }
        return nil
    }

    static func topic(groupID: String, order: Int) -> DirectoryManagedTopic {
        .init(
            id: "topic-" + UUID().uuidString.lowercased(),
            groupID: groupID, order: order, isHidden: false,
            title: .init(ukrainian: "", german: ""),
            summary: .init(ukrainian: "", german: ""),
            sections: [section(order: 0)],
            sources: [.init(name: "", url: "")], regionalSections: [:]
        )
    }

    static func section(order: Int) -> DirectoryManagedSection {
        .init(
            id: "section-" + UUID().uuidString.lowercased(),
            order: order, isHidden: false,
            title: .init(ukrainian: "", german: ""),
            body: .init(ukrainian: "", german: ""),
            symbol: "text.book.closed.fill", phoneNumber: nil,
            source: nil, contacts: []
        )
    }
}
