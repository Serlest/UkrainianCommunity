import Foundation

/// One plain-text item keeps the article and its links together in receivers
/// that ignore ShareLink's optional message (for example, some messengers).
enum ContentShareText {
    nonisolated static let appURL = "https://apps.apple.com/at/app/uac/id6772565024"

    nonisolated static func compose(
        title: String, introduction: String, body: String,
        facts: [String] = [], sources: [String?], language: AppLanguage
    ) -> String {
        let ukrainian = language == .ukrainian
        var paragraphs: [String] = []
        func append(_ raw: String) {
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, !paragraphs.contains(text) else { return }
            paragraphs.append(text)
        }
        append(title)
        for fact in facts { append(fact) }
        let intro = introduction.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = body.trimmingCharacters(in: .whitespacesAndNewlines)
        // Do not repeat the summary when the full article already starts with it.
        if !content.hasPrefix(intro) { append(intro) }
        append(content)
        var links = Set<String>()
        for source in sources {
            guard let url = safeWebURL(source), links.insert(url.absoluteString).inserted else { continue }
            append("\(ukrainian ? "Джерело" : "Quelle"): \(url.absoluteString)")
        }
        append("\(ukrainian ? "Більше інформації — у застосунку UAC" : "Weitere Informationen in der UAC-App"): \(appURL)")
        return paragraphs.joined(separator: "\n\n")
    }

    nonisolated static func safeWebURL(_ value: String?) -> URL? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: value), let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme), url.host?.isEmpty == false,
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    nonisolated static func price(_ pricing: EventPricing, language: AppLanguage) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: language.localeIdentifier)
        formatter.numberStyle = .currency
        formatter.currencyCode = pricing.currencyCode
        func amount(_ number: Double?) -> String? {
            guard let number else { return nil }
            return formatter.string(from: NSNumber(value: number))
        }
        switch pricing.kind {
        case .unspecified: return ""
        case .free: return language == .ukrainian ? "Безкоштовно" : "Kostenlos"
        case .exact: return amount(pricing.amount) ?? ""
        case .startingFrom:
            guard let value = amount(pricing.amount) else { return "" }
            return "\(language == .ukrainian ? "Ціна від" : "Preis ab") \(value)"
        case .range:
            guard let minimum = amount(pricing.amount), let maximum = amount(pricing.maximumAmount) else { return "" }
            return "\(minimum)–\(maximum)"
        }
    }
}
