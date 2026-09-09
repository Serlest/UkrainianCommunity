#if DEBUG
import Foundation

/// Isolated UI data. Enabled only by both explicit UI-test switches.
struct UITestLegalEvidenceRepository: LegalEvidenceRepository {
    func fetchAccounts(query: String?, limit: Int, cursor: LegalEvidenceAccountCursor?) async throws -> LegalEvidenceAccountPage {
        let account = LegalEvidenceAccount(userID: "legal-fixture", displayName: "Audit Fixture", email: "fixture@example.invalid", createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        return LegalEvidenceAccountPage(accounts: [account], nextCursor: nil, totalMatches: 1)
    }

    func fetchEvidence(userID: String) async throws -> LegalEvidenceHistory {
        let account = LegalEvidenceAccount(
            userID: userID,
            displayName: "Audit Fixture",
            email: "fixture@example.invalid",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let events = Array((0..<501).map { index in
            LegalEvidenceEvent(id: "fixture-\(index)", userID: userID,
                displayName: nil, email: nil,
                eventType: index % 2 == 0 ? .analyticsGranted : .analyticsWithdrawn,
                occurredAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)),
                version: "2026.12", locale: "de", appVersion: "fixture", source: "ui-test",
                contentHash: nil, organizationID: nil, organizationName: nil,
                sourceRecordID: "fixture-\(index)", acceptedFromPlatform: "ios",
                consentID: nil, purposeVersion: nil, disclosureVersion: nil, disclosureText: nil)
        }.reversed())
        return LegalEvidenceHistory(
            account: account,
            events: events,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_501)
        )
    }
}
#endif
