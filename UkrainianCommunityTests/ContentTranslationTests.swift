import Foundation
import Testing
@testable import UkrainianCommunity

struct ContentTranslationTests {
    @Test func translationCannotReplaceNewerEditsOrAnotherAccountsDraft() {
        let draft = ContentTranslationPreview(userID: "a", organizationID: "org-a", sources: ["Текст", ""], previousTargets: ["Alter Text", ""], indices: [0], translations: ["Neuer Text"])
        #expect(draft.isCurrent(userID: "a", organizationID: "org-a", sources: ["Текст", ""], targets: ["Alter Text", ""]))
        #expect(!draft.isCurrent(userID: "b", organizationID: "org-a", sources: draft.sources, targets: draft.previousTargets))
        #expect(!draft.isCurrent(userID: "a", organizationID: "org-b", sources: draft.sources, targets: draft.previousTargets))
        #expect(!draft.isCurrent(userID: "a", organizationID: "org-a", sources: ["Змінений текст", ""], targets: draft.previousTargets))
        #expect(!draft.isCurrent(userID: "a", organizationID: "org-a", sources: draft.sources, targets: ["Meine neue Fassung", ""]))
        #expect(draft.indices == [0])
    }
}

@MainActor
struct LegalTranslationSessionTests {
    @Test func previewCannotSurviveSameAccountReauthenticationOrRoleLoss() {
        let owner = AppUser(id: "fixture", fullName: "Fixture", city: "Vienna", email: "fixture@uac.test", bio: "", role: .user, globalRole: .owner, blockState: .active, createdAt: .now, updatedAt: .now)
        let scope = ProfileAccessIdentity(user: owner)
        let preview = ContentTranslationPreview(userID: "fixture", organizationID: nil, sources: ["Source"], previousTargets: ["Target"], indices: [0], translations: ["Translation"], authorizationRevision: 2, authority: scope)
        #expect(preview.isCurrent(userID: "fixture", organizationID: nil, sources: ["Source"], targets: ["Target"], authorizationRevision: 2, authority: scope))
        #expect(!preview.isCurrent(userID: "fixture", organizationID: nil, sources: ["Source"], targets: ["Target"], authorizationRevision: 3, authority: scope))
        let demoted = AppUser(id: owner.id, fullName: owner.fullName, city: owner.city, email: owner.email, bio: owner.bio, role: .user, globalRole: .user, blockState: .active, createdAt: owner.createdAt, updatedAt: .now)
        #expect(!preview.isCurrent(userID: "fixture", organizationID: nil, sources: ["Source"], targets: ["Target"], authorizationRevision: 2, authority: ProfileAccessIdentity(user: demoted)))
    }
}
