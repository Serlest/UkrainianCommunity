import Foundation

/// Matches callable string limits (JavaScript UTF-16 length), including emoji.
nonisolated enum FeedbackSupportValidation {
    static func text(_ value: String, minimum: Int = 1, maximum: Int) -> Bool {
        let count = value.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count
        return (minimum...maximum).contains(count)
    }

    static func decision(facts: String, legalBasis: String, termsBasis: String,
                         territory: String, duration: String, redress: String, humanReviewed: Bool) -> Bool {
        humanReviewed && text(facts, minimum: 20, maximum: 5_000)
            && (text(legalBasis, maximum: 2_000) || text(termsBasis, maximum: 2_000))
            && legalBasis.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count <= 2_000
            && termsBasis.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count <= 2_000
            && text(territory, maximum: 500) && text(duration, maximum: 500)
            && text(redress, maximum: 2_000)
    }
}
