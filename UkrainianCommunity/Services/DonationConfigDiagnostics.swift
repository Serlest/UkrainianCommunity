import Foundation

/// Injected at the repository boundary so confirmed and ambiguous outcomes cannot
/// be confused with optimistic editor state. Text and payment URL are never logged.
struct DonationConfigDiagnostics {
    var confirmed: @MainActor (DonationConfig, String) async -> Void
    var failed: @MainActor (Error, String, String, String?) async -> Void

    static var none: DonationConfigDiagnostics {
        .init(confirmed: { _, _ in }, failed: { _, _, _, _ in })
    }
    static var live: DonationConfigDiagnostics {
        .init(confirmed: { config, actorID in
            let context = SystemAuditLogContext(moduleName: "ProjectSupport", operationName: "saveDonationConfig",
                eventType: .configurationUpdated, targetType: .donationConfig, targetId: DonationConfig.documentID,
                summary: "Project support configuration updated", expectedPrincipalID: actorID,
                metadata: ["resultRevision": fingerprint(config.sourceRevision), "isEnabled": String(config.isEnabled), "confirmation": "serverReadback"])
            Task { await SystemAuditLoggingService.shared.logSuccess(context) }
        }, failed: { error, actorID, stage, revision in
            let context = SystemTechnicalErrorContext(moduleName: "ProjectSupport", operationName: "saveDonationConfig",
                screenName: "DonationSettings", targetType: .donationConfig, targetId: DonationConfig.documentID,
                metadata: ["expectedRevision": fingerprint(revision)], principalID: actorID,
                failureStage: stage, executionMode: "foreground")
            Task { await SystemTechnicalErrorLoggingService.shared.logFailure(error, context: context) }
        })
    }

    /// Human-readable checksum groups, not an exemption from credential redaction.
    /// Only exact SHA256 config revisions can enter this formatting path.
    nonisolated static func fingerprint(_ revision: String?) -> String {
        guard let revision, revision.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { return "missing" }
        let chars = Array(revision)
        return stride(from: 0, to: chars.count, by: 8).map { String(chars[$0..<($0 + 8)]) }.joined(separator: " ")
    }
}
