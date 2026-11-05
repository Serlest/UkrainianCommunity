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
        let compactFacts = facts.reduce(into: [String]()) { result, fact in
            let line = fact.trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty, !result.contains(line) { result.append(line) }
        }
        append(compactFacts.joined(separator: "\n"))
        append(shortSummary(introduction: introduction, body: body))
        var links = Set<String>()
        for source in sources {
            guard let url = safeWebURL(source), links.insert(url.absoluteString).inserted else { continue }
            append("\(ukrainian ? "Джерело" : "Quelle"): \(url.absoluteString)")
        }
        append("\(ukrainian ? "Більше інформації — у застосунку UAC" : "Weitere Informationen in der UAC-App"): \(appURL)")
        return paragraphs.joined(separator: "\n\n")
    }

    /// Prefer the editor's existing short summary; never fetch or invent a new one.
    nonisolated static func shortSummary(introduction: String, body: String) -> String {
        let intro = textWithoutImageDisclosure(introduction)
        let source = (intro.isEmpty ? textWithoutImageDisclosure(body) : intro)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !source.isEmpty else { return "" }
        var sentences: [String] = []
        source.enumerateSubstrings(in: source.startIndex..<source.endIndex, options: .bySentences) { sentence, _, _, stop in
            guard let sentence else { return }
            let candidate = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (sentences + [candidate]).joined(separator: " ").count <= 320 else { stop = true; return }
            sentences.append(candidate)
            if sentences.count == 2 { stop = true }
        }
        if !sentences.isEmpty { return sentences.joined(separator: " ") }
        guard source.count > 320 else { return source }
        let prefix = String(source.prefix(317))
        let boundary = prefix.lastIndex(where: \.isWhitespace) ?? prefix.endIndex
        return String(prefix[..<boundary]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    nonisolated static func location(venue: String, address: String?, city: String) -> String {
        let venue = venue.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = (address ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let city = city.trimmingCharacters(in: .whitespacesAndNewlines)
        let cityInAddress = !city.isEmpty && address.range(
            of: "\\b" + NSRegularExpression.escapedPattern(for: city) + "\\b",
            options: [.regularExpression, .caseInsensitive]) != nil
        return [venue, address, cityInAddress ? "" : city].reduce(into: [String]()) { result, part in
            if !part.isEmpty, !result.contains(part) { result.append(part) }
        }.joined(separator: ", ")
    }

    /// Sharing sends text only. Remove narrowly recognized, standalone image
    /// disclosures, while retaining AI-related reporting and the in-app original.
    nonisolated static func textWithoutImageDisclosure(_ text: String) -> String {
        let patterns = [
            #"(?i)^(?:Зображення|Ілюстрація)\s*[—–:-]\s*тематична\s+(?:ШІ|AI)[\s‑–-]*ілюстрація[^.!?\n]*[.!?]?$"#,
            #"(?i)^(?:Das Bild|Die Abbildung|Bild|Abbildung)\s*(?:[—–:-]|ist)\s*(?:eine\s+)?(?:thematische\s+KI[-‑– ]Illustration|KI[-‑– ]generierte\s+(?:Themenillustration|Illustration))[^.!?\n]*[.!?]?$"#
        ]
        return text.components(separatedBy: .newlines).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return !patterns.contains { trimmed.range(of: $0, options: .regularExpression) != nil }
        }.joined(separator: "\n")
            .replacingOccurrences(of: #"\n[\t ]*\n(?:[\t ]*\n)+"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated static func eventSchedule(
        occurrences: [EventOccurrence], detailedSchedule: [String], language: AppLanguage,
        hasOrganizerLink: Bool, calendar: Calendar = .current
    ) -> String {
        let valid = occurrences.filter(\.isValid)
        let days = Set(valid.map { calendar.startOfDay(for: $0.startDate) })
        // One-off events and a few separate dates keep their exact times.
        guard days.count > 3, let first = valid.map(\.startDate).min() else {
            return detailedSchedule.reduce(into: [String]()) { result, line in
                if !result.contains(line) { result.append(line) }
            }.joined(separator: "\n")
        }
        let last = valid.map { occurrence in
            occurrence.isAllDay && occurrence.endDate > occurrence.startDate
                ? occurrence.endDate.addingTimeInterval(-1) : occurrence.endDate
        }.max() ?? first
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.localeIdentifier)
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(calendar.component(.year, from: first) == calendar.component(.year, from: last) ? "d MMMM" : "d MMMM y")
        let start = formatter.string(from: first)
        formatter.setLocalizedDateFormatFromTemplate("d MMMM y")
        let end = formatter.string(from: last)
        let period = "\(language == .ukrainian ? "Період" : "Zeitraum"): \(start) — \(end)"
        let schedule: String
        if language == .ukrainian {
            schedule = hasOrganizerLink ? "Дні та час окремих сеансів — на сайті організатора." : "Дні та час окремих сеансів — у застосунку UAC."
        } else {
            schedule = hasOrganizerLink ? "Einzelne Termine und Uhrzeiten auf der Website des Veranstalters." : "Einzelne Termine und Uhrzeiten in der UAC-App."
        }
        let cancellation = valid.contains { $0.status == .cancelled }
            ? (language == .ukrainian ? "Деякі сеанси скасовано. Перевірте актуальний розклад." : "Einzelne Termine sind abgesagt. Bitte den aktuellen Zeitplan prüfen.") : ""
        return [period, schedule, cancellation].filter { !$0.isEmpty }.joined(separator: "\n")
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
