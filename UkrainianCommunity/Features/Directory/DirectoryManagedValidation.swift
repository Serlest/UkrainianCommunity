import Foundation

enum DirectoryManagedValidation {
    enum Failure: LocalizedError {
        case invalidContent
        case invalidSource
        case tooLarge
        case conflict

        var errorDescription: String? {
            switch self {
            case .invalidContent: "Заповніть назви обома мовами, розділи та статті."
            case .invalidSource: "Кожен видимий матеріал потребує офіційного HTTPS-джерела."
            case .tooLarge: "Категорія завелика для збереження. Розділіть матеріал."
            case .conflict: "Категорію змінили на іншому пристрої. Оновіть її та повторіть правки."
            }
        }
    }

    static func validate(_ category: DirectoryManagedCategory) throws -> Data {
        guard validID(category.id), validText(category.title, max: 100),
              validText(category.summary, max: 500),
              !category.symbol.isEmpty, category.symbol.count <= 80,
              category.groups.count <= 30, category.topics.count <= 100,
              unique(category.groups.map(\.id)), unique(category.topics.map(\.id)),
              category.groups.allSatisfy({ validID($0.id) && validText($0.title, max: 100) })
        else { throw Failure.invalidContent }

        let groupIDs = Set(category.groups.map(\.id))
        let visibleGroupIDs = Set(category.groups.filter { !$0.isHidden }.map(\.id))
        for topic in category.topics {
            guard validID(topic.id), groupIDs.contains(topic.groupID),
                  validText(topic.title, max: 140), topic.summary.ukrainian.count <= 800,
                  topic.summary.german.count <= 800,
                  topic.sections.count <= 80, topic.sources.count <= 80,
                  topic.regionalSections.count <= 9,
                  unique(topic.sections.map(\.id)),
                  topic.sources.allSatisfy(validSource)
            else { throw Failure.invalidContent }
            for (state, sections) in topic.regionalSections {
                guard AustrianFederalState(rawValue: state) != nil,
                      sections.count <= 40, unique(sections.map(\.id))
                else { throw Failure.invalidContent }
                for section in sections {
                    try validateSection(section, inheritedSources: [])
                }
            }
            for section in topic.sections {
                try validateSection(section, inheritedSources: topic.sources)
            }
            if !topic.isHidden && (!visibleGroupIDs.contains(topic.groupID) ||
                                   topic.sections.allSatisfy(\.isHidden) ||
                                   topic.summary.ukrainian.isEmpty || topic.summary.german.isEmpty) {
                throw Failure.invalidContent
            }
        }
        if !category.isHidden && category.topics.allSatisfy(\.isHidden) {
            throw Failure.invalidContent
        }
        let data = try JSONEncoder().encode(category)
        guard data.count <= 800_000 else { throw Failure.tooLarge }
        return data
    }

    private static func validateSection(_ section: DirectoryManagedSection,
                                        inheritedSources: [DirectoryManagedSource]) throws {
        guard validID(section.id), validText(section.title, max: 160),
              section.body.ukrainian.count <= 6000,
              section.body.german.count <= 6000,
              !section.symbol.isEmpty, section.symbol.count <= 80,
              section.contacts.count <= 12,
              section.contacts.allSatisfy({
                  !$0.number.isEmpty && $0.number.count <= 40 &&
                  validText($0.title, max: 100) &&
                  validText($0.detail, max: 200)
              })
        else { throw Failure.invalidContent }
        if let source = section.source, !validSource(source) { throw Failure.invalidSource }
        if !section.isHidden &&
            (section.body.ukrainian.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
             section.body.german.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
             (section.source == nil && inheritedSources.isEmpty)) {
            throw Failure.invalidSource
        }
    }

    private static func validID(_ value: String) -> Bool {
        value.range(of: "^[a-z0-9][a-z0-9-]{0,63}$", options: .regularExpression) != nil
    }

    private static func validText(_ text: DirectoryText, max: Int) -> Bool {
        let values = [text.ukrainian, text.german]
        return values.allSatisfy {
            let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && trimmed.count <= max
        }
    }

    private static func validSource(_ source: DirectoryManagedSource) -> Bool {
        guard !source.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              source.name.count <= 160, source.url.count <= 1024,
              let url = URL(string: source.url),
              url.scheme == "https", url.host != nil else { return false }
        return true
    }

    private static func unique(_ ids: [String]) -> Bool {
        Set(ids).count == ids.count
    }
}
