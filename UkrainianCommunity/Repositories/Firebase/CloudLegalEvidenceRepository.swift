import Foundation

protocol LegalEvidenceRepository {
    func fetchAccounts(
        query: String?,
        limit: Int,
        cursor: LegalEvidenceAccountCursor?
    ) async throws -> LegalEvidenceAccountPage
    func fetchEvidence(userID: String) async throws -> [LegalEvidenceEvent]
}

struct CloudLegalEvidenceRepository: LegalEvidenceRepository {
    private let functionsClient: CloudFunctionsClient

    init(functionsClient: CloudFunctionsClient = .shared) {
        self.functionsClient = functionsClient
    }

    func fetchAccounts(
        query: String?,
        limit: Int = 50,
        cursor: LegalEvidenceAccountCursor? = nil
    ) async throws -> LegalEvidenceAccountPage {
        let response = try await functionsClient.listLegalEvidenceAccounts(
            query: query,
            limit: limit,
            cursor: cursor.map {
                LegalEvidenceAccountCursorFunctionValue(
                    userId: $0.userID,
                    createdAt: ISO8601DateFormatter.legalEvidence.string(from: $0.createdAt)
                )
            }
        )
        return LegalEvidenceAccountPage(
            accounts: response.accounts.map(Self.decode),
            nextCursor: response.nextCursor.flatMap { cursor in
                ISO8601DateFormatter.legalEvidence.date(from: cursor.createdAt).map {
                    LegalEvidenceAccountCursor(userID: cursor.userId, createdAt: $0)
                }
            },
            totalMatches: response.totalMatches
        )
    }

    func fetchEvidence(userID: String) async throws -> [LegalEvidenceEvent] {
        let response = try await functionsClient.getLegalEvidenceForUser(userID: userID)
        return response.events.compactMap(Self.decode)
    }

    private static func decode(_ account: LegalEvidenceAccountFunctionValue) -> LegalEvidenceAccount {
        LegalEvidenceAccount(
            userID: account.userId,
            displayName: account.displayName,
            email: account.email,
            createdAt: account.createdAt.flatMap(ISO8601DateFormatter.legalEvidence.date(from:))
        )
    }

    private static func decode(_ event: LegalEvidenceFunctionEvent) -> LegalEvidenceEvent? {
        guard
            let eventType = LegalEvidenceEventType(rawValue: event.eventType),
            let occurredAt = ISO8601DateFormatter.legalEvidence.date(from: event.occurredAt)
        else {
            return nil
        }
        return LegalEvidenceEvent(
            id: event.id,
            userID: event.userId,
            displayName: event.displayName,
            email: event.email,
            eventType: eventType,
            occurredAt: occurredAt,
            version: event.version,
            locale: event.locale,
            appVersion: event.appVersion,
            source: event.source,
            contentHash: event.contentHash,
            organizationID: event.organizationId,
            organizationName: event.organizationName
        )
    }
}

private extension ISO8601DateFormatter {
    static let legalEvidence: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
