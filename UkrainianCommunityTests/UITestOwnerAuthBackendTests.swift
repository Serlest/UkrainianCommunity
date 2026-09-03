#if DEBUG && targetEnvironment(simulator)
import Testing
@testable import UkrainianCommunity

@MainActor
struct UITestOwnerAuthBackendTests {
    @Test func fixtureRequiresBothExplicitUITestModeAndOwnerScenario() {
        #expect(UITestOwnerAuthBackend.makeIfRequested(arguments: [], environment: ["UITestForceOwnerSession": "1"]) == nil)
        #expect(UITestOwnerAuthBackend.makeIfRequested(arguments: ["-ui-testing"], environment: [:]) == nil)
    }

    @Test func fixtureModelsBothSecondFactorStatesWithoutRelaxingThePolicy() async throws {
        for missing in [false, true] {
            let backend = try #require(UITestOwnerAuthBackend.makeIfRequested(arguments: ["-ui-testing"], environment: [
                "UITestForceOwnerSession": "1", "UITestOwnerSecondFactor": missing ? "missing" : "totp",
            ]))
            let owner = MockContentBuilder.ownerUser(requiresMultiFactorAuth: true)
            let authenticated = try await backend.isCurrentSessionTOTPAuthenticated()
            #expect(AuthSecurityPolicy.protectedSessionIsReady(user: owner, isTOTPAuthenticated: authenticated) == !missing)
            try backend.signOut()
            #expect(try await backend.isCurrentSessionTOTPAuthenticated() == false)
            #expect(backend.currentSessionUser == nil)
        }
    }
}
#endif
