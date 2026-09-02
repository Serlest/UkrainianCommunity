import Foundation

/// The callable returns JavaScript `Date.toISOString()` strings, including milliseconds.
nonisolated struct OwnerContentPublicationResponse: Decodable {
    let draftId: String
    let kind: String
    let contentId: String
    let leaseId: String
    let expiresAt: String
    let contentAlreadyExists: Bool
    let existingModerationStatus: String?
    let existingScheduledAt: String?

    @MainActor func lease(forDraftID expectedDraftID: String) throws -> OwnerContentPublicationLease {
        guard draftId == expectedDraftID,
              !contentId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !leaseId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let kind = OwnerContentDraftKind(rawValue: kind),
              let expiresAt = OwnerContentDraftDateParser.parse(expiresAt) else {
            throw AppError.validationFailed
        }
        let moderationStatus = existingModerationStatus.flatMap(ModerationStatus.init(rawValue:))
        let scheduledAt = existingScheduledAt.flatMap(OwnerContentDraftDateParser.parse)
        guard existingModerationStatus == nil || moderationStatus != nil,
              existingScheduledAt == nil || scheduledAt != nil,
              contentAlreadyExists == (moderationStatus != nil),
              moderationStatus == .draft || scheduledAt == nil else {
            throw AppError.validationFailed
        }
        return OwnerContentPublicationLease(
            draftID: draftId,
            kind: kind,
            contentID: contentId,
            leaseID: leaseId,
            expiresAt: expiresAt,
            contentAlreadyExists: contentAlreadyExists,
            existingModerationStatus: moderationStatus,
            existingScheduledAt: scheduledAt
        )
    }
}

nonisolated enum OwnerContentDraftDateParser {
    static func parse(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        // Older planning payloads can contain whole-second ISO 8601 dates.
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
