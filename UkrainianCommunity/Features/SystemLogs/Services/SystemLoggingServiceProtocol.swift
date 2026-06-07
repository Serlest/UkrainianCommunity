import Foundation

protocol SystemLoggingServiceProtocol {
    func log(_ draft: SystemLogDraft) async throws
}

extension SystemLoggingServiceProtocol {
    func logAudit(_ draft: SystemLogDraft) async throws {
        try await log(draft.withDefaultRetentionPolicy(.normalAudit))
    }

    func logError(_ draft: SystemLogDraft) async throws {
        try await log(draft.withDefaultRetentionPolicy(.technicalError))
    }

    func logSecurity(_ draft: SystemLogDraft) async throws {
        try await log(draft.withDefaultRetentionPolicy(.security))
    }

    func logModeration(_ draft: SystemLogDraft) async throws {
        try await log(draft.withDefaultRetentionPolicy(.moderationDispute))
    }
}

private extension SystemLogDraft {
    func withDefaultRetentionPolicy(_ defaultRetentionPolicy: SystemLogRetentionPolicy) -> SystemLogDraft {
        var draft = self
        draft.retentionPolicy = draft.retentionPolicy ?? defaultRetentionPolicy
        return draft
    }
}
