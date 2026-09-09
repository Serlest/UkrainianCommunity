import Foundation

struct SystemLogActorIdentity: Equatable {
    let displayName: String?
    let email: String?
}

@MainActor
protocol SystemLogActorIdentityResolving {
    func resolve(userID: String) async throws -> SystemLogActorIdentity?
}

/// Resolves the actor only while an authorized administrator is viewing a log.
/// The result is presentation-only and is never written back to the immutable log.
@MainActor
struct LiveSystemLogActorIdentityResolver: SystemLogActorIdentityResolving {
    private let reads: UserManagementReads

    init(reads: UserManagementReads? = nil) {
        self.reads = reads ?? .live
    }

    func resolve(userID: String) async throws -> SystemLogActorIdentity? {
        let user = try await RefreshRequest.run { [reads] in
            try await reads.user(userID)
        }
        guard let user else { return nil }

        return SystemLogActorIdentity(
            displayName: firstNonEmpty(user.displayName, user.fullName),
            email: nonEmpty(user.email)
        )
    }

    private func firstNonEmpty(_ values: String?...) -> String? {
        values.lazy.compactMap(nonEmpty).first
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
