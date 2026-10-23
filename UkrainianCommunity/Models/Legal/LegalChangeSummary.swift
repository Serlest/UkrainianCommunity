import Foundation

/// Keeps both change explanations in the existing Firestore string field.
/// Older single-language summaries remain readable until their next edit.
struct LegalChangeSummary {
    var german: String
    var ukrainian: String
    private(set) var hasSeparateTranslations: Bool

    init(raw: String?) {
        let value = raw ?? ""
        if value.hasPrefix("DE:"), let separator = value.range(of: "\nUK:") {
            hasSeparateTranslations = true
            german = String(value[value.index(value.startIndex, offsetBy: 3)..<separator.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            ukrainian = String(value[separator.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            hasSeparateTranslations = false
            german = value.trimmingCharacters(in: .whitespacesAndNewlines)
            ukrainian = german
        }
    }

    func localized(_ locale: String) -> String {
        locale.lowercased() == "uk" ? ukrainian : german
    }

    var hasBothLanguages: Bool {
        hasSeparateTranslations &&
        !german.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !ukrainian.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var encoded: String? {
        let de = german.trimmingCharacters(in: .whitespacesAndNewlines)
        let uk = ukrainian.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !de.isEmpty || !uk.isEmpty else { return nil }
        return "DE:\(de.replacingOccurrences(of: "\n", with: " "))\nUK:\(uk.replacingOccurrences(of: "\n", with: " "))"
    }
}
