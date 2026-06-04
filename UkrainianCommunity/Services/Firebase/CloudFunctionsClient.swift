import FirebaseFunctions
import Foundation

enum CloudFunctionName: String, CaseIterable {
    case assignOrganizationAdmin
    case removeOrganizationAdmin
    case assignOrganizationModerator
    case removeOrganizationModerator
    case transferOrganizationOwnership
    case approveOrganization
    case rejectOrganization
    case requestOrganizationRevision
    case submitGuideArticleForReview
    case approveGuideArticle
    case publishGuideArticle
    case archiveGuideArticle
    case assignAppAdmin
    case removeAppAdmin
    case assignAppModerator
    case removeAppModerator
    case assignGuideEditor
    case removeGuideEditor
    case warnUser
    case suspendUser
    case banUser
    case deactivateUser
    case restoreUser
    case acceptLegalDocument
}

enum CloudOrganizationRole: String, Codable, Equatable {
    case none
    case communityOwner
    case communityAdmin
    case communityModerator
}

enum CloudOrganizationModerationStatus: String, Codable, Equatable {
    case pendingReview
    case approved
    case needsRevision
    case rejected
}

struct OrganizationRoleChangeFunctionRequest: Codable, Equatable {
    let organizationId: String
    let targetUserId: String
    let reason: String?

    init(organizationId: String, targetUserId: String, reason: String? = nil) {
        self.organizationId = organizationId
        self.targetUserId = targetUserId
        self.reason = reason
    }
}

struct OrganizationRoleChangeFunctionResponse: Codable, Equatable {
    let organizationId: String
    let targetUserId: String
    let previousRole: CloudOrganizationRole
    let newRole: CloudOrganizationRole
    let updatedAt: String
}

struct OrganizationOwnershipTransferFunctionResponse: Codable, Equatable {
    let organizationId: String
    let previousOwnerId: String?
    let newOwnerId: String
    let updatedAt: String
}

enum CloudPlatformGlobalRole: String, Codable, Equatable {
    case owner
    case admin
    case moderator
    case user
}

struct PlatformRoleChangeFunctionRequest: Codable, Equatable {
    let targetUserId: String
    let reason: String?

    init(targetUserId: String, reason: String? = nil) {
        self.targetUserId = targetUserId
        self.reason = reason
    }
}

struct PlatformRoleChangeFunctionResponse: Codable, Equatable {
    let targetUserId: String
    let previousGlobalRole: CloudPlatformGlobalRole
    let newGlobalRole: CloudPlatformGlobalRole
    let previousCanManageGuide: Bool
    let newCanManageGuide: Bool
    let updatedAt: String
}

enum CloudAccountStatus: String, Codable, Equatable {
    case active
    case warned
    case suspendedUntil
    case bannedPermanent
    case deactivated
}

struct AccountStatusChangeFunctionRequest: Codable, Equatable {
    let targetUserId: String
    let until: String?
    let reason: String?

    init(targetUserId: String, until: String? = nil, reason: String? = nil) {
        self.targetUserId = targetUserId
        self.until = until
        self.reason = reason
    }
}

struct AccountStatusChangeFunctionResponse: Codable, Equatable {
    let targetUserId: String
    let previousAccountStatus: CloudAccountStatus
    let newAccountStatus: CloudAccountStatus
    let previousBlockState: CloudAccountStatus
    let newBlockState: CloudAccountStatus
    let warningCount: Int
    let banExpiresAt: String?
    let updatedAt: String
}

struct LegalAcceptanceFunctionRequest: Codable, Equatable {
    let documentType: LegalDocumentType
    let version: String
    let appVersion: String?
    let locale: String?
    let acceptedFromPlatform: String
}

struct LegalAcceptanceFunctionResponse: Codable, Equatable {
    let documentType: LegalDocumentType
    let version: String
    let acceptedAt: String
}

struct OrganizationReviewFunctionRequest: Codable, Equatable {
    let organizationId: String
    let message: String?
    let reason: String?

