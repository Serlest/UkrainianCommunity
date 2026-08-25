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
    case cancelEvent
    case registerForEvent
    case unregisterFromEvent
    case deleteNews
    case deleteOrganization
    case assignAppAdmin
    case removeAppAdmin
    case warnUser
    case suspendUser
    case banUser
    case deactivateUser
    case restoreUser
    case searchManagedUsers
    case getManagedUserSecurityMetadata
    case acceptLegalDocument
    case deleteOwnAccount
    case deleteFeedback
    case clearFeedbackInbox
    case saveFeaturedBanner
    case setFeaturedBannerActive
    case deleteFeaturedBanner
    case submitContentReport
    case setUserBlocked
    case createOrganizationPhotoMetadata
    case deleteOrganizationPhotoMetadata
    case deleteNotificationPushRegistration
    case sendTestPushNotification
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

struct ManagedUserSearchFunctionRequest: Codable, Equatable {
    let query: String
    let limit: Int
}

struct ManagedUserSearchFunctionResponse: Codable, Equatable {
    let userIds: [String]
    let totalMatches: Int
}

struct ManagedUserSecurityMetadataFunctionRequest: Codable, Equatable {
    let targetUserId: String
}

struct ManagedUserSecurityMetadataFunctionResponse: Codable, Equatable {
    let targetUserId: String
    let emailVerified: Bool
    let authDisabled: Bool
    let creationTime: String?
    let lastSignInTime: String?
    let providerIds: [String]
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

struct EventCancellationFunctionRequest: Codable, Equatable {
    let eventId: String
    let reason: String?

    init(eventId: String, reason: String? = nil) {
        self.eventId = eventId
        self.reason = reason
    }
}

struct EventCancellationFunctionResponse: Codable, Equatable {
    let eventId: String
    let status: String
    let recipientCount: Int
    let notificationCount: Int
    let pushRecipientCount: Int
    let cancelledAt: String
}

private struct EventRegistrationFunctionRequest: Codable, Equatable {
    let eventId: String
    let actionProof: AnalyticsActionCapture?
}

private struct EventRegistrationFunctionResponse: Codable, Equatable {
    let eventId: String
    let registrationState: EventRegistrationState
    let registeredCount: Int
    let didChange: Bool
}

struct NewsDeletionFunctionRequest: Codable, Equatable {
    let newsId: String
}

struct OrganizationDeletionFunctionRequest: Codable, Equatable {
    let organizationId: String
}

struct OrganizationPhotoCreateFunctionRequest: Codable, Equatable {
    let organizationId: String
    let photoId: String
    let imageURL: String
    let caption: String?
}

struct OrganizationPhotoDeleteFunctionRequest: Codable, Equatable {
    let organizationId: String
    let photoId: String
}

struct OrganizationPhotoMutationFunctionResponse: Codable, Equatable {
    let organizationId: String
    let photoId: String
    let photoCount: Int
    let didChange: Bool
    let uploadedBy: String?
    let createdAt: String?
}

struct ContentDeletionFunctionResponse: Codable, Equatable {
    let status: String
    let deletedAt: String
}

struct AccountDeletionFunctionRequest: Codable, Equatable {}

struct ClearMyFeedbackFunctionRequest: Codable, Equatable {}

struct ClearMyFeedbackFunctionResponse: Codable, Equatable {
    let deletedCount: Int
}

struct DeleteFeedbackFunctionRequest: Codable, Equatable {
    let feedbackId: String
}

struct AccountDeletionFunctionResponse: Codable, Equatable {
    let status: String
    let completedAt: String
}

nonisolated struct PushRegistrationDeletionFunctionRequest: Codable, Equatable {
    let userId: String
    let identifier: String
    let registrationType: String
}

nonisolated struct PushRegistrationDeletionFunctionResponse: Codable, Equatable {
    let deletedRegistrationCount: Int
}

struct TestPushNotificationFunctionRequest: Codable, Equatable {}

struct TestPushNotificationFunctionResponse: Codable, Equatable {
    let targetCount: Int
    let successCount: Int
    let failureCount: Int
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

