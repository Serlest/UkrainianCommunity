#if DEBUG
import Foundation

/// Isolated UI data. Enabled only by both explicit UI-test switches.
struct UITestLegalEvidenceRepository: LegalEvidenceRepository {
    func fetchAccounts(query: String?, limit: Int, cursor: LegalEvidenceAccountCursor?) async throws -> LegalEvidenceAccountPage {
        let account = LegalEvidenceAccount(userID: "legal-fixture", displayName: "Audit Fixture", email: "fixture@example.invalid", createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        return LegalEvidenceAccountPage(accounts: [account], nextCursor: nil, totalMatches: 1)
    }

    func fetchEvidence(userID: String) async throws -> [LegalEvidenceEvent] {
        Array((0..<501).map { index in
            LegalEvidenceEvent(id: "fixture-\(index)", userID: userID,
                displayName: "Audit Fixture", email: "fixture@example.invalid",
                eventType: index % 2 == 0 ? .analyticsGranted : .analyticsWithdrawn,
                occurredAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)),
                version: "2026.12", locale: "de", appVersion: "fixture", source: "ui-test",
                contentHash: nil, organizationID: nil, organizationName: nil)
        }.reversed())
    }
}
#endif
