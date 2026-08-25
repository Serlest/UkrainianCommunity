import Foundation

protocol ContentSafetyRepository {
    func submitReport(
        target: ContentReportTarget,
        reason: ContentReportReason,
        submission: ContentReportSubmission
    ) async throws -> ContentReportReceipt
}

struct MockContentSafetyRepository: ContentSafetyRepository {
    var receipt = ContentReportReceipt(
        reportId: "preview-report",
        caseNumber: "UC-20260825-PREVIEW",
        accessToken: "preview-access-token",
        submittedAt: Date(),
        acknowledgementAt: Date(),
        wasDuplicate: false
    )

    func submitReport(
        target: ContentReportTarget,
        reason: ContentReportReason,
        submission: ContentReportSubmission
    ) async throws -> ContentReportReceipt {
        receipt
    }
}
