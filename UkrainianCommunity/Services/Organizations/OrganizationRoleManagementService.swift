import Foundation

protocol OrganizationRoleManagementService {
    func updateRole(
        role: CommunityRole,
        organization: Organization,
        targetUserID: String,
        actor: AppUser,
        isRemoval: Bool,
        reason: String?
    ) async throws

    func transferOwner(
        organization: Organization,
        newOwnerID: String,
        actor: AppUser,
        reason: String?
    ) async throws
}

extension OrganizationRoleManagementService {
    func transferOwner(
        organization: Organization,
        newOwnerID: String,
        actor: AppUser
    ) async throws {
        try await transferOwner(
            organization: organization,
            newOwnerID: newOwnerID,
            actor: actor,
            reason: nil
        )
    }
}

final class FirestoreOrganizationRoleManagementService: OrganizationRoleManagementService {
    private let cloudFunctionsClient: CloudFunctionsClient

    init(
        cloudFunctionsClient: CloudFunctionsClient = .shared
    ) {
        self.cloudFunctionsClient = cloudFunctionsClient
    }

    func updateRole(
        role: CommunityRole,
        organization: Organization,
        targetUserID: String,
        actor: AppUser,
        isRemoval: Bool,
        reason: String?
    ) async throws {
        let trimmedReason = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = OrganizationRoleChangeFunctionRequest(
            organizationId: organization.id,
            targetUserId: targetUserID,
            reason: trimmedReason?.isEmpty == false ? trimmedReason : nil
        )

        if isRemoval {
            switch Self.role(for: targetUserID, in: organization) {
            case .communityAdmin:
                _ = try await cloudFunctionsClient.removeOrganizationAdmin(request)
            case .communityModerator:
                _ = try await cloudFunctionsClient.removeOrganizationModerator(request)
            case .communityOwner:
                throw AppError.permissionDenied
            case .member, nil:
                return
            }
            return
        }

        switch role {
        case .communityAdmin:
            _ = try await cloudFunctionsClient.assignOrganizationAdmin(request)
        case .communityModerator:
            _ = try await cloudFunctionsClient.assignOrganizationModerator(request)
        case .communityOwner:
            try await transferOwner(
                organization: organization,
                newOwnerID: targetUserID,
                actor: actor,
                reason: reason
            )
        case .member:
            return
        }
    }

    func transferOwner(
        organization: Organization,
        newOwnerID: String,
        actor: AppUser,
        reason: String?
    ) async throws {
        guard PermissionService.canInitiateOwnershipTransferWorkflow(user: actor), !newOwnerID.isEmpty else {
            throw AppError.permissionDenied
        }

        let trimmedReason = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
        let request = OrganizationRoleChangeFunctionRequest(
            organizationId: organization.id,
            targetUserId: newOwnerID,
            reason: trimmedReason?.isEmpty == false ? trimmedReason : nil
        )

        _ = try await cloudFunctionsClient.transferOrganizationOwnership(request)
    }

    private static func role(for userID: String, in organization: Organization) -> CommunityRole? {
        if organization.ownerId == userID { return .communityOwner }
        if organization.adminIds.contains(userID) { return .communityAdmin }
        if organization.moderatorIds.contains(userID) { return .communityModerator }
        return nil
    }
}
