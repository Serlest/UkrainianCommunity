import Foundation
import Testing
@testable import UkrainianCommunity

@Suite("Content safety contract")
struct ContentSafetyTests {
    @Test func cloudFunctionAndReasonValuesMatchBackendContract() throws {
        #expect(CloudFunctionName.submitContentReport.rawValue == "submitContentReport")
        #expect(CloudFunctionName.allCases.contains(.submitContentReport))
        #expect(Set(ContentReportReason.allCases.map(\.rawValue)) == Set([
            "harassment",
            "hate",
            "violence",
            "sexual",
            "spam",
            "misinformation",
            "privacy",
            "other"
        ]))
    }

    @Test func commentTargetCarriesItsTrustedParentIdentity() throws {
        let comment = Comment(
            id: "comment-1",
            parentType: .event,
            parentId: "event-1",
            authorId: "author-1",
            authorName: "Author",
            text: "Comment",
            createdAt: .now
        )

        let target = try #require(ContentReportTarget.comment(comment, parentTitle: "Community event"))
        #expect(target.targetType == .comment)
        #expect(target.targetId == "comment-1")
        #expect(target.parentType == .event)
        #expect(target.parentId == "event-1")
        #expect(target.authorId == "author-1")
    }

    @Test func commentWithoutParentCannotBecomeAReportTarget() {
        let comment = Comment(
            id: "legacy-comment",
            authorId: "author-1",
            authorName: "Author",
            text: "Legacy comment",
            createdAt: .now
        )

        #expect(ContentReportTarget.comment(comment, parentTitle: "Missing parent") == nil)
    }

    @Test func contentReportRequestOmitsEmptyOptionalFields() throws {
        let request = ContentReportFunctionRequest(
            targetType: "news",
            targetId: "news-1",
            parentType: nil,
            parentId: nil,
            reason: "spam",
            illegalExplanation: "This listing uses a fraudulent payment link.",
            legalBasis: nil,
            evidence: nil,
            goodFaithConfirmed: true
        )
        let object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        )

        #expect(object["targetType"] as? String == "news")
        #expect(object["targetId"] as? String == "news-1")
        #expect(object["reason"] as? String == "spam")
        #expect(object["parentType"] == nil)
        #expect(object["parentId"] == nil)
        #expect(object["illegalExplanation"] as? String == "This listing uses a fraudulent payment link.")
        #expect(object["legalBasis"] == nil)
        #expect(object["evidence"] == nil)
        #expect(object["goodFaithConfirmed"] as? Bool == true)
    }
}
