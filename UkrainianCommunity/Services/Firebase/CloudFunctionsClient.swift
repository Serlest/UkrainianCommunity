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

    private func call<Request: Encodable, Response: Decodable>(
        _ functionName: CloudFunctionName,
        request: Request
    ) async throws -> Response {
        let callable: Callable<Request, Response> = functions.httpsCallable(functionName.rawValue)
        do {
            let response = try await callable.call(request)
            await logSecuritySuccessIfNeeded(functionName, request: request, response: response)
            return response
        } catch {
            await SystemTechnicalErrorLoggingService.shared.logFailure(
                error,
                context: SystemTechnicalErrorContext(
                    moduleName: "CloudFunctions",
                    operationName: functionName.rawValue,
                    targetType: targetType(for: functionName),
                    metadata: [
                        "functionName": functionName.rawValue,
                        "callable": functionName.rawValue
                    ]
                )
            )
            await logSecurityFailureIfNeeded(functionName, request: request, error: error)
            throw error
        }
    }

    private func logSecuritySuccessIfNeeded<Request, Response>(
        _ functionName: CloudFunctionName,
        request: Request,
        response: Response
    ) async {
        guard let context = securitySuccessContext(functionName, request: request, response: response) else { return }
        await SystemSecurityLoggingService.shared.log(context)
    }

    private func logSecurityFailureIfNeeded<Request>(
        _ functionName: CloudFunctionName,
        request: Request,
        error: Error
    ) async {
        guard isSecuritySensitive(functionName),
              isPermissionFailure(error),
              let context = securityFailureContext(functionName, request: request, error: error) else { return }
        await SystemSecurityLoggingService.shared.log(context)
    }

    private func targetType(for functionName: CloudFunctionName) -> SystemLogTargetType {
        switch functionName {
        case .assignOrganizationAdmin,
             .removeOrganizationAdmin,
             .assignOrganizationModerator,
             .removeOrganizationModerator,
             .transferOrganizationOwnership,
             .approveOrganization,
             .rejectOrganization,
             .requestOrganizationRevision:
            return .organization
        case .assignAppAdmin,
             .removeAppAdmin,
             .assignAppModerator,
             .removeAppModerator,
             .assignGuideEditor,
             .removeGuideEditor,
             .warnUser,
             .suspendUser,
             .banUser,
             .deactivateUser,
             .restoreUser:
            return .userProfile
        case .acceptLegalDocument:
            return .legalDocument
        }
    }

    private func isSecuritySensitive(_ functionName: CloudFunctionName) -> Bool {
        switch functionName {
        case .assignOrganizationAdmin,
             .removeOrganizationAdmin,
             .assignOrganizationModerator,
             .removeOrganizationModerator,
             .transferOrganizationOwnership,
             .assignAppAdmin,
             .removeAppAdmin,
             .assignAppModerator,
             .removeAppModerator,
             .assignGuideEditor,
             .removeGuideEditor,
             .warnUser,
             .suspendUser,
             .banUser,
             .deactivateUser,
             .restoreUser:
            return true
        case .approveOrganization,
             .rejectOrganization,
             .requestOrganizationRevision,
             .acceptLegalDocument:
            return false
        }
    }

    private func isPermissionFailure(_ error: Error) -> Bool {
        let code = FunctionsErrorCode(rawValue: (error as NSError).code)
        return code == .permissionDenied || code == .unauthenticated
    }

    private func securitySuccessContext<Request, Response>(
        _ functionName: CloudFunctionName,
        request: Request,
        response: Response
    ) -> SystemSecurityLogContext? {
        switch functionName {
        case .assignOrganizationAdmin,
             .removeOrganizationAdmin,
             .assignOrganizationModerator,
             .removeOrganizationModerator:
            guard let request = request as? OrganizationRoleChangeFunctionRequest,
                  let response = response as? OrganizationRoleChangeFunctionResponse else { return nil }
            return organizationRoleSecurityContext(functionName, request: request, response: response)
        case .transferOrganizationOwnership:
            guard let request = request as? OrganizationRoleChangeFunctionRequest,
                  let response = response as? OrganizationOwnershipTransferFunctionResponse else { return nil }
            return organizationOwnershipSecurityContext(functionName, request: request, response: response)
        case .assignAppAdmin,
             .removeAppAdmin,
             .assignAppModerator,
             .removeAppModerator,
             .assignGuideEditor,
             .removeGuideEditor:
            guard let response = response as? PlatformRoleChangeFunctionResponse else { return nil }
            return platformRoleSecurityContext(functionName, response: response)
        case .warnUser,
             .suspendUser,
             .banUser,
             .deactivateUser,
             .restoreUser:
            guard let response = response as? AccountStatusChangeFunctionResponse else { return nil }
            return accountStatusSecurityContext(functionName, response: response)
        case .approveOrganization,
             .rejectOrganization,
             .requestOrganizationRevision,
             .acceptLegalDocument:
            return nil
        }
    }

    private func securityFailureContext<Request>(
        _ functionName: CloudFunctionName,
        request: Request,
        error: Error
    ) -> SystemSecurityLogContext? {
        guard isSecuritySensitive(functionName) else { return nil }
        let nsError = error as NSError
        let code = FunctionsErrorCode(rawValue: nsError.code)
        let metadata = safeSecurityMetadata(functionName: functionName, request: request)
            .merging(["errorCode": "cloudFunctions.\(code?.rawValue ?? nsError.code)"]) { current, _ in current }

        return SystemSecurityLogContext(
            moduleName: "Security",
            operationName: functionName.rawValue,
            eventType: .permissionDenied,
            severity: code == .unauthenticated ? .warning : .error,
            targetType: targetType(for: functionName),
            targetId: securityTargetId(functionName: functionName, request: request),
            outcome: .blocked,
            summary: "Доступ до захищеної дії відхилено",
            metadata: metadata
        )
    }

    private func organizationRoleSecurityContext(
        _ functionName: CloudFunctionName,
        request: OrganizationRoleChangeFunctionRequest,
        response: OrganizationRoleChangeFunctionResponse
    ) -> SystemSecurityLogContext {
        let isRemoval = response.newRole == .none
        return SystemSecurityLogContext(
            moduleName: "Security",
            operationName: functionName.rawValue,
            eventType: isRemoval ? .roleRemoved : .roleAssigned,
            severity: .notice,
            targetType: .organization,
            targetId: response.organizationId,
            outcome: .success,
            summary: isRemoval ? "Роль в організації знято" : "Роль в організації призначено",
            metadata: [
                "functionName": functionName.rawValue,
                "targetUserId": response.targetUserId,
                "previousRole": response.previousRole.rawValue,
                "newRole": response.newRole.rawValue,
                "organizationId": request.organizationId
            ]
        )
    }

    private func organizationOwnershipSecurityContext(
        _ functionName: CloudFunctionName,
        request: OrganizationRoleChangeFunctionRequest,
        response: OrganizationOwnershipTransferFunctionResponse
    ) -> SystemSecurityLogContext {
        var metadata = [
            "functionName": functionName.rawValue,
            "targetUserId": request.targetUserId,
            "newOwnerId": response.newOwnerId,
            "organizationId": response.organizationId
        ]
        if let previousOwnerId = response.previousOwnerId {
            metadata["previousOwnerId"] = previousOwnerId
        }

        return SystemSecurityLogContext(
            moduleName: "Security",
            operationName: functionName.rawValue,
            eventType: .roleAssigned,
            severity: .warning,
            targetType: .organization,
            targetId: response.organizationId,
            outcome: .success,
            summary: "Власника організації змінено",
            metadata: metadata
        )
    }

    private func platformRoleSecurityContext(
        _ functionName: CloudFunctionName,
        response: PlatformRoleChangeFunctionResponse
    ) -> SystemSecurityLogContext {
        let isRemoval = functionName == .removeAppAdmin
            || functionName == .removeAppModerator
            || functionName == .removeGuideEditor
        return SystemSecurityLogContext(
            moduleName: "Security",
            operationName: functionName.rawValue,
            eventType: isRemoval ? .roleRemoved : .roleAssigned,
            severity: .notice,
            targetType: .userProfile,
            targetId: response.targetUserId,
            outcome: .success,
            summary: isRemoval ? "Платформну роль знято" : "Платформну роль призначено",
            metadata: [
                "functionName": functionName.rawValue,
                "previousGlobalRole": response.previousGlobalRole.rawValue,
                "newGlobalRole": response.newGlobalRole.rawValue,
                "previousCanManageGuide": String(response.previousCanManageGuide),
                "newCanManageGuide": String(response.newCanManageGuide)
            ]
        )
    }

    private func accountStatusSecurityContext(
        _ functionName: CloudFunctionName,
        response: AccountStatusChangeFunctionResponse
    ) -> SystemSecurityLogContext {
        let isRestored = response.newAccountStatus == .active
        let isWarning = response.newAccountStatus == .warned
        return SystemSecurityLogContext(
            moduleName: "Account",
            operationName: functionName.rawValue,
            eventType: isWarning ? .userWarned : (isRestored ? .accountUnblocked : .accountBlocked),
            severity: isRestored ? .notice : .warning,
            targetType: .userProfile,
            targetId: response.targetUserId,
            outcome: .success,
            summary: accountStatusSummary(response.newAccountStatus),
            metadata: [
                "functionName": functionName.rawValue,
                "previousAccountStatus": response.previousAccountStatus.rawValue,
                "newAccountStatus": response.newAccountStatus.rawValue,
                "previousBlockState": response.previousBlockState.rawValue,
                "newBlockState": response.newBlockState.rawValue,
                "warningCount": String(response.warningCount),
                "banExpiresAt": response.banExpiresAt ?? "none"
            ]
        )
    }

    private func accountStatusSummary(_ status: CloudAccountStatus) -> String {
        switch status {
        case .active:
            return "Доступ до облікового запису відновлено"
        case .warned:
            return "Користувача попереджено"
        case .suspendedUntil:
            return "Обліковий запис тимчасово заблоковано"
        case .bannedPermanent:
            return "Обліковий запис заблоковано"
        case .deactivated:
            return "Обліковий запис деактивовано"
        }
    }

    private func safeSecurityMetadata<Request>(
        functionName: CloudFunctionName,
        request: Request
    ) -> [String: String] {
        var metadata = [
            "functionName": functionName.rawValue
        ]

        if let request = request as? OrganizationRoleChangeFunctionRequest {
            metadata["organizationId"] = request.organizationId
            metadata["targetUserId"] = request.targetUserId
        } else if let request = request as? PlatformRoleChangeFunctionRequest {
            metadata["targetUserId"] = request.targetUserId
        } else if let request = request as? AccountStatusChangeFunctionRequest {
            metadata["targetUserId"] = request.targetUserId
            metadata["hasUntil"] = String(request.until != nil)
        }

        return metadata
    }

    private func securityTargetId<Request>(
        functionName: CloudFunctionName,
        request: Request
    ) -> String? {
        if let request = request as? OrganizationRoleChangeFunctionRequest {
            return request.organizationId
        }
        if let request = request as? PlatformRoleChangeFunctionRequest {
            return request.targetUserId
        }
        if let request = request as? AccountStatusChangeFunctionRequest {
            return request.targetUserId
        }
        return nil
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
