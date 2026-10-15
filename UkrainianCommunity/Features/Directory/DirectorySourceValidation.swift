import Foundation

enum DirectorySourceValidation {
    static let nameLimit = 160
    static let urlLimit = 1024

    /// Accept editor input, but only return a credential-free HTTPS URL for storage/opening.
    static func normalizedURL(_ input: String) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              value.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil,
              value.rangeOfCharacter(from: CharacterSet(charactersIn: "\\<>\"{}|^`")) == nil,
              value.range(of: "%(?![0-9a-fA-F]{2})", options: .regularExpression) == nil else { return nil }

        let candidate: String
        let lower = value.lowercased()
        if lower.hasPrefix("https://") {
            candidate = "https://" + value.dropFirst(8)
        } else if lower.hasPrefix("http://") {
            candidate = "https://" + value.dropFirst(7)
        } else {
            guard !value.hasPrefix("/"),
                  value.range(of: "^[a-zA-Z][a-zA-Z0-9+.-]*:", options: .regularExpression) == nil ||
                    value.range(of: "^(?:[^/?#:@]+\\.[^/?#:@]+|localhost):[0-9]+(?:[/?#]|$)",
                                options: .regularExpression) != nil else { return nil }
            candidate = "https://" + value
        }
        guard var components = URLComponents(string: candidate),
              components.user == nil, components.password == nil,
              let host = components.url?.host, !host.isEmpty,
              host.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil,
              host.rangeOfCharacter(from: CharacterSet(charactersIn: "/?#@\\%")) == nil,
              components.port.map({ (1...65535).contains($0) }) ?? true else { return nil }
        if lower.hasPrefix("http://"), components.port == 80 { components.port = nil }
        return components.url?.absoluteString
    }

    static func normalizingSources(in source: DirectoryManagedSource) -> DirectoryManagedSource {
        var result = source
        if let url = normalizedURL(source.url) { result.url = url }
        return result
    }

    static func normalizingSources(in section: DirectoryManagedSection) -> DirectoryManagedSection {
        var result = section
        result.source = section.source.map { normalizingSources(in: $0) }
        return result
    }

    static func normalizingSources(in topic: DirectoryManagedTopic) -> DirectoryManagedTopic {
        var result = topic
        result.sources = topic.sources.map { normalizingSources(in: $0) }
        result.sections = topic.sections.map { normalizingSources(in: $0) }
        result.regionalSections = topic.regionalSections.mapValues { $0.map { normalizingSources(in: $0) } }
        return result
    }

    static func normalizingSources(in category: DirectoryManagedCategory) -> DirectoryManagedCategory {
        var result = category
        result.topics = category.topics.map { normalizingSources(in: $0) }
        return result
    }

    static func nameIssue(_ value: String) -> String? {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return DirectoryEditorText.value("Вкажіть назву установи або джерела.", "Geben Sie den Namen der Behörde oder Quelle an.")
        }
        if value.utf16.count > nameLimit {
            return DirectoryEditorText.value("Назва джерела: максимум \(nameLimit) символів.", "Quellenname: maximal \(nameLimit) Zeichen.")
        }
        return nil
    }

    static func urlIssue(_ value: String) -> String? {
        let normalized = normalizedURL(value)
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return DirectoryEditorText.value("Додайте адресу сторінки, наприклад serlest.com. HTTPS додамо автоматично.",
                                             "Geben Sie die Seitenadresse ein, z. B. serlest.com. HTTPS wird automatisch ergänzt.")
        }
        if (normalized ?? value).utf16.count > urlLimit {
            return DirectoryEditorText.value("Посилання: максимум \(urlLimit) символів.", "Link: maximal \(urlLimit) Zeichen.")
        }
        guard normalized != nil else {
            return DirectoryEditorText.value("Перевірте адресу: без пробілів усередині, логіна чи пароля. Вкажіть сайт або повне посилання; збережемо через HTTPS.",
                                             "Prüfen Sie die Adresse: keine Leerzeichen innerhalb, kein Benutzername oder Passwort. Website oder vollständigen Link eingeben; gespeichert wird mit HTTPS.")
        }
        return nil
    }
}
