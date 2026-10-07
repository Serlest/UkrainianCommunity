import Foundation

enum DirectoryCatalog {
    static func topic(_ id: String, _ uk: String, _ de: String) -> DirectoryTopic {
        DirectoryTopic(id: id, title: DirectoryText(ukrainian: uk, german: de))
    }

    static func category(
        _ id: String, _ uk: String, _ de: String,
        summaryUK: String, summaryDE: String, symbol: String,
        topics: [DirectoryTopic]
    ) -> DirectoryCategory {
        DirectoryCategory(
            id: id, title: DirectoryText(ukrainian: uk, german: de),
            summary: DirectoryText(ukrainian: summaryUK, german: summaryDE),
            symbol: symbol, topics: topics
        )
    }

    static let categories = startCategories + lifeCategories + supportCategories
}
