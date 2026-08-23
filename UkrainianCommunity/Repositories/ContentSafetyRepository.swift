import Foundation

protocol ContentSafetyRepository {
    func submitReport(
        target: ContentReportTarget,
        reason: ContentReportReason,
        details: String?
    ) async throws -> ContentReportReceipt
}

struct MockContentSafetyRepository: ContentSafetyRepository {
    var receipt = ContentReportReceipt(
        reportId: "preview-report",
        submittedAt: Date(),
        wasDuplicate: false
    )

    func submitReport(
        target: ContentReportTarget,
        reason: ContentReportReason,
        details: String?
    ) async throws -> ContentReportReceipt {
        receipt
    }
}
