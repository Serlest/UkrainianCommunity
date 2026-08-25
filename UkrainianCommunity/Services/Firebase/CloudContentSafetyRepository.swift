import FirebaseFunctions
import Foundation

nonisolated struct ContentReportFunctionRequest: Codable, Equatable {
    let targetType: String
    let targetId: String
    let parentType: String?
    let parentId: String?
    let reason: String
    let illegalExplanation: String
    let legalBasis: String?
    let evidence: String?
    let goodFaithConfirmed: Bool
}

private nonisolated struct ContentReportFunctionResponse: Codable, Equatable {
    let reportId: String
    let status: String
    let submittedAt: String
    let wasDuplicate: Bool
    let caseNumber: String
    let accessToken: String
    let acknowledgementAt: String
}

struct CloudContentSafetyRepository: ContentSafetyRepository {
    private let client: CloudFunctionsClient

    init(client: CloudFunctionsClient = .shared) {
        self.client = client
    }

    func submitReport(
        target: ContentReportTarget,
        reason: ContentReportReason,
        submission: ContentReportSubmission
    ) async throws -> ContentReportReceipt {
        do {
            let response: ContentReportFunctionResponse = try await client.call(
                .submitContentReport,
                request: ContentReportFunctionRequest(
                    targetType: target.targetType.rawValue,
                    targetId: target.targetId,
                    parentType: target.parentType?.rawValue,
                    parentId: target.parentId,
                    reason: reason.rawValue,
                    illegalExplanation: submission.illegalExplanation.trimmingCharacters(in: .whitespacesAndNewlines),
                    legalBasis: Self.normalizedDetails(submission.legalBasis),
                    evidence: Self.normalizedDetails(submission.evidence),
                    goodFaithConfirmed: submission.goodFaithConfirmed
                )
            )
            guard response.status == "open",
                  let submittedAt = Self.dateFormatter.date(from: response.submittedAt),
                  let acknowledgementAt = Self.dateFormatter.date(from: response.acknowledgementAt),
                  !response.caseNumber.isEmpty,
                  !response.accessToken.isEmpty else {
                throw ContentReportSubmissionError.unknown
            }
            return ContentReportReceipt(
                reportId: response.reportId,
                caseNumber: response.caseNumber,
                accessToken: response.accessToken,
                submittedAt: submittedAt,
                acknowledgementAt: acknowledgementAt,
                wasDuplicate: response.wasDuplicate
            )
        } catch let error as ContentReportSubmissionError {
            throw error
        } catch {
            throw Self.submissionError(from: error)
        }
    }

    private static func normalizedDetails(_ details: String?) -> String? {
        let normalized = details?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalized.isEmpty ? nil : normalized
    }

    private static func submissionError(from error: Error) -> ContentReportSubmissionError {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return .network
        }
        guard let code = FunctionsErrorCode(rawValue: nsError.code) else {
            return .unknown
        }

        switch code {
        case .unauthenticated:
            return .authenticationRequired
        case .permissionDenied:
            return .permissionDenied
        case .notFound:
            return .targetUnavailable
        case .failedPrecondition:
            return nsError.localizedDescription.localizedCaseInsensitiveContains("own content")
                ? .ownContent
                : .targetUnavailable
        case .unavailable, .deadlineExceeded:
            return .network
        default:
            return .unknown
        }
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
