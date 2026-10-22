import Combine
import Foundation
import FirebaseFunctions

@MainActor
final class OrganizationTeamViewModel: ObservableObject {
    @Published private(set) var members: [OrganizationTeamMember] = []
    @Published private(set) var candidateMembers: [OrganizationTeamMember] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingCandidates = false
    @Published private(set) var updatingUserIDs = Set<String>()
    @Published var errorMessage: String?
    @Published private(set) var candidateErrorMessage: String?
    @Published var statusMessage: String?

    @Published private(set) var hasMoreCandidates = false
    private var candidateCursor: String?
    private var candidateGeneration = UUID()
    private var loadGeneration = UUID()
    private var generation = 0
    private let workspaceRead: (OrganizationWorkspaceRequest) async throws -> OrganizationWorkspaceResponse
    private let organizationRepository: OrganizationRepository
    private let roleManagementService: OrganizationRoleManagementService

    init(
        organizationRepository: OrganizationRepository? = nil,
        roleManagementService: OrganizationRoleManagementService? = nil,
        workspaceRead: ((OrganizationWorkspaceRequest) async throws -> OrganizationWorkspaceResponse)? = nil
    ) {
        if let organizationRepository { self.organizationRepository = organizationRepository }
        else if ProcessInfo.processInfo.arguments.contains("-ui-testing") { self.organizationRepository = MockOrganizationRepository() }
        else { self.organizationRepository = FirestoreOrganizationRepository() }
        self.roleManagementService = roleManagementService ?? FirestoreOrganizationRoleManagementService()
        self.workspaceRead = workspaceRead ?? { try await CloudFunctionsClient.shared.call(.manageOrganizationWorkspace, request: $0) }
    }

    func reset() {
        generation &+= 1; loadGeneration = UUID(); candidateGeneration = UUID(); candidateCursor = nil; hasMoreCandidates = false
        members = []; candidateMembers = []; updatingUserIDs = []
        isLoading = false; isLoadingCandidates = false
        errorMessage = nil; candidateErrorMessage = nil; statusMessage = nil
    }

    func load(organization: Organization, actor: AppUser?) async {
        let expected = generation
        loadGeneration = UUID(); let expectedLoad = loadGeneration
        guard PermissionService.canAccessManagedOrganization(organization, user: actor) else { reset(); return }
        isLoading = true
        errorMessage = nil
        defer { if generation == expected, loadGeneration == expectedLoad { isLoading = false } }

        do {
            let subscriberIDs: [String] = []
            let teamIDs = Self.teamIDs(for: organization)
            let profiles = try await organizationRepository.fetchPublicUserProfiles(
                userIDs: Array(Set(teamIDs + subscriberIDs))
            )
            guard generation == expected, loadGeneration == expectedLoad, !Task.isCancelled else { return }
            members = Self.makeMembers(
                organization: organization,
                profiles: profiles,
                subscriberIDs: subscriberIDs
            )
        } catch {
            guard generation == expected, loadGeneration == expectedLoad, !Task.isCancelled else { return }
            errorMessage = AppStrings.Profile.organizationTeamLoadFailed
        }
    }

    func loadCandidateUsers(excluding organization: Organization, actor: AppUser?, allowsExistingTeamMembers: Bool = false,
                            search: String = "", more: Bool = false) async {
        guard let actor, PermissionService.canManageOrganizationRoles(organization, user: actor) else {
            candidateMembers = []; candidateErrorMessage = AppStrings.Profile.organizationTeamPermissionDenied; return
        }
        if more { guard hasMoreCandidates, !isLoadingCandidates else { return } }
        else { candidateGeneration = UUID(); candidateCursor = nil; candidateMembers = []; hasMoreCandidates = false }
        let expected = generation, requestID = candidateGeneration
        isLoadingCandidates = true; candidateErrorMessage = nil
        defer { if generation == expected, candidateGeneration == requestID { isLoadingCandidates = false } }
        do {
            let fresh: [OrganizationTeamMember]; let cursor: String?
            if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
                let page = try await organizationRepository.fetchOrganizationSubscriberPage(organizationID: organization.id, limit: 30, after: nil)
                let profiles = try await organizationRepository.fetchPublicUserProfiles(userIDs: page.items.map(\.userID))
                let excluded = allowsExistingTeamMembers ? [organization.ownerId].compactMap { $0 } : Self.teamIDs(for: organization)
                fresh = profiles.filter { !excluded.contains($0.id) && LocalSearchMatcher.matches(query: search, values: [$0.displayName, $0.city]) }
                    .map { .init(profile: $0, userID: $0.id, role: .member) }
                cursor = nil
            } else {
                let result = try await workspaceRead(OrganizationWorkspaceRequest(action: "candidates", principalId: actor.id, organizationId: organization.id,
                        cursor: more ? candidateCursor : nil, search: search, transfer: allowsExistingTeamMembers))
                fresh = (result.users ?? []).map { user in
                    .init(profile: PublicUserProfile(id: user.id, displayName: user.displayName, avatarURL: user.avatarURL.flatMap(URL.init(string:)),
                        city: user.city, federalState: user.federalState.flatMap(AustrianFederalState.init(rawValue:)), updatedAt: nil), userID: user.id, role: .member)
                }
                cursor = result.cursor
            }
            guard generation == expected, candidateGeneration == requestID, !Task.isCancelled else { return }
            var byID = Dictionary(uniqueKeysWithValues: (more ? candidateMembers : []).map { ($0.id, $0) }); fresh.forEach { byID[$0.id] = $0 }
            candidateMembers = byID.values.sorted { $0.id < $1.id }; candidateCursor = cursor; hasMoreCandidates = cursor != nil
        } catch {
            if generation == expected, candidateGeneration == requestID { candidateErrorMessage = AppStrings.Profile.organizationTeamUserSearchFailed }
        }
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

        return await update(
            targetUserID: target.userID,
            organization: organization,
            actor: actor
        ) {
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

        return await update(
            targetUserID: member.userID,
            organization: organization,
            actor: actor
        ) {
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

        return await update(
            targetUserID: target.userID,
            organization: organization,
            actor: actor
        ) {
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
        actor: AppUser,
        operation: () async throws -> Void
    ) async -> Bool {
        let expected = generation
        guard !updatingUserIDs.contains(targetUserID) else { return false }
        updatingUserIDs.insert(targetUserID)
        errorMessage = nil
        statusMessage = nil
        defer { if generation == expected { updatingUserIDs.remove(targetUserID) } }

        do {
            try await operation()
            guard generation == expected, !Task.isCancelled else { return false }
            statusMessage = AppStrings.Profile.organizationTeamUpdated
            return true
        } catch {
            guard generation == expected, !Task.isCancelled else { return false }
            let code = FunctionsErrorCode(rawValue: (error as NSError).code)
            errorMessage = code == .aborted || code == .alreadyExists ? OrganizationWorkspaceCopy.conflict : AppStrings.Profile.organizationTeamSaveFailed
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
