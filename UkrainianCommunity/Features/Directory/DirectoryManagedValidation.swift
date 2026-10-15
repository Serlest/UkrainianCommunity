import Foundation

enum DirectoryManagedValidation {
    enum Failure: LocalizedError {
        case invalidContent
        case invalidSource
        case tooLarge
        case conflict
        case permissionDenied
        case field(String, AppLanguage?)

        var language: AppLanguage? {
            if case let .field(_, language) = self { return language }
            return nil
        }

        var errorDescription: String? {
            let ukrainian = AppLanguage.stored == .ukrainian
            switch self {
            case let .field(message, _): return message
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
        let category = DirectorySourceValidation.normalizingSources(in: category)
        try validateText(category.title, field: .categoryTitle)
        try validateText(category.summary, field: .categorySummary)
        for group in category.groups { try validateText(group.title, field: .groupTitle) }
        guard validID(category.id),
              !category.symbol.isEmpty, category.symbol.utf16.count <= 80,
              category.groups.count <= 30, category.topics.count <= 100,
              unique(category.groups.map(\.id)), unique(category.topics.map(\.id)),
              category.groups.allSatisfy({ validID($0.id) })
        else { throw Failure.invalidContent }

        let groupIDs = Set(category.groups.map(\.id))
        let visibleGroupIDs = Set(category.groups.filter { !$0.isHidden }.map(\.id))
        for topic in category.topics {
            try validateText(topic.title, field: .articleTitle)
            try validateText(topic.summary, field: .articleSummary, required: !topic.isHidden)
            for source in topic.sources { try validateSource(source) }
            if !unique(topic.sources.map(\.url)) {
                throw Failure.field(DirectoryEditorText.value(
                    "У статті «\(topic.title.value(for: AppLanguage.stored))» одне джерело додано двічі. Приберіть повтор.",
                    "Im Beitrag „\(topic.title.value(for: AppLanguage.stored))“ ist eine Quelle doppelt. Entfernen Sie das Duplikat."
                ), nil)
            }
            guard validID(topic.id), groupIDs.contains(topic.groupID),
                  topic.sections.count <= 80, topic.sources.count <= 80,
                  topic.regionalSections.count <= 9,
                  unique(topic.sections.map(\.id))
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
        try validateText(section.title, field: .sectionTitle)
        try validateText(section.body, field: .sectionBody, required: !section.isHidden)
        for contact in section.contacts {
            try validateText(contact.title, field: .contactTitle)
            try validateText(contact.detail, field: .contactDetail)
        }
        guard validID(section.id),
              !section.symbol.isEmpty, section.symbol.utf16.count <= 80,
              section.phoneNumber.map({ $0.utf16.count <= 40 }) ?? true,
              section.contacts.count <= 12,
              section.contacts.allSatisfy({
                  !$0.number.isEmpty && $0.number.utf16.count <= 40 &&
                  $0.number.range(of: "^[0-9 +()/-]+$", options: .regularExpression) != nil
              })
        else { throw Failure.invalidContent }
        if let source = section.source { try validateSource(source) }
        if !section.isHidden && section.source == nil && inheritedSources.isEmpty {
            throw Failure.field(DirectoryEditorText.value(
                "Додайте офіційне HTTPS-джерело до блока «\(section.title.value(for: AppLanguage.stored))» або до статті.",
                "Ergänzen Sie für „\(section.title.value(for: AppLanguage.stored))“ eine offizielle HTTPS-Quelle im Abschnitt oder Beitrag."
            ), nil)
        }
    }

    private static func validID(_ value: String) -> Bool {
        value.range(of: "^[a-z0-9][a-z0-9-]{0,63}$", options: .regularExpression) != nil
    }

    private static func validateText(_ text: DirectoryText, field: DirectoryEditorField,
                                     required: Bool = true) throws {
        for language in [AppLanguage.ukrainian, .german] {
            if let issue = field.issue(for: text.value(for: language), language: language, required: required) {
                throw Failure.field(issue, language)
            }
        }
    }

    private static func validateSource(_ source: DirectoryManagedSource) throws {
        if let issue = DirectorySourceValidation.nameIssue(source.name)
            ?? DirectorySourceValidation.urlIssue(source.url) {
            throw Failure.field(DirectoryEditorText.value(
                "Джерело «\(source.name)»: \(issue)", "Quelle „\(source.name)“: \(issue)"
            ), nil)
        }
    }

    private static func unique(_ ids: [String]) -> Bool {
        Set(ids).count == ids.count
    }
}