    init(organizationId: String, message: String? = nil, reason: String? = nil) {
        self.organizationId = organizationId
        self.message = message
        self.reason = reason
    }
}

struct OrganizationReviewFunctionResponse: Codable, Equatable {
    let organizationId: String
    let moderationStatus: CloudOrganizationModerationStatus
    let notificationId: String
    let updatedAt: String
}

enum CloudGuideArticleStatus: String, Codable, Equatable {
    case draft
    case review
    case approved
    case published
    case archived
}

enum CloudGuideModerationStatus: String, Codable, Equatable {
    case draft
    case pendingReview
    case approved
    case archived
}

struct GuideWorkflowFunctionRequest: Codable, Equatable {
    let articleId: String
}

struct GuideWorkflowFunctionResponse: Codable, Equatable {
    let articleId: String
    let moderationStatus: CloudGuideModerationStatus
    let status: CloudGuideArticleStatus
    let updatedAt: String
}

final class CloudFunctionsClient {
    static let shared = CloudFunctionsClient()

    private let functions: Functions

    init(functions: Functions = Functions.functions(region: "europe-west3")) {
        self.functions = functions
    }

    func assignOrganizationAdmin(
        _ request: OrganizationRoleChangeFunctionRequest
    ) async throws -> OrganizationRoleChangeFunctionResponse {
        try await call(.assignOrganizationAdmin, request: request)
    }

    func removeOrganizationAdmin(
        _ request: OrganizationRoleChangeFunctionRequest
    ) async throws -> OrganizationRoleChangeFunctionResponse {
        try await call(.removeOrganizationAdmin, request: request)
    }

    func assignOrganizationModerator(
        _ request: OrganizationRoleChangeFunctionRequest
    ) async throws -> OrganizationRoleChangeFunctionResponse {
        try await call(.assignOrganizationModerator, request: request)
    }

    func removeOrganizationModerator(
        _ request: OrganizationRoleChangeFunctionRequest
    ) async throws -> OrganizationRoleChangeFunctionResponse {
        try await call(.removeOrganizationModerator, request: request)
    }

    func transferOrganizationOwnership(
        _ request: OrganizationRoleChangeFunctionRequest
    ) async throws -> OrganizationOwnershipTransferFunctionResponse {
        try await call(.transferOrganizationOwnership, request: request)
    }

    func assignAppAdmin(userId: String, reason: String? = nil) async throws -> PlatformRoleChangeFunctionResponse {
        try await call(
            .assignAppAdmin,
            request: platformRoleChangeRequest(userId: userId, reason: reason)
        )
    }

    func removeAppAdmin(userId: String, reason: String? = nil) async throws -> PlatformRoleChangeFunctionResponse {
        try await call(
            .removeAppAdmin,
            request: platformRoleChangeRequest(userId: userId, reason: reason)
        )
    }

    func assignAppModerator(userId: String, reason: String? = nil) async throws -> PlatformRoleChangeFunctionResponse {
        try await call(
            .assignAppModerator,
            request: platformRoleChangeRequest(userId: userId, reason: reason)
        )
    }

    func removeAppModerator(userId: String, reason: String? = nil) async throws -> PlatformRoleChangeFunctionResponse {
        try await call(
            .removeAppModerator,
            request: platformRoleChangeRequest(userId: userId, reason: reason)
        )
    }

    func assignGuideEditor(userId: String, reason: String? = nil) async throws -> PlatformRoleChangeFunctionResponse {
        try await call(
            .assignGuideEditor,
            request: platformRoleChangeRequest(userId: userId, reason: reason)
        )
    }

    func removeGuideEditor(userId: String, reason: String? = nil) async throws -> PlatformRoleChangeFunctionResponse {
        try await call(
            .removeGuideEditor,
            request: platformRoleChangeRequest(userId: userId, reason: reason)
        )
    }

    func warnUser(userId: String, reason: String? = nil) async throws -> AccountStatusChangeFunctionResponse {
        try await call(
            .warnUser,
            request: accountStatusChangeRequest(userId: userId, reason: reason)
        )
    }

