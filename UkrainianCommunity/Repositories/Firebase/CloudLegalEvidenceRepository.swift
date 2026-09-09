import Foundation

protocol LegalEvidenceRepository {
    func fetchAccounts(
        query: String?,
        limit: Int,
        cursor: LegalEvidenceAccountCursor?
    ) async throws -> LegalEvidenceAccountPage
    func fetchEvidence(userID: String) async throws -> LegalEvidenceHistory
}

enum LegalEvidenceRepositories {
    static func makeDefault() -> LegalEvidenceRepository {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing"),
           ProcessInfo.processInfo.environment["UITestLegalEvidence"] == "1" {
            return UITestLegalEvidenceRepository()
        }
        #endif
        return CloudLegalEvidenceRepository()
    }
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
                    createdAt: ISO8601DateFormatter.legalEvidence.string(from: $0.createdAt),
                    seconds: $0.seconds, nanoseconds: $0.nanoseconds
                )
            }
        )
        return LegalEvidenceAccountPage(
            accounts: response.accounts.map(Self.decode),
            nextCursor: response.nextCursor.flatMap { cursor in
                ISO8601DateFormatter.legalEvidence.date(from: cursor.createdAt).map {
                    LegalEvidenceAccountCursor(userID: cursor.userId, createdAt: $0, seconds: cursor.seconds, nanoseconds: cursor.nanoseconds)
                }
            },
            totalMatches: response.totalMatches
        )
    }

    func fetchEvidence(userID: String) async throws -> LegalEvidenceHistory {
        var cursor: String?
        var seen = Set<String>()
        var events: [String: LegalEvidenceEvent] = [:]
        var account: LegalEvidenceAccount?
        var generatedAt: Date?
        repeat {
            try Task.checkCancellation()
            let response = try await functionsClient.getLegalEvidencePage(userID: userID, cursor: cursor)
            if account == nil { account = Self.decode(response.account) }
            if generatedAt == nil {
                generatedAt = ISO8601DateFormatter.legalEvidence.date(from: response.generatedAt)
            }
            for raw in response.events {
                guard let event = Self.decode(raw) else { throw AppError.unknown }
                events[event.id] = event
            }
            cursor = response.nextCursor
            if let cursor, !seen.insert(cursor).inserted { throw AppError.unknown }
        } while cursor != nil
        let sortedEvents = events.values.sorted {
            $0.occurredAt == $1.occurredAt ? $0.id < $1.id : $0.occurredAt > $1.occurredAt
        }
        guard let account, let generatedAt else { throw AppError.unknown }
        return LegalEvidenceHistory(account: account, events: sortedEvents, generatedAt: generatedAt)
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
            // Identity returned by older endpoints is a current account join, not a receipt snapshot.
            displayName: nil,
            email: nil,
            eventType: eventType,
            occurredAt: occurredAt,
            version: event.version,
            locale: event.locale,
            appVersion: event.appVersion,
            source: event.source,
            contentHash: event.contentHash,
            organizationID: event.organizationId,
            organizationName: event.organizationName,
            sourceRecordID: event.sourceRecordId,
            acceptedFromPlatform: event.acceptedFromPlatform,
            consentID: event.consentId,
            purposeVersion: event.purposeVersion,
            disclosureVersion: event.disclosureVersion,
            disclosureText: event.disclosureText
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
