import Foundation

enum DirectoryManagedValidation {
    enum Failure: LocalizedError {
        case invalidContent
        case invalidSource
        case tooLarge
        case conflict
        case permissionDenied

        var errorDescription: String? {
            let ukrainian = AppLanguage.stored == .ukrainian
            switch self {
            case .invalidContent:
                return ukrainian ? "Заповніть назви обома мовами, розділи та статті."
                    : "Füllen Sie Namen, Bereiche und Beiträge in beiden Sprachen aus."
            case .invalidSource:
                return ukrainian ? "Кожен видимий матеріал потребує HTTPS-джерела. Перевірте адресу та актуальність інформації."
                    : "Jeder sichtbare Inhalt benötigt eine HTTPS-Quelle. Prüfen Sie Adresse und Aktualität."
            case .tooLarge:
                return ukrainian ? "Категорія завелика для збереження. Розділіть матеріал."
                    : "Der Bereich ist zu groß. Teilen Sie den Inhalt auf."
            case .conflict:
                return ukrainian ? "Категорію змінили на іншому пристрої. Вийдіть і відкрийте її знову перед редагуванням."
                    : "Der Bereich wurde auf einem anderen Gerät geändert. Öffnen Sie ihn vor dem Bearbeiten erneut."
            case .permissionDenied:
                return ukrainian ? "Доступ до редагування змінився. Перевірте свій обліковий запис."
                    : "Ihr Bearbeitungszugriff hat sich geändert. Prüfen Sie Ihr Konto."
            }
        }
    }

    static func validate(_ category: DirectoryManagedCategory) throws -> Data {
        guard validID(category.id), validText(category.title, max: 100),
              validText(category.summary, max: 500),
              !category.symbol.isEmpty, category.symbol.utf16.count <= 80,
              category.groups.count <= 30, category.topics.count <= 100,
              unique(category.groups.map(\.id)), unique(category.topics.map(\.id)),
              category.groups.allSatisfy({ validID($0.id) && validText($0.title, max: 100) })
        else { throw Failure.invalidContent }

        let groupIDs = Set(category.groups.map(\.id))
        let visibleGroupIDs = Set(category.groups.filter { !$0.isHidden }.map(\.id))
        for topic in category.topics {
            guard validID(topic.id), groupIDs.contains(topic.groupID),
                  validText(topic.title, max: 140), topic.summary.ukrainian.utf16.count <= 800,
                  topic.summary.german.utf16.count <= 800,
                  topic.sections.count <= 80, topic.sources.count <= 80,
                  topic.regionalSections.count <= 9,
                  unique(topic.sections.map(\.id)),
                  unique(topic.sources.map(\.url)),
                  topic.sources.allSatisfy({ validSource($0) })
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
            if !topic.isHidden && visibleGroupIDs.contains(topic.groupID) &&
                (topic.sections.allSatisfy(\.isHidden) ||
                                   topic.summary.ukrainian.isEmpty || topic.summary.german.isEmpty) {
                throw Failure.invalidContent
            }
        }
        if !category.isHidden && category.topics.isEmpty {
            throw Failure.invalidContent
        }
        let data = try JSONEncoder().encode(category)
        guard data.count <= 800_000 else { throw Failure.tooLarge }
        return data
    }

    private static func validateSection(_ section: DirectoryManagedSection,
                                        inheritedSources: [DirectoryManagedSource]) throws {
        guard validID(section.id), validText(section.title, max: 160),
              section.body.ukrainian.utf16.count <= 6000,
              section.body.german.utf16.count <= 6000,
              !section.symbol.isEmpty, section.symbol.utf16.count <= 80,
              section.phoneNumber.map({ $0.utf16.count <= 40 }) ?? true,
              section.contacts.count <= 12,
              section.contacts.allSatisfy({
                  !$0.number.isEmpty && $0.number.utf16.count <= 40 &&
                  $0.number.range(of: "^[0-9 +()/-]+$", options: .regularExpression) != nil &&
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
            return !trimmed.isEmpty && $0.utf16.count <= max
        }
    }

    private static func validSource(_ source: DirectoryManagedSource) -> Bool {
        guard !source.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              source.name.utf16.count <= 160, source.url.utf16.count <= 1024,
              let url = URL(string: source.url),
              url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil else { return false }
        return true
    }

    private static func unique(_ ids: [String]) -> Bool {
        Set(ids).count == ids.count
    }
}
