import Foundation
import Testing
@testable import UkrainianCommunity

struct ContentTranslationTests {
    @Test func translationCannotReplaceNewerEditsOrAnotherAccountsDraft() {
        let draft = ContentTranslationPreview(userID: "a", sources: ["Текст", ""], previousTargets: ["Alter Text", ""], indices: [0], translations: ["Neuer Text"])
        #expect(draft.isCurrent(userID: "a", sources: ["Текст", ""], targets: ["Alter Text", ""]))
        #expect(!draft.isCurrent(userID: "b", sources: draft.sources, targets: draft.previousTargets))
        #expect(!draft.isCurrent(userID: "a", sources: ["Змінений текст", ""], targets: draft.previousTargets))
        #expect(!draft.isCurrent(userID: "a", sources: draft.sources, targets: ["Meine neue Fassung", ""]))
        #expect(draft.indices == [0])
    }
}
