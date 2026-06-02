import Combine
import Foundation

@MainActor
final class OrganizationTeamViewModel: ObservableObject {
    @Published private(set) var members: [OrganizationTeamMember] = []
    @Published private(set) var candidateMembers: [OrganizationTeamMember] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingCandidates = false
    @Published private(set) var updatingUserIDs = Set<String>()
    @Published var errorMessage: String?
    @Published var statusMessage: String?

    private let organizationRepository: OrganizationRepository
    private let roleManagementService: OrganizationRoleManagementService

    init(
        organizationRepository: OrganizationRepository? = nil,
        roleManagementService: OrganizationRoleManagementService? = nil
    ) {
        self.organizationRepository = organizationRepository ?? FirestoreOrganizationRepository()
        self.roleManagementService = roleManagementService ?? FirestoreOrganizationRoleManagementService()
    }

    func load(organization: Organization) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let subscriberIDs = try await fetchSubscriberIDs(organizationID: organization.id)
            let teamIDs = Self.teamIDs(for: organization)
            let profiles = try await organizationRepository.fetchPublicUserProfiles(
                userIDs: Array(Set(teamIDs + subscriberIDs))
            )
            members = Self.makeMembers(
                organization: organization,
                profiles: profiles,
                subscriberIDs: subscriberIDs
            )
            statusMessage = nil
        } catch {
            members = []
            errorMessage = AppStrings.Profile.organizationTeamLoadFailed
        }
    }

    private func fetchSubscriberIDs(organizationID: String) async throws -> [String] {
        var cursor: OrganizationSubscriberCursor?
        var userIDs: [String] = []

        repeat {
            let page = try await organizationRepository.fetchOrganizationSubscriberPage(
                organizationID: organizationID,
                limit: 100,
                after: cursor
            )
            userIDs.append(contentsOf: page.items.map(\.userID))
            cursor = page.nextCursor
        } while cursor != nil

        return Array(NSOrderedSet(array: userIDs)) as? [String] ?? userIDs
    }

    func loadCandidateUsers(excluding organization: Organization, allowsExistingTeamMembers: Bool = false) async {
        isLoadingCandidates = true
        defer { isLoadingCandidates = false }

        if members.isEmpty {
            await load(organization: organization)
        }

        let excludedIDs: Set<String>
        if allowsExistingTeamMembers {
            excludedIDs = Set([organization.ownerId].compactMap { $0 }.filter { !$0.isEmpty })
        } else {
            excludedIDs = Set(Self.teamIDs(for: organization))
        }

        candidateMembers = members
            .filter { !excludedIDs.contains($0.userID) }
            .filter { allowsExistingTeamMembers || $0.role == .member }
    }

    func apply(
        _ action: OrganizationTeamAction,
        organization: Organization,
        actor: AppUser
    ) async -> Bool {
        guard PermissionService.canManageOrganizationRoles(organization, user: actor) else {
            errorMessage = AppStrings.Profile.organizationTeamPermissionDenied
            return false
        }

        switch action {
        case let .assign(member, role):
            return await assign(role, to: member, organization: organization, actor: actor)
        case let .changeOwner(member):
            return await changeOwner(to: member, organization: organization, actor: actor)
        case let .remove(member):
            return await remove(member, organization: organization, actor: actor)
        }
    }

    private func assign(
        _ role: OrganizationTeamRole,
        to target: OrganizationTeamMember,
        organization: Organization,
        actor: AppUser
    ) async -> Bool {
        let canInitiateOwnershipTransfer = PermissionService.canInitiateOwnershipTransferWorkflow(user: actor)
        guard canInitiateOwnershipTransfer || role != .owner else {
            errorMessage = AppStrings.Profile.organizationTeamOwnerCanAssignOnlyAdminModerator
            return false
        }

        return await update(targetUserID: target.userID, organization: organization) {
            try await roleManagementService.updateRole(
                role: role.communityRole,
                organization: organization,
                targetUserID: target.userID,
                actor: actor,
                isRemoval: false,
                reason: "Organization management hub"
            )
        }
    }

    private func remove(
        _ member: OrganizationTeamMember,
        organization: Organization,
        actor: AppUser
    ) async -> Bool {
        let canInitiateOwnershipTransfer = PermissionService.canInitiateOwnershipTransferWorkflow(user: actor)
        guard canInitiateOwnershipTransfer || member.role != .owner else {
            errorMessage = AppStrings.Profile.organizationTeamOwnerCannotRemoveOwner
            return false
        }

        guard member.role != .owner else {
            errorMessage = AppStrings.Profile.organizationTeamCannotRemoveLastOwner
            return false
        }

        return await update(targetUserID: member.userID, organization: organization) {
            try await roleManagementService.updateRole(
                role: .member,
                organization: organization,
                targetUserID: member.userID,
                actor: actor,
                isRemoval: true,
                reason: "Organization management hub"
            )
        }
    }

    private func changeOwner(
        to target: OrganizationTeamMember,
        organization: Organization,
        actor: AppUser
    ) async -> Bool {
        guard PermissionService.canInitiateOwnershipTransferWorkflow(user: actor) else {
            errorMessage = AppStrings.Profile.organizationTeamOwnerChangePlatformOnly
            return false
        }

        guard !target.userID.isEmpty else {
            errorMessage = AppStrings.Profile.organizationTeamUserProfileMissing
            return false
        }

        return await update(targetUserID: target.userID, organization: organization) {
            try await roleManagementService.transferOwner(
                organization: organization,
                newOwnerID: target.userID,
                actor: actor
            )
        }
    }

    private func update(
        targetUserID: String,
        organization: Organization,
        operation: () async throws -> Void
    ) async -> Bool {
        guard !updatingUserIDs.contains(targetUserID) else { return false }
        updatingUserIDs.insert(targetUserID)
        errorMessage = nil
        statusMessage = nil
        defer { updatingUserIDs.remove(targetUserID) }

        do {
            try await operation()
            statusMessage = AppStrings.Profile.organizationTeamUpdated
            await load(organization: organization)
            return true
        } catch {
            errorMessage = AppStrings.Profile.organizationTeamSaveFailed
            return false
        }
    }

    private static func teamIDs(for organization: Organization) -> [String] {
        var orderedIDs: [String] = []
        if let ownerId = organization.ownerId, !ownerId.isEmpty {
            orderedIDs.append(ownerId)
        }
        orderedIDs.append(contentsOf: organization.adminIds)
        orderedIDs.append(contentsOf: organization.moderatorIds)
        return Array(NSOrderedSet(array: orderedIDs)) as? [String] ?? orderedIDs
    }

    private static func makeMembers(
        organization: Organization,
        profiles: [PublicUserProfile],
        subscriberIDs: [String]
    ) -> [OrganizationTeamMember] {
        let profilesByID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        var result: [OrganizationTeamMember] = []
        var renderedUserIDs = Set<String>()

        if let ownerId = organization.ownerId, !ownerId.isEmpty {
            result.append(OrganizationTeamMember(profile: profilesByID[ownerId], userID: ownerId, role: .owner))
            renderedUserIDs.insert(ownerId)
        }

        for userID in organization.adminIds where !renderedUserIDs.contains(userID) {
            result.append(OrganizationTeamMember(profile: profilesByID[userID], userID: userID, role: .admin))
            renderedUserIDs.insert(userID)
        }

        for userID in organization.moderatorIds where !renderedUserIDs.contains(userID) {
            result.append(OrganizationTeamMember(profile: profilesByID[userID], userID: userID, role: .moderator))
            renderedUserIDs.insert(userID)
        }

        for userID in subscriberIDs where !renderedUserIDs.contains(userID) {
            result.append(OrganizationTeamMember(profile: profilesByID[userID], userID: userID, role: .member))
            renderedUserIDs.insert(userID)
        }

        return result
    }
}