    func searchManagedUsers(query: String, limit: Int = 100) async throws -> ManagedUserSearchFunctionResponse {
        try await call(
            .searchManagedUsers,
            request: ManagedUserSearchFunctionRequest(query: query, limit: limit)
        )
    }

    func getManagedUserSecurityMetadata(
        userId: String
    ) async throws -> ManagedUserSecurityMetadataFunctionResponse {
        try await call(
            .getManagedUserSecurityMetadata,
            request: ManagedUserSecurityMetadataFunctionRequest(targetUserId: userId)
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

    func cancelEvent(
        _ request: EventCancellationFunctionRequest
    ) async throws -> EventCancellationFunctionResponse {
        try await call(.cancelEvent, request: request)
    }

    func registerForEvent(id: String, actionCapture: AnalyticsActionCapture?) async throws -> EventRegistrationMutationResult {
        try await eventRegistrationMutation(.registerForEvent, eventID: id, actionCapture: actionCapture)
    }

    func cancelEventRegistration(id: String) async throws -> EventRegistrationMutationResult {
        try await eventRegistrationMutation(.unregisterFromEvent, eventID: id, actionCapture: nil)
    }

    func deleteNews(id: String) async throws -> ContentDeletionFunctionResponse {
        try await call(.deleteNews, request: NewsDeletionFunctionRequest(newsId: id))
    }

    func deleteOrganization(id: String) async throws -> ContentDeletionFunctionResponse {
        try await call(
            .deleteOrganization,
            request: OrganizationDeletionFunctionRequest(organizationId: id)
        )
    }

    func createOrganizationPhotoMetadata(
        organizationId: String,
        photoId: String,
        imageURL: String,
        caption: String?
    ) async throws -> OrganizationPhotoMutationFunctionResponse {
        try await call(
            .createOrganizationPhotoMetadata,
            request: OrganizationPhotoCreateFunctionRequest(
                organizationId: organizationId,
                photoId: photoId,
                imageURL: imageURL,
                caption: caption
            )
        )
    }

    func deleteOrganizationPhotoMetadata(
        organizationId: String,
        photoId: String
    ) async throws -> OrganizationPhotoMutationFunctionResponse {
        try await call(
            .deleteOrganizationPhotoMetadata,
            request: OrganizationPhotoDeleteFunctionRequest(
                organizationId: organizationId,
                photoId: photoId
            )
        )
    }

    func deleteOwnAccount() async throws -> AccountDeletionFunctionResponse {
        try await call(.deleteOwnAccount, request: AccountDeletionFunctionRequest())
    }

    func deleteFeedback(id: String) async throws -> ClearMyFeedbackFunctionResponse {
        try await call(.deleteFeedback, request: DeleteFeedbackFunctionRequest(feedbackId: id))
    }

    func clearFeedbackInbox() async throws -> ClearMyFeedbackFunctionResponse {
        try await call(.clearFeedbackInbox, request: ClearMyFeedbackFunctionRequest())
    }

    func deleteNotificationPushRegistration(
        _ request: PushRegistrationDeletionFunctionRequest
    ) async throws -> PushRegistrationDeletionFunctionResponse {
        try await call(.deleteNotificationPushRegistration, request: request)
    }

    func sendTestPushNotification() async throws -> TestPushNotificationFunctionResponse {
        try await call(.sendTestPushNotification, request: TestPushNotificationFunctionRequest())
    }

    private func eventRegistrationMutation(
        _ functionName: CloudFunctionName,
        eventID: String,
        actionCapture: AnalyticsActionCapture?
    ) async throws -> EventRegistrationMutationResult {
        do {
            let response: EventRegistrationFunctionResponse = try await call(
                functionName,
                request: EventRegistrationFunctionRequest(
                    eventId: eventID,
                    actionProof: actionCapture
                )
            )
            guard response.eventId == eventID, response.registeredCount >= 0 else {
                throw EventRegistrationMutationError.unavailable
            }
            return EventRegistrationMutationResult(
                eventID: response.eventId,
                registrationState: response.registrationState,
                registeredCount: response.registeredCount,
                didChange: response.didChange
            )
        } catch let mutationError as EventRegistrationMutationError {
            throw mutationError
        } catch {
            throw EventRegistrationFunctionErrorMapper.map(error)
        }
    }

    func call<Request: Encodable, Response: Decodable>(
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
                    targetId: securityTargetId(functionName: functionName, request: request),
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
             .requestOrganizationRevision,
             .cancelEvent,
             .registerForEvent,
             .unregisterFromEvent,
             .deleteOrganization,
             .createOrganizationPhotoMetadata,
             .deleteOrganizationPhotoMetadata:
            return functionName == .registerForEvent || functionName == .unregisterFromEvent
            ? .event
            : .organization
        case .deleteNews:
            return .newsPost
        case .assignAppAdmin,
             .removeAppAdmin,
             .warnUser,
             .suspendUser,
             .banUser,
             .deactivateUser,
             .restoreUser,
             .searchManagedUsers,
             .getManagedUserSecurityMetadata,
             .deleteOwnAccount,
             .deleteFeedback,
             .clearFeedbackInbox,
             .deleteNotificationPushRegistration,
             .sendTestPushNotification:
            return .userProfile
        case .acceptLegalDocument:
            return .legalDocument
        case .saveFeaturedBanner,
             .setFeaturedBannerActive,
             .deleteFeaturedBanner:
            return .systemConfiguration
        case .submitContentReport:
            return .report
        case .setUserBlocked:
            return .userProfile
        }
    }

    private func isSecuritySensitive(_ functionName: CloudFunctionName) -> Bool {
        switch functionName {
        case .assignOrganizationAdmin,
             .removeOrganizationAdmin,
             .assignOrganizationModerator,
             .removeOrganizationModerator,
             .transferOrganizationOwnership,
             .cancelEvent,
             .deleteNews,
             .deleteOrganization,
             .assignAppAdmin,
             .removeAppAdmin,
             .warnUser,
             .suspendUser,
             .banUser,
             .deactivateUser,
             .restoreUser,
             .saveFeaturedBanner,
             .setFeaturedBannerActive,
             .deleteFeaturedBanner,
             .createOrganizationPhotoMetadata,
             .deleteOrganizationPhotoMetadata:
            return true
        case .approveOrganization,
             .rejectOrganization,
             .requestOrganizationRevision,
             .acceptLegalDocument,
             .deleteOwnAccount,
             .deleteFeedback,
             .clearFeedbackInbox,
             .registerForEvent,
             .unregisterFromEvent,
             .submitContentReport,
             .setUserBlocked,
             .searchManagedUsers,
             .getManagedUserSecurityMetadata,
             .deleteNotificationPushRegistration,
             .sendTestPushNotification:
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
             .removeAppAdmin:
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
             .cancelEvent,
             .registerForEvent,
             .unregisterFromEvent,
             .deleteNews,
             .deleteOrganization,
             .acceptLegalDocument,
             .deleteOwnAccount,
             .deleteFeedback,
             .clearFeedbackInbox,
             .saveFeaturedBanner,
             .setFeaturedBannerActive,
             .deleteFeaturedBanner,
             .submitContentReport,
             .setUserBlocked,
             .searchManagedUsers,
             .getManagedUserSecurityMetadata,
             .createOrganizationPhotoMetadata,
             .deleteOrganizationPhotoMetadata,
             .deleteNotificationPushRegistration,
             .sendTestPushNotification:
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
                "newGlobalRole": response.newGlobalRole.rawValue
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
        } else if let request = request as? ManagedUserSecurityMetadataFunctionRequest {
            metadata["targetUserId"] = request.targetUserId
        } else if let request = request as? FeaturedBannerSaveFunctionRequest {
            metadata["bannerId"] = request.banner.id
            metadata["mode"] = request.mode.rawValue
        } else if let request = request as? FeaturedBannerIDFunctionRequest {
            metadata["bannerId"] = request.id
        } else if let request = request as? FeaturedBannerActiveFunctionRequest {
            metadata["bannerId"] = request.id
            metadata["isActive"] = String(request.isActive)
        } else if let request = request as? NewsDeletionFunctionRequest {
            metadata["newsId"] = request.newsId
        } else if let request = request as? OrganizationDeletionFunctionRequest {
            metadata["organizationId"] = request.organizationId
        } else if let request = request as? OrganizationPhotoCreateFunctionRequest {
            metadata["organizationId"] = request.organizationId
            metadata["photoId"] = request.photoId
        } else if let request = request as? OrganizationPhotoDeleteFunctionRequest {
            metadata["organizationId"] = request.organizationId
            metadata["photoId"] = request.photoId
        } else if let request = request as? ContentReportFunctionRequest {
            metadata["reportTargetType"] = request.targetType
            metadata["reportTargetId"] = request.targetId
        } else if let request = request as? UserBlockFunctionRequest {
            metadata["targetUserId"] = request.targetUserId
            metadata["isBlocked"] = String(request.isBlocked)
        } else if let request = request as? EventRegistrationFunctionRequest {
            metadata["eventId"] = request.eventId
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
        if let request = request as? OrganizationPhotoCreateFunctionRequest {
            return request.organizationId
        }
        if let request = request as? OrganizationPhotoDeleteFunctionRequest {
            return request.organizationId
        }
        if let request = request as? PlatformRoleChangeFunctionRequest {
            return request.targetUserId
        }
        if let request = request as? AccountStatusChangeFunctionRequest {
            return request.targetUserId
        }
        if let request = request as? ManagedUserSecurityMetadataFunctionRequest {
            return request.targetUserId
        }
        if let request = request as? FeaturedBannerSaveFunctionRequest {
            return request.banner.id
        }
        if let request = request as? FeaturedBannerIDFunctionRequest {
            return request.id
        }
        if let request = request as? FeaturedBannerActiveFunctionRequest {
            return request.id
        }
        if let request = request as? NewsDeletionFunctionRequest {
            return request.newsId
        }
        if let request = request as? OrganizationDeletionFunctionRequest {
            return request.organizationId
        }
        if let request = request as? ContentReportFunctionRequest {
            return request.targetId
        }
        if let request = request as? UserBlockFunctionRequest {
            return request.targetUserId
        }
        if let request = request as? EventRegistrationFunctionRequest {
            return request.eventId
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

extension CloudFunctionsClient: EventRegistrationMutating {}

enum EventRegistrationFunctionErrorMapper {
    static func map(_ error: Error) -> EventRegistrationMutationError {
        let nsError = error as NSError
        guard nsError.domain == FunctionsErrorDomain,
              let code = FunctionsErrorCode(rawValue: nsError.code) else {
            return nsError.domain == NSURLErrorDomain ? .network : .unavailable
        }

        let reason = serverReason(from: nsError)
        switch (code, reason) {
        case (.resourceExhausted, "event-full"):
            return .full
        case (.failedPrecondition, "registration-not-required"):
            return .registrationNotRequired
        case (.failedPrecondition, "event-cancelled"):
            return .eventCancelled
        case (.failedPrecondition, "event-past"):
            return .eventPast
        case (.permissionDenied, _), (.unauthenticated, _):
            return .permissionDenied
        case (.notFound, _):
            return .notFound
        case (.deadlineExceeded, _), (.unavailable, _), (.aborted, _), (.cancelled, _):
            return .network
        default:
            return .unavailable
        }
    }

    private static func serverReason(from error: NSError) -> String? {
        if let details = error.userInfo[FunctionsErrorDetailsKey] as? [String: Any] {
            return details["reason"] as? String
        }
        if let details = error.userInfo[FunctionsErrorDetailsKey] as? NSDictionary {
            return details["reason"] as? String
        }
        return nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