    func suspendUser(userId: String, until: Date, reason: String? = nil) async throws -> AccountStatusChangeFunctionResponse {
        try await call(
            .suspendUser,
            request: accountStatusChangeRequest(userId: userId, until: until, reason: reason)
        )
    }

    func banUser(userId: String, reason: String? = nil) async throws -> AccountStatusChangeFunctionResponse {
        try await call(
            .banUser,
            request: accountStatusChangeRequest(userId: userId, reason: reason)
        )
    }

    func deactivateUser(userId: String, reason: String? = nil) async throws -> AccountStatusChangeFunctionResponse {
        try await call(
            .deactivateUser,
            request: accountStatusChangeRequest(userId: userId, reason: reason)
        )
    }

    func restoreUser(userId: String, reason: String? = nil) async throws -> AccountStatusChangeFunctionResponse {
        try await call(
            .restoreUser,
            request: accountStatusChangeRequest(userId: userId, reason: reason)
        )
    }

    func acceptLegalDocument(
        type: LegalDocumentType,
        version: String,
        appVersion: String?,
        locale: String?,
        acceptedFromPlatform: String = "ios"
    ) async throws -> LegalAcceptanceFunctionResponse {
        let trimmedVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await call(
            .acceptLegalDocument,
            request: LegalAcceptanceFunctionRequest(
                documentType: type,
                version: trimmedVersion,
                appVersion: appVersion?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                locale: locale?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                acceptedFromPlatform: acceptedFromPlatform
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty ?? "ios"
            )
        )
    }

    func approveOrganization(
        _ request: OrganizationReviewFunctionRequest
    ) async throws -> OrganizationReviewFunctionResponse {
        try await call(.approveOrganization, request: request)
    }

    func rejectOrganization(
        _ request: OrganizationReviewFunctionRequest
    ) async throws -> OrganizationReviewFunctionResponse {
        try await call(.rejectOrganization, request: request)
    }

    func requestOrganizationRevision(
        _ request: OrganizationReviewFunctionRequest
    ) async throws -> OrganizationReviewFunctionResponse {
        try await call(.requestOrganizationRevision, request: request)
    }

    func submitGuideArticleForReview(
        _ request: GuideWorkflowFunctionRequest
    ) async throws -> GuideWorkflowFunctionResponse {
        try await call(.submitGuideArticleForReview, request: request)
    }

    func approveGuideArticle(
        _ request: GuideWorkflowFunctionRequest
    ) async throws -> GuideWorkflowFunctionResponse {
        try await call(.approveGuideArticle, request: request)
    }

    func publishGuideArticle(
        _ request: GuideWorkflowFunctionRequest
    ) async throws -> GuideWorkflowFunctionResponse {
        try await call(.publishGuideArticle, request: request)
    }

    func archiveGuideArticle(
        _ request: GuideWorkflowFunctionRequest
    ) async throws -> GuideWorkflowFunctionResponse {
        try await call(.archiveGuideArticle, request: request)
    }

    private func call<Request: Encodable, Response: Decodable>(
        _ functionName: CloudFunctionName,
        request: Request
    ) async throws -> Response {
        let callable: Callable<Request, Response> = functions.httpsCallable(functionName.rawValue)
        return try await callable.call(request)
    }

    private func platformRoleChangeRequest(
        userId: String,
        reason: String?
    ) -> PlatformRoleChangeFunctionRequest {
        let trimmedReason = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        return PlatformRoleChangeFunctionRequest(
            targetUserId: userId,
            reason: trimmedReason?.isEmpty == false ? trimmedReason : nil
        )
    }

    private func accountStatusChangeRequest(
        userId: String,
        until: Date? = nil,
        reason: String?
    ) -> AccountStatusChangeFunctionRequest {
        let trimmedReason = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        return AccountStatusChangeFunctionRequest(
            targetUserId: userId,
            until: until.map(Self.cloudFunctionDateFormatter.string(from:)),
            reason: trimmedReason?.isEmpty == false ? trimmedReason : nil
        )
    }

    private static let cloudFunctionDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
