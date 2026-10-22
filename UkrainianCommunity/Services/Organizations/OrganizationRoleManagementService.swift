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
    private var journal = OrganizationRoleRequestJournal()

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
        let request = operationRequest(organization: organization, target: targetUserID, actor: actor,
            action: isRemoval ? "remove" : role.rawValue, reason: trimmedReason?.isEmpty == false ? trimmedReason : nil)

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
        let request = operationRequest(organization: organization, target: newOwnerID, actor: actor, action: "transfer",
            reason: trimmedReason?.isEmpty == false ? trimmedReason : nil)

        _ = try await cloudFunctionsClient.transferOrganizationOwnership(request)
    }

    private func operationRequest(organization: Organization, target: String, actor: AppUser, action: String, reason: String?) -> OrganizationRoleChangeFunctionRequest {
        journal.request(organization: organization, target: target, actor: actor, action: action, reason: reason)
    }

    private static func role(for userID: String, in organization: Organization) -> CommunityRole? {
        if organization.ownerId == userID { return .communityOwner }
        if organization.adminIds.contains(userID) { return .communityAdmin }
        if organization.moderatorIds.contains(userID) { return .communityModerator }
        return nil
    }
}

struct OrganizationRoleRequestJournal {
    private var requests: [String: OrganizationRoleChangeFunctionRequest] = [:]
    mutating func request(organization: Organization, target: String, actor: AppUser, action: String, reason: String?) -> OrganizationRoleChangeFunctionRequest {
        let oldRole = organization.ownerId == target ? "communityOwner" : organization.adminIds.contains(target) ? "communityAdmin" : organization.moderatorIds.contains(target) ? "communityModerator" : "none"
        let key = [actor.id, organization.id, target, action, organization.accessRevision ?? "null", oldRole, reason ?? ""].joined(separator: "\u{0}")
        if let request = requests[key] { return request }
        if requests.count >= 100 { requests.removeAll() }
        let request = OrganizationRoleChangeFunctionRequest(organizationId: organization.id, targetUserId: target, reason: reason,
            operationId: UUID().uuidString, principalId: actor.id, expectedRevision: organization.accessRevision, expectedRole: oldRole)
        requests[key] = request
        return request
    }
}
