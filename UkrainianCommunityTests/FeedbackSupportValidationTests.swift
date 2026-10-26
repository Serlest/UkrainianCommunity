import Testing
@testable import UkrainianCommunity

struct FeedbackSupportValidationTests {
    @Test func callableLimitsCountEmojiLikeTheServer() {
        #expect(FeedbackSupportValidation.text(String(repeating: "😀", count: 2500), maximum: 5000))
        #expect(!FeedbackSupportValidation.text(String(repeating: "😀", count: 2501), maximum: 5000))
        #expect(!FeedbackSupportValidation.text(" \n ", maximum: 5000))
        #expect(!FeedbackSupportValidation.text("too short", minimum: 20, maximum: 5000))
    }
    @Test func decisionRequiresHumanReviewAndKeepsEveryFieldWithinItsContract() {
        func valid(_ facts: String = String(repeating: "f", count: 20), legal: String = "", terms: String = "Terms clause",
                   territory: String = "Austria", duration: String = "Permanent", redress: String = "Internal appeal", human: Bool = true) -> Bool {
            FeedbackSupportValidation.decision(facts: facts, legalBasis: legal, termsBasis: terms,
                territory: territory, duration: duration, redress: redress, humanReviewed: human)
        }
        #expect(valid())
        #expect(!valid(human: false))
        #expect(!valid(terms: ""))
        #expect(!valid(String(repeating: "f", count: 5001)))
        #expect(!valid(legal: String(repeating: "l", count: 2001)))
        #expect(!valid(terms: String(repeating: "t", count: 2001)))
        #expect(!valid(territory: String(repeating: "a", count: 501)))
        #expect(!valid(duration: String(repeating: "a", count: 501)))
        #expect(!valid(redress: String(repeating: "a", count: 2001)))
        #expect(!valid(territory: "\n "))
    }
}
