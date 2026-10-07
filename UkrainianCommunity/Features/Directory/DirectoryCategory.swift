import Foundation

struct DirectoryText: Hashable {
    let ukrainian: String
    let german: String

    func value(for language: AppLanguage) -> String {
        language == .ukrainian ? ukrainian : german
    }
}

struct DirectoryTopic: Identifiable, Hashable {
    let id: String
    let title: DirectoryText

    func matches(_ query: String, language: AppLanguage) -> Bool {
        title.value(for: language).localizedStandardContains(query)
    }
}

struct DirectoryCategory: Identifiable, Hashable {
    let id: String
    let title: DirectoryText
    let summary: DirectoryText
    let symbol: String
    let topics: [DirectoryTopic]

    func matches(_ query: String, language: AppLanguage) -> Bool {
        title.value(for: language).localizedStandardContains(query)
            || summary.value(for: language).localizedStandardContains(query)
            || topics.contains { $0.matches(query, language: language) }
    }
}
