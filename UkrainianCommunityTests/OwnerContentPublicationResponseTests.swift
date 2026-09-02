import Foundation
import Testing
@testable import UkrainianCommunity

/// Same JSON field names, nulls and millisecond timestamps as the publication callable.
enum OwnerContentPublicationResponseFixture {
    static func data(
        kind: OwnerContentDraftKind = .news,
        overrides: [String: Any] = [:]
    ) throws -> Data {
        let json = """
        {
          "draftId": "draft-1",
          "kind": "news",
          "contentId": "planning-draft-1",
          "leaseId": "lease-1",
          "expiresAt": "2099-09-02T17:40:00.123Z",
          "contentAlreadyExists": false,
          "existingModerationStatus": null,
          "existingScheduledAt": null
        }
        """
        var fields = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        fields["kind"] = kind.rawValue
        fields.merge(overrides) { _, new in new }
        return try JSONSerialization.data(withJSONObject: fields)
    }

    static func response(
        kind: OwnerContentDraftKind = .news,
        overrides: [String: Any] = [:]
    ) throws -> OwnerContentPublicationResponse {
        try JSONDecoder().decode(OwnerContentPublicationResponse.self, from: data(kind: kind, overrides: overrides))
    }
}

@MainActor
struct OwnerContentPublicationResponseTests {
    @Test(arguments: OwnerContentDraftKind.allCases)
    func acceptsTheServerResponseIncludingMilliseconds(kind: OwnerContentDraftKind) throws {
        let response = try OwnerContentPublicationResponseFixture.response(kind: kind)
        let lease = try response.lease(forDraftID: "draft-1")
        let wholeSeconds = try #require(ISO8601DateFormatter().date(from: "2099-09-02T17:40:00Z"))

        #expect(lease.kind == kind)
        #expect(lease.contentID == "planning-draft-1")
        #expect(lease.leaseID == "lease-1")
        #expect(abs(lease.expiresAt.timeIntervalSince(wholeSeconds) - 0.123) < 0.000_01)
        #expect(!lease.contentAlreadyExists)
        #expect(lease.existingModerationStatus == nil)
        #expect(lease.existingScheduledAt == nil)
    }

    @Test(arguments: OwnerContentDraftKind.allCases, [".456", ""])
    func recoversExistingScheduledContent(kind: OwnerContentDraftKind, fraction: String) throws {
        let response = try OwnerContentPublicationResponseFixture.response(kind: kind, overrides: [
            "expiresAt": "2099-09-02T17:40:00\(fraction)Z",
            "contentAlreadyExists": true,
            "existingModerationStatus": "draft",
            "existingScheduledAt": "2099-09-03T09:00:00\(fraction)Z",
        ])
        let lease = try response.lease(forDraftID: "draft-1")
        let scheduledAt = try #require(lease.existingScheduledAt)
        let wholeSeconds = try #require(ISO8601DateFormatter().date(from: "2099-09-03T09:00:00Z"))

        #expect(lease.contentAlreadyExists)
        #expect(lease.existingModerationStatus == .draft)
        #expect(abs(scheduledAt.timeIntervalSince(wholeSeconds) - (fraction.isEmpty ? 0 : 0.456)) < 0.000_01)
    }

    @Test(arguments: ["approved", "pendingReview"])
    func recoversExistingUnscheduledContent(status: String) throws {
        let response = try OwnerContentPublicationResponseFixture.response(overrides: [
            "contentAlreadyExists": true,
            "existingModerationStatus": status,
        ])
        let lease = try response.lease(forDraftID: "draft-1")

        #expect(lease.contentAlreadyExists)
        #expect(lease.existingModerationStatus?.rawValue == status)
        #expect(lease.existingScheduledAt == nil)
    }

    @Test(arguments: ["draftId", "kind", "contentId", "leaseId", "expiresAt", "existingModerationStatus", "existingScheduledAt"])
    func rejectsInvalidResponseFields(field: String) throws {
        let response = try OwnerContentPublicationResponseFixture.response(overrides: [field: ""])
        #expect(throws: AppError.validationFailed) { try response.lease(forDraftID: "draft-1") }
    }

    @Test(arguments: [true, false])
    func rejectsContradictoryExistingContentFlag(exists: Bool) throws {
        let response = try OwnerContentPublicationResponseFixture.response(overrides: [
            "contentAlreadyExists": exists,
            "existingModerationStatus": exists ? NSNull() : "approved",
        ])
        #expect(throws: AppError.validationFailed) { try response.lease(forDraftID: "draft-1") }
    }

    @Test func rejectsScheduledDateOnAlreadyPublishedContent() throws {
        let response = try OwnerContentPublicationResponseFixture.response(overrides: [
            "contentAlreadyExists": true,
            "existingModerationStatus": "approved",
            "existingScheduledAt": "2099-09-03T09:00:00.456Z",
        ])
        #expect(throws: AppError.validationFailed) { try response.lease(forDraftID: "draft-1") }
    }

    @Test func parsesPlanningPayloadDatesWithTimezoneOffsets() throws {
        let localDate = try #require(OwnerContentDraftDateParser.parse("2099-09-03T11:00:00.456+02:00"))
        let utcDate = try #require(OwnerContentDraftDateParser.parse("2099-09-03T09:00:00.456Z"))
        #expect(localDate == utcDate)
        #expect(OwnerContentDraftDateParser.parse("not-a-date") == nil)
    }
}
