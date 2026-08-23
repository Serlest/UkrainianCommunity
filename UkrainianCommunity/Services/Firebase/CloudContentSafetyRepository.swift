import FirebaseFunctions
import Foundation

struct ContentReportFunctionRequest: Codable, Equatable {
    let targetType: String
    let targetId: String
    let parentType: String?
    let parentId: String?
    let reason: String
    let details: String?
}

private struct ContentReportFunctionResponse: Codable, Equatable {
    let reportId: String
    let status: String
    let submittedAt: String
    let wasDuplicate: Bool
}

struct CloudContentSafetyRepository: ContentSafetyRepository {
    private let client: CloudFunctionsClient

    init(client: CloudFunctionsClient = .shared) {
        self.client = client
    }

    func submitReport(
        target: ContentReportTarget,
        reason: ContentReportReason,
        details: String?
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
                    details: Self.normalizedDetails(details)
                )
            )
            guard response.status == "open",
                  let submittedAt = Self.dateFormatter.date(from: response.submittedAt) else {
                throw ContentReportSubmissionError.unknown
            }
            return ContentReportReceipt(
                reportId: response.reportId,
                submittedAt: submittedAt,
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
