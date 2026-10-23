import Foundation

protocol LegalEvidenceRepository {
    func fetchAccounts(
        query: String?,
        limit: Int,
        cursor: LegalEvidenceAccountCursor?
    ) async throws -> LegalEvidenceAccountPage
    func fetchEvidence(userID: String) async throws -> LegalEvidenceHistory
    func fetchEvidencePage(userID: String, cursor: String?, filter: LegalEvidenceFilter, query: String) async throws -> LegalEvidencePage
}

extension LegalEvidenceRepository {
    func fetchEvidencePage(userID: String, cursor: String?, filter: LegalEvidenceFilter, query: String) async throws -> LegalEvidencePage {
        let history = try await fetchEvidence(userID: userID)
        let matches = history.events.filter { filter.includes($0.eventType) && (query.isEmpty || $0.matches(query)) }
        let start = cursor.flatMap(Int.init) ?? 0
        let end = min(start + 50, matches.count)
        guard start >= 0, start <= end else { throw AppError.validationFailed }
        return LegalEvidencePage(history: LegalEvidenceHistory(account: history.account, events: Array(matches[start..<end]),
            generatedAt: history.generatedAt, summary: history.summary), nextCursor: end < matches.count ? String(end) : nil)
    }
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
                    seconds: $0.seconds, nanoseconds: $0.nanoseconds, searchQuery: $0.searchQuery
                )
            }
        )
        return LegalEvidenceAccountPage(
            accounts: response.accounts.map(Self.decode),
            nextCursor: response.nextCursor.flatMap { cursor in
                ISO8601DateFormatter.legalEvidence.date(from: cursor.createdAt).map {
                    LegalEvidenceAccountCursor(userID: cursor.userId, createdAt: $0, seconds: cursor.seconds, nanoseconds: cursor.nanoseconds, searchQuery: cursor.searchQuery)
                }
            },
            totalMatches: response.totalMatches
        )
    }

    func fetchEvidencePage(userID: String, cursor: String?, filter: LegalEvidenceFilter, query: String) async throws -> LegalEvidencePage {
        let response = try await functionsClient.getLegalEvidencePage(userID: userID, cursor: cursor, format: 2,
            filter: filter.rawValue, query: query)
        guard response.account.userId == userID, let generatedAt = ISO8601DateFormatter.legalEvidence.date(from: response.generatedAt) else { throw AppError.unknown }
        let events = try response.events.map { raw in
            guard let event = Self.decode(raw), event.userID == userID else { throw AppError.unknown }
            return event
        }
        return LegalEvidencePage(history: LegalEvidenceHistory(account: Self.decode(response.account), events: events,
            generatedAt: generatedAt, summary: response.summary ?? []), nextCursor: response.nextCursor)
    }

    /// Full history is fetched only for the explicitly requested export.
    func fetchEvidence(userID: String) async throws -> LegalEvidenceHistory {
        var cursor: String?
        var seen = Set<String>()
        var result: LegalEvidenceHistory?
        var events: [String: LegalEvidenceEvent] = [:]
        repeat {
            try Task.checkCancellation()
            let page = try await fetchEvidencePage(userID: userID, cursor: cursor, filter: .all, query: "")
            if result == nil { result = page.history }
            for event in page.history.events { events[event.id] = event }
            cursor = page.nextCursor
            if let cursor, !seen.insert(cursor).inserted { throw AppError.unknown }
        } while cursor != nil
        guard let result else { throw AppError.unknown }
        return LegalEvidenceHistory(account: result.account, events: events.values.sorted {
            $0.occurredAt == $1.occurredAt ? $0.id < $1.id : $0.occurredAt > $1.occurredAt
        }, generatedAt: result.generatedAt, summary: result.summary)
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
