#if DEBUG
import Foundation

/// Isolated UI data. Enabled only by both explicit UI-test switches.
struct UITestLegalEvidenceRepository: LegalEvidenceRepository {
    func fetchAccounts(query: String?, limit: Int, cursor: LegalEvidenceAccountCursor?) async throws -> LegalEvidenceAccountPage {
        let account = LegalEvidenceAccount(userID: "legal-fixture", displayName: "Audit Fixture", email: "fixture@example.invalid", createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        return LegalEvidenceAccountPage(accounts: [account], nextCursor: nil, totalMatches: 1)
    }

    func fetchEvidencePage(userID: String, cursor: String?, filter: LegalEvidenceFilter, query: String) async throws -> LegalEvidencePage {
        let history = try await fetchEvidence(userID: userID)
        let events = history.events.filter { filter.includes($0.eventType) && (query.isEmpty || $0.matches(query)) }
        let start = cursor.flatMap(Int.init) ?? 0
        let end = min(start + 10, events.count)
        return LegalEvidencePage(history: LegalEvidenceHistory(account: history.account, events: Array(events[start..<end]),
            generatedAt: history.generatedAt, summary: history.summary), nextCursor: end < events.count ? String(end) : nil)
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
        let document = LegalDocument.hardcodedFallback(type: .terms)
        let acceptance = LegalEvidenceEvent(id: "fixture-terms", userID: userID, displayName: nil, email: nil,
            eventType: .termsAccepted, occurredAt: Date(timeIntervalSince1970: 1_800_000_000), version: document.version,
            locale: "uk", appVersion: "fixture", source: "legalDocument", contentHash: document.contentHash,
            organizationID: nil, organizationName: nil, sourceRecordID: "fixture-terms", acceptedFromPlatform: "ios",
            consentID: nil, purposeVersion: nil, disclosureVersion: nil, disclosureText: nil)
        return LegalEvidenceHistory(
            account: account,
            events: [acceptance] + events,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_501),
            summary: [LegalEvidenceStatus(kind: "terms", version: document.version, confirmedAt: nil,
                currentVersion: document.version, state: "current"),
                LegalEvidenceStatus(kind: "analytics", version: "2026.12", confirmedAt: nil, currentVersion: nil, state: "withdrawn")]
        )
    }
}
#endif
