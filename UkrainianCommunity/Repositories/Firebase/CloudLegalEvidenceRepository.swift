import Foundation

protocol LegalEvidenceRepository {
    func fetchRecentEvidence(limit: Int) async throws -> [LegalEvidenceEvent]
}

struct CloudLegalEvidenceRepository: LegalEvidenceRepository {
    private let functionsClient: CloudFunctionsClient

    init(functionsClient: CloudFunctionsClient = .shared) {
        self.functionsClient = functionsClient
    }

    func fetchRecentEvidence(limit: Int = 200) async throws -> [LegalEvidenceEvent] {
        let response = try await functionsClient.listLegalEvidence(limit: limit)
        return response.events.compactMap(Self.decode)
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
