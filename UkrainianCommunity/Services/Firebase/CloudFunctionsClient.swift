import FirebaseFunctions
import Foundation

enum CloudFunctionName: String, CaseIterable {
    case assignOrganizationAdmin
    case removeOrganizationAdmin
    case assignOrganizationModerator
    case removeOrganizationModerator
    case approveOrganization
    case rejectOrganization
    case requestOrganizationRevision
    case submitGuideArticleForReview
    case approveGuideArticle
    case publishGuideArticle
    case archiveGuideArticle
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
}
