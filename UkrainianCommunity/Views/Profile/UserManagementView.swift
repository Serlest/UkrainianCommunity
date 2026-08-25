import Combine
import FirebaseFirestore
import SwiftUI

private enum UserManagementFilter: CaseIterable, Identifiable {
    case all
    case active
    case warned
    case suspended
    case banned
    case organizationOwners
    case organizationAdmins
    case organizationModerators

    var id: String { title }

    var title: String {
        switch self {
        case .all:
            AppStrings.UserManagement.filterAll
        case .active:
            AppStrings.UserManagement.filterActive
        case .warned:
            AppStrings.UserManagement.filterWarned
        case .suspended:
            AppStrings.UserManagement.filterSuspended
        case .banned:
            AppStrings.UserManagement.filterBanned
        case .organizationOwners:
            AppStrings.UserManagement.filterOrganizationOwners
        case .organizationAdmins:
            AppStrings.UserManagement.filterOrganizationAdmins
        case .organizationModerators:
            AppStrings.UserManagement.filterOrganizationModerators
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            "person.3"
        case .active:
            "checkmark.seal"
        case .warned:
            "exclamationmark.triangle"
        case .suspended:
            "clock.badge.exclamationmark"
        case .banned:
            "lock"
        case .organizationOwners:
            "crown"
        case .organizationAdmins:
            "person.badge.key"
        case .organizationModerators:
            "shield"
        }
    }

    func matches(_ user: AppUser, organizationRoles: [UserOrganizationRole]) -> Bool {
        switch self {
        case .all:
            true
        case .active:
            user.blockState == .active && user.accountStatus == .active
        case .warned:
            user.blockState == .warned || user.accountStatus == .warned
        case .suspended:
            user.blockState == .suspendedUntil || user.blockState == .blocked || user.accountStatus == .suspendedUntil || user.accountStatus == .temporarilyBanned
        case .banned:
            user.blockState == .bannedPermanent || user.blockState == .deactivated || user.accountStatus == .bannedPermanent || user.accountStatus == .permanentlyBanned || user.accountStatus == .deactivated
        case .organizationOwners:
            organizationRoles.contains { $0.role == .communityOwner }
        case .organizationAdmins:
            organizationRoles.contains { $0.role == .communityAdmin }
        case .organizationModerators:
            organizationRoles.contains { $0.role == .communityModerator }
        }
    }
}

enum UserAdminAction: String, Identifiable, CaseIterable {
    case warningIssued
    case suspended
    case banned
    case unblocked
    case deactivated

    var id: String { rawValue }

    var title: String {
        switch self {
        case .warningIssued:
            AppStrings.UserManagement.actionWarn
        case .suspended:
            AppStrings.UserManagement.actionSuspend
        case .banned:
            AppStrings.UserManagement.actionBan
        case .unblocked:
            AppStrings.UserManagement.actionUnblock
        case .deactivated:
            AppStrings.UserManagement.actionDeactivate
        }
    }

    var systemImage: String {
        switch self {
        case .warningIssued:
            "exclamationmark.triangle"
        case .suspended:
            "clock.badge.exclamationmark"
        case .banned:
            "lock"
        case .unblocked:
            "lock.open"
        case .deactivated:
            "person.crop.circle.badge.xmark"
        }
    }

    var effectDescription: String {
        switch self {
        case .warningIssued:
            AppStrings.UserManagement.actionEffectWarning
        case .suspended:
            AppStrings.UserManagement.actionEffectSuspension
        case .banned:
            AppStrings.UserManagement.actionEffectBan
        case .unblocked:
            AppStrings.UserManagement.actionEffectRestore
        case .deactivated:
            AppStrings.UserManagement.actionEffectDeactivate
        }
    }
}

enum PlatformRoleAction: Identifiable {
    case assignAppAdmin
    case removeAppAdmin

    var id: String { title }

    var title: String {
        switch self {
        case .assignAppAdmin:
            AppStrings.UserManagement.assignAppAdmin
        case .removeAppAdmin:
            AppStrings.UserManagement.removeAppAdmin
        }
    }

    var systemImage: String {
        switch self {
        case .assignAppAdmin, .removeAppAdmin:
            "person.badge.key"
        }
    }

    var isRemoval: Bool {
        switch self {
        case .removeAppAdmin:
            true
        case .assignAppAdmin:
            false
        }
    }

    var effectDescription: String {
        isRemoval
            ? AppStrings.UserManagement.platformRoleRemoveEffect
            : AppStrings.UserManagement.platformRoleAssignEffect
    }

}

struct ManagedOrganization: Identifiable, Hashable {
    let id: String
    let name: String
    let city: String
    let logoURL: String?
    let ownerId: String?
    let adminIds: [String]
    let moderatorIds: [String]

    func asOrganization() -> Organization {
        Organization(
            id: id,
            name: name,
            description: name,
            city: city,
            imageURL: logoURL,
            logoURL: logoURL,
            ownerId: ownerId,
            adminIds: adminIds,
            moderatorIds: moderatorIds,
            createdAt: .distantPast,
            updatedAt: .distantPast,
            moderationStatus: .approved,
            likeCount: 0,
            likeState: .notLiked
        )
    }

    func role(for userId: String) -> CommunityRole? {
        if ownerId == userId { return .communityOwner }
        if adminIds.contains(userId) { return .communityAdmin }
        if moderatorIds.contains(userId) { return .communityModerator }
        return nil
    }
}

struct UserOrganizationRole: Identifiable, Hashable {
    let organization: ManagedOrganization
    let role: CommunityRole

    var id: String { organization.id }
}

struct ManagedUserSecurityMetadata: Equatable {
    let emailVerified: Bool
    let authDisabled: Bool
    let creationTime: Date?
    let lastSignInTime: Date?
    let providerIDs: [String]
}

@MainActor
final class UserManagementViewModel: ObservableObject {
    @Published private(set) var users: [AppUser] = []
    @Published private(set) var organizations: [ManagedOrganization] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var isSearching = false
    @Published private(set) var searchResults: [AppUser] = []
    @Published private(set) var searchTotalMatches = 0
    @Published private(set) var securityMetadataByUserID: [String: ManagedUserSecurityMetadata] = [:]
    @Published private(set) var canLoadMore = false
    @Published private(set) var error: AppError?
    @Published var statusMessage: String?
    @Published private(set) var updatingUserIDs = Set<String>()
    @Published private(set) var mutationRevision = 0

    private let db = Firestore.firestore()
    private let roleManagementService: OrganizationRoleManagementService
    private let pageSize = 40
    private var loadedActorKey: String?
    private var lastUserDocument: QueryDocumentSnapshot?
    private var searchGeneration = 0

    private var usersCollection: CollectionReference { db.collection("users") }
    private var organizationsCollection: CollectionReference { db.collection("organizations") }

    init(roleManagementService: OrganizationRoleManagementService? = nil) {
        self.roleManagementService = roleManagementService ?? FirestoreOrganizationRoleManagementService()
    }

    func load(actor: AppUser?) async {
        let actorKey = managementActorKey(for: actor)
        guard loadedActorKey != actorKey || users.isEmpty else { return }
        await refresh(actor: actor)
    }

    func refresh(actor: AppUser?) async {
        let actorKey = managementActorKey(for: actor)
        reset(for: actorKey)

        guard PermissionService.canManageUsers(user: actor) else {
            return
        }

        isLoading = true
        error = nil
        defer {
            isLoading = false
        }

        do {
            let usersSnapshot = try await usersCollection
                .order(by: "createdAt", descending: true)
                .limit(to: pageSize)
                .getDocuments()
            guard loadedActorKey == actorKey, !Task.isCancelled else { return }
            users = usersSnapshot.documents.map(makeUser(from:))
            lastUserDocument = usersSnapshot.documents.last
            canLoadMore = usersSnapshot.documents.count == pageSize
        } catch {
            guard !Task.isCancelled, loadedActorKey == actorKey else { return }
            self.error = .network
            return
        }

        do {
            async let approvedOrganizationsTask = organizationsCollection
                .whereField("moderationStatus", isEqualTo: ModerationStatus.approved.rawValue)
                .getDocuments()
            async let reviewableOrganizationsTask = organizationsCollection
                .whereField(
                    "moderationStatus",
                    in: [
                        ModerationStatus.pendingReview.rawValue,
                        ModerationStatus.needsRevision.rawValue,
                        ModerationStatus.rejected.rawValue
                    ]
                )
                .getDocuments()
            let (approvedOrganizations, reviewableOrganizations) = try await (
                approvedOrganizationsTask,
                reviewableOrganizationsTask
            )
            guard loadedActorKey == actorKey, !Task.isCancelled else { return }
            organizations = uniqueOrganizationDocuments(
                approvedOrganizations.documents + reviewableOrganizations.documents
            )
            .map(makeManagedOrganization(from:))
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            guard !Task.isCancelled, loadedActorKey == actorKey else { return }
            organizations = []
        }
    }

    func loadMore(actor: AppUser?) async {
        guard PermissionService.canManageUsers(user: actor),
              managementActorKey(for: actor) == loadedActorKey,
              canLoadMore,
              !isLoading,
              !isLoadingMore,
              let lastUserDocument else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let snapshot = try await usersCollection
                .order(by: "createdAt", descending: true)
                .start(afterDocument: lastUserDocument)
                .limit(to: pageSize)
                .getDocuments()
            guard managementActorKey(for: actor) == loadedActorKey, !Task.isCancelled else { return }

            let existingIDs = Set(users.map(\.id))
            users.append(contentsOf: snapshot.documents.map(makeUser(from:)).filter { !existingIDs.contains($0.id) })
            self.lastUserDocument = snapshot.documents.last
            canLoadMore = snapshot.documents.count == pageSize
        } catch {
            guard !Task.isCancelled else { return }
            statusMessage = AppStrings.UserManagement.loadMoreFailed
        }
    }

    func search(query: String, actor: AppUser?) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.count >= 2 else {
            clearSearch()
            return
        }
        guard let actor, PermissionService.canManageUsers(user: actor) else {
            clearSearch()
            return
        }

        searchGeneration &+= 1
        let generation = searchGeneration
        isSearching = true
        defer {
            if generation == searchGeneration {
                isSearching = false
            }
        }

        do {
            let response = try await CloudFunctionsClient.shared.searchManagedUsers(query: trimmedQuery)
            guard generation == searchGeneration, !Task.isCancelled else { return }

            var usersByID: [String: AppUser] = [:]
            for userIDs in response.userIds.chunked(into: 30) where !userIDs.isEmpty {
                let snapshot = try await usersCollection
                    .whereField(FieldPath.documentID(), in: Array(userIDs))
                    .getDocuments()
                guard generation == searchGeneration, !Task.isCancelled else { return }
                for document in snapshot.documents {
                    usersByID[document.documentID] = makeUser(from: document)
                }
            }

            searchResults = response.userIds.compactMap { usersByID[$0] }
            searchTotalMatches = response.totalMatches
        } catch {
            guard generation == searchGeneration, !Task.isCancelled else { return }
            searchResults = []
            searchTotalMatches = 0
            statusMessage = AppStrings.UserManagement.searchFailed
        }
    }

    func clearSearch() {
        searchGeneration &+= 1
        isSearching = false
        searchResults = []
        searchTotalMatches = 0
    }

    func loadSecurityMetadata(userID: String, actor: AppUser?) async {
        guard let actor, PermissionService.canManageUsers(user: actor) else { return }

        do {
            let response = try await CloudFunctionsClient.shared.getManagedUserSecurityMetadata(userId: userID)
            guard response.targetUserId == userID, !Task.isCancelled else { return }
            securityMetadataByUserID[userID] = ManagedUserSecurityMetadata(
                emailVerified: response.emailVerified,
                authDisabled: response.authDisabled,
                creationTime: response.creationTime.flatMap(Self.parseAuthDate),
                lastSignInTime: response.lastSignInTime.flatMap(Self.parseAuthDate),
                providerIDs: response.providerIds
            )
        } catch {
            guard !Task.isCancelled else { return }
            securityMetadataByUserID[userID] = nil
        }
    }

    func securityMetadata(for userID: String) -> ManagedUserSecurityMetadata? {
        securityMetadataByUserID[userID]
    }

    func refreshDetail(userID: String, actor: AppUser?) async {
        await refresh(actor: actor)
        guard let actor, PermissionService.canManageUsers(user: actor) else { return }
        await reloadUser(id: userID, actor: actor)
    }

    func perform(
        _ action: UserAdminAction,
        target: AppUser,
        actor: AppUser,
        reason: String,
        suspensionDays: Int = 7
    ) async {
        guard canManage(target: target, actor: actor) else {
            statusMessage = AppStrings.UserManagement.statusPermissionDenied
            return
        }

        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReason.isEmpty else {
            statusMessage = AppStrings.UserManagement.reasonRequired
            return
        }

        await updateUser(target, actor: actor, failureMessage: accountStatusFailureMessage(from:)) {
            switch action {
            case .warningIssued:
                _ = try await CloudFunctionsClient.shared.warnUser(userId: target.id, reason: trimmedReason)
            case .suspended:
                let safeDays = min(max(suspensionDays, 1), 365)
                let suspendedUntil = Calendar.current.date(byAdding: .day, value: safeDays, to: Date()) ?? Date().addingTimeInterval(TimeInterval(safeDays * 24 * 60 * 60))
                _ = try await CloudFunctionsClient.shared.suspendUser(userId: target.id, until: suspendedUntil, reason: trimmedReason)
            case .banned:
                _ = try await CloudFunctionsClient.shared.banUser(userId: target.id, reason: trimmedReason)
            case .unblocked:
                _ = try await CloudFunctionsClient.shared.restoreUser(userId: target.id, reason: trimmedReason)
            case .deactivated:
                _ = try await CloudFunctionsClient.shared.deactivateUser(userId: target.id, reason: trimmedReason)
            }
        }
    }

    func assignRole(_ role: CommunityRole, in organization: ManagedOrganization, to target: AppUser, actor: AppUser, reason: String) async {
        guard canManageOrganizationRoles(in: organization, actor: actor) else {
            statusMessage = AppStrings.UserManagement.rolePermissionDenied
            return
        }

        if role == .communityOwner {
            await changeOwner(in: organization, to: target, actor: actor, reason: reason)
            return
        }

        guard role != .member else { return }
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusMessage = AppStrings.UserManagement.reasonRequired
            return
        }

        await updateUser(target, actor: actor, failureMessage: organizationRoleFailureMessage(from:)) {
            try await updateOrganizationRole(
                role: role,
                organization: organization,
                target: target,
                actor: actor,
                reason: reason,
                isRemoval: false
            )
        }
        await reloadOrganizationAfterSuccessfulMutation(id: organization.id)
    }

    func changeOwner(in organization: ManagedOrganization, to target: AppUser, actor: AppUser, reason: String) async {
        guard PermissionService.canInitiateOwnershipTransferWorkflow(user: actor) else {
            statusMessage = AppStrings.UserManagement.ownerChangePermissionDenied
            return
        }

        guard PermissionService.isUsableAccount(user: target) else {
            statusMessage = AppStrings.UserManagement.platformRoleTargetAccountNotUsable
            return
        }

        guard organization.ownerId != target.id else {
            statusMessage = AppStrings.UserManagement.ownerChangeSelectNewOwner
            return
        }
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusMessage = AppStrings.UserManagement.reasonRequired
            return
        }

        await updateUser(target, actor: actor, failureMessage: organizationRoleFailureMessage(from:)) {
            try await updateOrganizationOwner(
                organization: organization,
                newOwner: target,
                actor: actor,
                reason: reason
            )
        }
        await reloadOrganizationAfterSuccessfulMutation(id: organization.id)
    }

    func removeRole(in organization: ManagedOrganization, from target: AppUser, actor: AppUser, reason: String) async {
        guard canManageOrganizationRoles(in: organization, actor: actor) else {
            statusMessage = AppStrings.UserManagement.removeRolePermissionDenied
            return
        }

        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusMessage = AppStrings.UserManagement.reasonRequired
            return
        }

        await updateUser(target, actor: actor, failureMessage: organizationRoleFailureMessage(from:)) {
            try await updateOrganizationRole(
                role: .member,
                organization: organization,
                target: target,
                actor: actor,
                reason: reason,
                isRemoval: true
            )
        }
        await reloadOrganizationAfterSuccessfulMutation(id: organization.id)
    }

    func performPlatformRoleAction(_ action: PlatformRoleAction, target: AppUser, actor: AppUser, reason: String) async {
        guard !PermissionService.hasOwnerRoleForDisplay(user: target) else {
            statusMessage = AppStrings.UserManagement.platformRoleTargetOwnerProtected
            return
        }

        guard actor.id != target.id else {
            statusMessage = AppStrings.UserManagement.platformRoleSelfChangeRejected
            return
        }

        guard canManagePlatformRole(target: target, actor: actor) else {
            statusMessage = AppStrings.UserManagement.platformRolePermissionDenied
            return
        }

        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReason.isEmpty else {
            statusMessage = AppStrings.UserManagement.reasonRequired
            return
        }

        await updateUser(target, actor: actor, failureMessage: platformRoleFailureMessage(from:)) {
            switch action {
            case .assignAppAdmin:
                _ = try await CloudFunctionsClient.shared.assignAppAdmin(userId: target.id, reason: trimmedReason)
            case .removeAppAdmin:
                _ = try await CloudFunctionsClient.shared.removeAppAdmin(userId: target.id, reason: trimmedReason)
            }
        }
    }

    func canManage(target: AppUser, actor: AppUser) -> Bool {
        PermissionService.canManageUserTarget(actor: actor, target: target)
    }

    func canManagePlatformRole(target: AppUser, actor: AppUser) -> Bool {
        PermissionService.canManageUserTarget(actor: actor, target: target)
            && PermissionService.canAssignGlobalRoles(user: actor)
    }

    func canManageOrganizationRoles(in organization: ManagedOrganization, actor: AppUser) -> Bool {
        PermissionService.canInitiateOrganizationRoleWorkflow(user: actor)
            || (PermissionService.isUsableAccount(user: actor) && organization.ownerId == actor.id)
    }

    func user(withID id: String) -> AppUser? {
        users.first { $0.id == id }
    }

    func organizationRoles(for user: AppUser) -> [UserOrganizationRole] {
        organizations.compactMap { organization in
            guard let role = organization.role(for: user.id) else { return nil }
            return UserOrganizationRole(organization: organization, role: role)
        }
    }

    private func updateUser(_ target: AppUser, actor: AppUser, operation: () async throws -> Void) async {
        await updateUser(target, actor: actor, failureMessage: nil, operation: operation)
    }

    private func updateUser(
        _ target: AppUser,
        actor: AppUser,
        failureMessage: ((Error) -> String?)?,
        operation: () async throws -> Void
    ) async {
        guard !updatingUserIDs.contains(target.id) else { return }
        updatingUserIDs.insert(target.id)
        statusMessage = nil
        defer { updatingUserIDs.remove(target.id) }

        do {
            try await operation()
            statusMessage = AppStrings.UserManagement.changesSaved
            mutationRevision &+= 1
            await reloadUser(id: target.id, actor: actor)
        } catch {
            self.error = .permissionDenied
            statusMessage = failureMessage?(error) ?? AppStrings.UserManagement.changesFailed
        }
    }

    private func reloadUser(id: String, actor: AppUser) async {
        guard managementActorKey(for: actor) == loadedActorKey else { return }

        do {
            let document = try await usersCollection.document(id).getDocument()
            guard document.exists, let data = document.data() else { return }
            let refreshedUser = makeUser(id: document.documentID, data: data)
            if let index = users.firstIndex(where: { $0.id == id }) {
                users[index] = refreshedUser
            } else {
                users.append(refreshedUser)
            }
        } catch {
            statusMessage = AppStrings.UserManagement.changesSavedRefreshFailed
        }
    }

    private func reloadOrganizationAfterSuccessfulMutation(id: String) async {
        guard statusMessage == AppStrings.UserManagement.changesSaved else { return }

        do {
            let document = try await organizationsCollection.document(id).getDocument()
            guard document.exists, let data = document.data() else {
                statusMessage = AppStrings.UserManagement.organizationMissing
                return
            }
            let refreshedOrganization = makeManagedOrganization(id: document.documentID, data: data)
            if let index = organizations.firstIndex(where: { $0.id == id }) {
                organizations[index] = refreshedOrganization
            } else {
                organizations.append(refreshedOrganization)
                organizations.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
        } catch {
            statusMessage = AppStrings.UserManagement.changesSavedRefreshFailed
        }
    }

    private func platformRoleFailureMessage(from error: Error) -> String? {
        let message = (error as NSError).localizedDescription.lowercased()

        if message.contains("owner role cannot be changed") {
            return AppStrings.UserManagement.platformRoleTargetOwnerProtected
        }
        if message.contains("self role changes") {
            return AppStrings.UserManagement.platformRoleSelfChangeRejected
        }
        if message.contains("usable account") {
            return AppStrings.UserManagement.platformRoleTargetAccountNotUsable
        }
        if message.contains("already applied") {
            return AppStrings.UserManagement.platformRoleNoOp
        }
        if message.contains("target user does not exist") {
            return AppStrings.UserManagement.platformRoleTargetMissing
        }
        if message.contains("owner permissions") || message.contains("permission") {
            return AppStrings.UserManagement.platformRolePermissionDenied
        }

        return nil
    }

    private func accountStatusFailureMessage(from error: Error) -> String? {
        let message = (error as NSError).localizedDescription.lowercased()

        if message.contains("owner account status cannot be changed") || message.contains("owner role cannot be changed") {
            return AppStrings.UserManagement.platformRoleTargetOwnerProtected
        }
        if message.contains("self account status") || message.contains("self-target") {
            return AppStrings.UserManagement.platformRoleSelfChangeRejected
        }
        if message.contains("target user does not exist") {
            return AppStrings.UserManagement.platformRoleTargetMissing
        }
        if message.contains("owner permissions") || message.contains("permission") {
            return AppStrings.UserManagement.statusPermissionDenied
        }

        return nil
    }

    private func organizationRoleFailureMessage(from error: Error) -> String? {
        let message = (error as NSError).localizedDescription.lowercased()

        if message.contains("organization role permissions") || message.contains("owner permissions") {
            return AppStrings.UserManagement.rolePermissionDenied
        }
        if message.contains("verify their email") {
            return AppStrings.UserManagement.organizationRoleTargetEmailUnverified
        }
        if message.contains("active account") || message.contains("account is disabled") {
            return AppStrings.UserManagement.platformRoleTargetAccountNotUsable
        }
        if message.contains("owner role cannot be changed") {
            return AppStrings.UserManagement.ownerTransferOnly
        }
        if message.contains("organization does not exist") {
            return AppStrings.UserManagement.organizationMissing
        }

        return nil
    }

    private func updateOrganizationRole(
        role: CommunityRole,
        organization: ManagedOrganization,
        target: AppUser,
        actor: AppUser,
        reason: String,
        isRemoval: Bool
    ) async throws {
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalReason = trimmedReason.isEmpty ? "Organization role update" : trimmedReason

        try await roleManagementService.updateRole(
            role: role,
            organization: organization.asOrganization(),
            targetUserID: target.id,
            actor: actor,
            isRemoval: isRemoval,
            reason: finalReason
        )
    }

    private func updateOrganizationOwner(
        organization: ManagedOrganization,
        newOwner: AppUser,
        actor: AppUser,
        reason: String
    ) async throws {
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalReason = trimmedReason.isEmpty ? "Organization owner changed" : trimmedReason

        try await roleManagementService.transferOwner(
            organization: organization.asOrganization(),
            newOwnerID: newOwner.id,
            actor: actor,
            reason: finalReason
        )
    }

    private func makeUser(from document: QueryDocumentSnapshot) -> AppUser {
        makeUser(id: document.documentID, data: document.data())
    }

    private func makeUser(id: String, data: [String: Any]) -> AppUser {
        let legacyRole = UserRole(rawValue: data["role"] as? String ?? "") ?? .user
        let globalRole = (data["globalRole"] as? String).flatMap(GlobalRole.init(rawValue:)) ?? .user
        let isBlocked = data["isBlocked"] as? Bool ?? false
        let blockState = UserBlockState(rawValue: data["blockState"] as? String ?? "") ?? (isBlocked ? .suspendedUntil : .active)
        return AppUser(
            id: data["id"] as? String ?? id,
            fullName: data["fullName"] as? String ?? "",
            displayName: data["displayName"] as? String ?? data["fullName"] as? String ?? "",
            city: data["city"] as? String ?? "",
            email: data["email"] as? String ?? "",
            avatarURL: (data["avatarURL"] as? String).flatMap(URL.init(string:)),
            bio: data["bio"] as? String ?? "",
            telegramUsername: data["telegramUsername"] as? String,
            role: legacyRole,
            globalRole: globalRole,
            moderatorSections: (data["moderatorSections"] as? [String] ?? []).compactMap(AppSection.init(rawValue:)),
            blockState: blockState,
            accountStatus: (data["accountStatus"] as? String).flatMap(AccountStatus.init(rawValue:)) ?? (blockState.isRestricted ? .suspendedUntil : .active),
            banExpiresAt: (data["banExpiresAt"] as? Timestamp)?.dateValue(),
            warningCount: data["warningCount"] as? Int ?? 0,
            statusReason: data["statusReason"] as? String,
            statusMessage: data["statusMessage"] as? String,
            statusUpdatedAt: (data["statusUpdatedAt"] as? Timestamp)?.dateValue(),
            statusUpdatedBy: data["statusUpdatedBy"] as? String,
            statusAcknowledgedAt: (data["statusAcknowledgedAt"] as? Timestamp)?.dateValue(),
            communityMemberships: [],
            selectedFederalState: (data["selectedFederalState"] as? String).flatMap(AustrianFederalState.init(rawValue:)),
            acceptedTermsAt: (data["acceptedTermsAt"] as? Timestamp)?.dateValue(),
            acceptedPrivacyAt: (data["acceptedPrivacyAt"] as? Timestamp)?.dateValue(),
            termsVersion: data["termsVersion"] as? String,
            privacyVersion: data["privacyVersion"] as? String,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? .distantPast,
            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? .distantPast
        )
    }

    private func makeManagedOrganization(from document: QueryDocumentSnapshot) -> ManagedOrganization {
        makeManagedOrganization(id: document.documentID, data: document.data())
    }

    private func makeManagedOrganization(id: String, data: [String: Any]) -> ManagedOrganization {
        return ManagedOrganization(
            id: id,
            name: data["name"] as? String ?? id,
            city: data["city"] as? String ?? "",
            logoURL: data["logoURL"] as? String ?? data["imageURL"] as? String,
            ownerId: data["ownerId"] as? String,
            adminIds: data["adminIds"] as? [String] ?? [],
            moderatorIds: data["moderatorIds"] as? [String] ?? []
        )
    }

    private func uniqueOrganizationDocuments(_ documents: [QueryDocumentSnapshot]) -> [QueryDocumentSnapshot] {
        var seenIDs = Set<String>()
        return documents.filter { seenIDs.insert($0.documentID).inserted }
    }

    private func managementActorKey(for actor: AppUser?) -> String? {
        guard let actor, PermissionService.canManageUsers(user: actor) else { return nil }
        return "\(actor.id)|\(actor.globalRole.authorizationRole.rawValue)"
    }

    private func reset(for actorKey: String?) {
        loadedActorKey = actorKey
        users = []
        organizations = []
        error = nil
        canLoadMore = false
        lastUserDocument = nil
        clearSearch()
        securityMetadataByUserID = [:]
    }

    nonisolated private static func parseAuthDate(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }


}

struct UserManagementView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel = UserManagementViewModel()
    @State private var searchText = ""
    @State private var selectedFilter: UserManagementFilter = .all
    @State private var isShowingRoleGuide = false
    @FocusState private var isSearchFocused: Bool

    private var actor: AppUser? { authState.user }
    private var canAccessUserManagement: Bool {
        PermissionService.canManageUsers(user: actor)
    }

    private var actorLoadKey: String {
        guard let actor else { return "signed-out" }
        return "\(actor.id)|\(actor.globalRole.authorizationRole.rawValue)"
    }

    private var filteredUsers: [AppUser] {
        candidateUsers.filter { user in
            selectedFilter.matches(user, organizationRoles: viewModel.organizationRoles(for: user))
        }
    }

    private var normalizedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var candidateUsers: [AppUser] {
        normalizedSearch.isEmpty ? viewModel.users : viewModel.searchResults
    }

    var body: some View {
        AdminScreenShell(
            title: AppStrings.UserManagement.title,
            subtitle: AppStrings.UserManagement.contentSubtitle,
            tabBarHidden: false
        ) {
            userManagementContent
        }
        .task(id: actorLoadKey) {
            await viewModel.load(actor: actor)
        }
        .task(id: normalizedSearch) {
            guard normalizedSearch.count >= 2 else {
                viewModel.clearSearch()
                return
            }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await viewModel.search(query: normalizedSearch, actor: actor)
        }
        .refreshable {
            await viewModel.refresh(actor: actor)
        }
        .alert(AppStrings.UserManagement.title, isPresented: Binding(
            get: { viewModel.statusMessage != nil },
            set: { if !$0 { viewModel.statusMessage = nil } }
        )) {
            Button(AppStrings.Common.ok, role: .cancel) {}
        } message: {
            Text(viewModel.statusMessage ?? "")
        }
        .sheet(isPresented: $isShowingRoleGuide) {
            UserRolePermissionsSheet()
        }
    }

    @ViewBuilder
    private var userManagementContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
            if !canAccessUserManagement {
                UnifiedEmptyStateCard(
                    systemImage: "lock.shield",
                    title: AppStrings.UserManagement.title,
                    message: AppStrings.UserManagement.permission
                )
            } else {
                summaryCard
                searchField
                filterRow
                contentList
            }
        }
    }

    private var summaryCard: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                HStack(spacing: AppTheme.eventsMetadataSpacing) {
                    Label("\(viewModel.users.count)", systemImage: "person.3")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(viewModel.canLoadMore ? AppStrings.UserManagement.loadedUsers : AppStrings.UserManagement.registeredUsers)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)

                    Spacer(minLength: 0)

                    if viewModel.isLoading {
                        ProgressView()
                    }
                }

                Button {
                    isShowingRoleGuide = true
                } label: {
                    Label(AppStrings.UserManagement.roleGuideButton, systemImage: "questionmark.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.accentPrimaryForeground)

                AppHorizontalFilterRow {
                    ForEach(UserManagementFilter.allCases.prefix(5)) { filter in
                        UserManagementStatusBadge(
                            title: "\(filter.title): \(count(for: filter))",
                            tint: selectedFilter == filter ? AppTheme.accentPrimaryForeground : AppTheme.textSecondary
                        )
                    }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: AppTheme.eventsMetadataSpacing) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppTheme.textSecondary)

            TextField(AppStrings.UserManagement.searchPlaceholder, text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.subheadline)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .onSubmit { isSearchFocused = false }

            if !searchText.isEmpty {
                AppSearchClearButton {
                    searchText = ""
                }
            }


            if viewModel.isSearching {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, AppTheme.inputHorizontalPadding)
        .frame(minHeight: AppTheme.searchControlHeight)
        .background(AppTheme.surfaceControl.opacity(0.45), in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle)
        )
    }

    private var filterRow: some View {
        AppHorizontalFilterRow {
            ForEach(UserManagementFilter.allCases) { filter in
                Button {
                    selectedFilter = filter
                } label: {
                    AppFilterChip(
                        title: "\(filter.title) · \(count(for: filter))",
                        systemImage: filter.systemImage,
                        isSelected: selectedFilter == filter
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var contentList: some View {
        if viewModel.isSearching {
            LoadingStateCard(title: AppStrings.UserManagement.searching)
        } else if viewModel.isLoading && viewModel.users.isEmpty {
            LoadingStateCard(title: AppStrings.UserManagement.title)
        } else if viewModel.users.isEmpty, viewModel.error != nil {
            UnifiedEmptyStateCard(
                systemImage: "exclamationmark.triangle",
                title: AppStrings.UserManagement.title,
                message: AppStrings.UserManagement.loadError
            ) {
                PrimaryActionButton(title: AppStrings.UserManagement.retry, systemImage: "arrow.clockwise") {
                    Task { await viewModel.refresh(actor: actor) }
                }
            }
        } else if filteredUsers.isEmpty {
            VStack(spacing: AppTheme.dashboardSpacing) {
                UnifiedEmptyStateCard(
                    systemImage: "person.crop.circle.badge.questionmark",
                    title: AppStrings.UserManagement.noResultsTitle,
                    message: AppStrings.UserManagement.noResultsMessage
                )
                if normalizedSearch.isEmpty { loadMoreButton }
            }
        } else {
            VStack(spacing: AppTheme.feedRowSpacing) {
                ForEach(filteredUsers) { user in
                    NavigationLink {
                        UserDetailView(
                            userID: user.id,
                            fallbackUser: user,
                            viewModel: viewModel,
                            actor: actor
                        )
                    } label: {
                        ManagedUserRow(user: user, organizationRoles: viewModel.organizationRoles(for: user))
                    }
                    .buttonStyle(.plain)
                }
                if normalizedSearch.isEmpty {
                    loadMoreButton
                } else {
                    Text(AppStrings.UserManagement.searchResultCount(viewModel.searchTotalMatches))
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
    }

    @ViewBuilder
    private var loadMoreButton: some View {
        if viewModel.canLoadMore {
            PrimaryActionButton(
                title: AppStrings.UserManagement.loadMore,
                isEnabled: !viewModel.isLoadingMore,
                isLoading: viewModel.isLoadingMore,
                systemImage: "arrow.down.circle"
            ) {
                Task { await viewModel.loadMore(actor: actor) }
            }
        }
    }

    private func count(for filter: UserManagementFilter) -> Int {
        viewModel.users.filter {
            filter.matches($0, organizationRoles: viewModel.organizationRoles(for: $0))
        }.count
    }

}

private struct ManagedUserRow: View {
    let user: AppUser
    let organizationRoles: [UserOrganizationRole]

    var body: some View {
        AppEditorSectionCard {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    UserManagementAvatar(user: user, size: 46)
                    identityContent
                    Spacer(minLength: 12)
                    registrationDate
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        UserManagementAvatar(user: user, size: 46)
                        identityText
                    }
                    badges
                    registrationDate
                }
            }
        }
    }

    private var identityContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            identityText
            badges
        }
    }

    private var identityText: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(user.preferredDisplayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(secondaryLine)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var badges: some View {
        UserManagementBadgeFlowLayout(spacing: 6) {
            UserManagementStatusBadge(title: user.blockState.title, tint: statusTint)

            if !user.city.isEmpty {
                UserManagementStatusBadge(title: user.city, tint: AppTheme.textSecondary)
            }

            if let primaryOrganizationRole {
                UserManagementStatusBadge(title: primaryOrganizationRole, tint: AppTheme.accentPrimaryForeground)
            }

            if organizationRoles.count > 1 {
                UserManagementStatusBadge(title: AppStrings.UserManagement.organizationRolesAdditionalCount(organizationRoles.count - 1), tint: AppTheme.accentPrimaryForeground)
            }
        }
    }

    private var registrationDate: some View {
        Label(
            LocalizationStore.dateString(from: user.createdAt, dateStyle: .short, timeStyle: .none),
            systemImage: "calendar"
        )
        .font(.caption2)
        .foregroundStyle(AppTheme.textSecondary)
        .multilineTextAlignment(.trailing)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var secondaryLine: String {
        if !user.email.isEmpty { return user.email }
        if let telegramUsername = user.telegramUsername, !telegramUsername.isEmpty { return telegramUsername }
        return user.id
    }

    private var statusTint: Color {
        switch user.blockState {
        case .active:
            AppTheme.accentPrimary
        case .warned:
            AppTheme.accentSupport
        case .suspendedUntil, .blocked, .bannedPermanent, .deactivated:
            AppTheme.accentDestructive
        }
    }

    private var primaryOrganizationRole: String? {
        if organizationRoles.contains(where: { $0.role == .communityOwner }) { return AppStrings.UserManagement.organizationOwnerRole }
        if organizationRoles.contains(where: { $0.role == .communityAdmin }) { return AppStrings.UserManagement.organizationAdminRole }
        if organizationRoles.contains(where: { $0.role == .communityModerator }) { return AppStrings.UserManagement.organizationModeratorRole }
        return nil
    }
}

private enum UserDetailFocusField {
    case organizationSearch
    case roleReason
}

private struct PendingOwnershipTransfer: Identifiable {
    let organization: ManagedOrganization
    let target: AppUser
    let reason: String

    var id: String { "\(organization.id)|\(target.id)" }
}

private struct UserDetailView: View {
    let userID: String
    let fallbackUser: AppUser
    @ObservedObject var viewModel: UserManagementViewModel
    let actor: AppUser?

    @State private var selectedOrganizationID: String?
    @State private var selectedRole: CommunityRole = .communityModerator
    @State private var organizationSearchText = ""
    @State private var roleReason = ""
    @State private var pendingAction: UserAdminAction?
    @State private var pendingRoleRemoval: ManagedOrganization?
    @State private var pendingPlatformRoleAction: PlatformRoleAction?
    @State private var pendingOwnershipTransfer: PendingOwnershipTransfer?
    @FocusState private var focusedField: UserDetailFocusField?

    private var selectedOrganization: ManagedOrganization? {
        assignmentOrganizations.first { $0.id == selectedOrganizationID }
    }

    private var user: AppUser {
        viewModel.user(withID: userID) ?? fallbackUser
    }

    private var securityMetadata: ManagedUserSecurityMetadata? {
        viewModel.securityMetadata(for: userID)
    }

    private var organizations: [ManagedOrganization] {
        viewModel.organizations
    }

    private var organizationRoles: [UserOrganizationRole] {
        viewModel.organizationRoles(for: user)
    }

    private var assignmentOrganizations: [ManagedOrganization] {
        guard let actor else { return [] }
        return organizations.filter { viewModel.canManageOrganizationRoles(in: $0, actor: actor) }
    }

    private var filteredOrganizations: [ManagedOrganization] {
        let query = organizationSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return assignmentOrganizations }

        return assignmentOrganizations.filter { organization in
            [organization.name, organization.city, organization.id]
                .contains { $0.lowercased().contains(query) }
        }
    }

    private var canAssignSelectedOrganizationRole: Bool {
        guard let selectedOrganization else { return false }
        guard PermissionService.isUsableAccount(user: user) else { return false }
        let query = organizationSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty || filteredOrganizations.contains(where: { $0.id == selectedOrganization.id }) else {
            return false
        }
        guard selectedOrganization.role(for: user.id) != selectedRole else { return false }
        guard selectedOrganization.ownerId != user.id else { return false }
        return selectedRole != .communityOwner || canTransferOwnership
    }

    private var assignableRoles: [CommunityRole] {
        guard selectedOrganization?.ownerId != user.id else {
            return [.communityOwner]
        }
        return canTransferOwnership
            ? [.communityOwner, .communityAdmin, .communityModerator]
            : [.communityAdmin, .communityModerator]
    }

    private var isUpdating: Bool {
        viewModel.updatingUserIDs.contains(userID)
    }

    private var canManage: Bool {
        actor.map { viewModel.canManage(target: user, actor: $0) } ?? false
    }

    private var canManageSelectedOrganizationRoles: Bool {
        guard let actor, let selectedOrganization else { return false }
        return viewModel.canManageOrganizationRoles(in: selectedOrganization, actor: actor)
    }

    private var canTransferOwnership: Bool {
        PermissionService.canInitiateOwnershipTransferWorkflow(user: actor)
    }

    private var roleAssignmentBlockingMessage: String? {
        guard !organizations.isEmpty else {
            return AppStrings.UserManagement.organizationsNotLoaded
        }
        guard !assignmentOrganizations.isEmpty else {
            return AppStrings.UserManagement.roleAssignmentUnavailable
        }
        guard PermissionService.isUsableAccount(user: user) else {
            return AppStrings.UserManagement.platformRoleTargetAccountNotUsable
        }
        if securityMetadata?.emailVerified == false {
            return AppStrings.UserManagement.organizationRoleTargetEmailUnverified
        }
        guard let selectedOrganization else {
            return AppStrings.UserManagement.organizationsNotLoaded
        }
        if selectedOrganization.ownerId == user.id {
            return AppStrings.UserManagement.ownerTransferOnly
        }
        if selectedOrganization.role(for: user.id) == selectedRole {
            return AppStrings.UserManagement.organizationRoleAlreadyAssigned
        }
        if selectedRole == .communityOwner && !canTransferOwnership {
            return AppStrings.UserManagement.ownerChangePermissionDenied
        }
        if roleReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AppStrings.UserManagement.reasonRequired
        }
        return nil
    }

    private var availableAccountActions: [UserAdminAction] {
        switch user.blockState {
        case .active:
            [.warningIssued, .suspended, .banned, .deactivated]
        case .warned:
            [.suspended, .banned, .deactivated]
        case .suspendedUntil, .blocked:
            [.unblocked, .banned, .deactivated]
        case .bannedPermanent, .deactivated:
            [.unblocked]
        }
    }

    var body: some View {
        lifecycleScreen
            .sheet(item: $pendingAction) { action in
                AccountActionConfirmationSheet(
                    action: action,
                    target: user,
                    actor: actor,
                    viewModel: viewModel
                )
            }
            .sheet(item: $pendingPlatformRoleAction) { action in
                PlatformRoleConfirmationSheet(
                    action: action,
                    target: user,
                    actor: actor,
                    viewModel: viewModel
                )
            }
            .sheet(item: $pendingRoleRemoval) { organization in
                OrganizationRoleRemovalSheet(
                    organization: organization,
                    target: user,
                    actor: actor,
                    viewModel: viewModel
                )
            }
            .confirmationDialog(
                AppStrings.UserManagement.ownerTransferConfirmationTitle,
                isPresented: Binding(
                    get: { pendingOwnershipTransfer != nil },
                    set: { if !$0 { pendingOwnershipTransfer = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let pendingOwnershipTransfer {
                    Button(AppStrings.UserManagement.changeOwnerButton, role: .destructive) {
                        performOwnershipTransfer(pendingOwnershipTransfer)
                    }
                }
                Button(AppStrings.Common.cancel, role: .cancel) {}
            } message: {
                if let pendingOwnershipTransfer {
                    Text(
                        AppStrings.UserManagement.ownerTransferConfirmationMessage(
                            pendingOwnershipTransfer.target.preferredDisplayName,
                            pendingOwnershipTransfer.organization.name
                        )
                    )
                }
            }
    }

    private var baseScreen: some View {
        PushedScreenShell(
            title: user.preferredDisplayName
        ) {
            AppGroupedContentPlane {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    profileCard
                    platformRolesCard
                    organizationRolesCard
                    roleAssignmentCard
                    accountActionsCard
                    UserAuditHistoryCard(userId: user.id, refreshToken: viewModel.mutationRevision)
                }
            }
        }
    }

    private var lifecycleScreen: some View {
        baseScreen
            .contentShape(Rectangle())
            .refreshable {
                await viewModel.refreshDetail(userID: userID, actor: actor)
                ensureSelectedOrganization()
                ensureSelectedRole()
            }
            .task {
                ensureSelectedOrganization()
                ensureSelectedRole()
                await viewModel.loadSecurityMetadata(userID: userID, actor: actor)
            }
            .onChange(of: viewModel.organizations.count) { _, _ in
                ensureSelectedOrganization()
                ensureSelectedRole()
            }
            .onChange(of: selectedOrganizationID) { _, _ in
                ensureSelectedRole()
            }
            .onChange(of: selectedOrganization?.ownerId) { _, _ in
                ensureSelectedRole()
            }
            .onChange(of: organizationSearchText) { _, _ in
                ensureSelectedOrganization(allowFilteredMatch: true)
                ensureSelectedRole()
            }
    }

    private var profileCard: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                HStack(spacing: 12) {
                    UserManagementAvatar(user: user, size: 64)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(user.preferredDisplayName)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)

                        Text(user.email.isEmpty ? user.id : user.email)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)

                        UserManagementBadgeFlowLayout(spacing: 6) {
                            UserManagementStatusBadge(title: user.blockState.title, tint: statusTint)
                            UserManagementStatusBadge(title: user.globalRole.title, tint: PermissionService.hasOwnerRoleForDisplay(user: user) ? AppTheme.accentSupport : AppTheme.textSecondary)
                        }

                        if !organizationRoles.isEmpty {
                            UserManagementBadgeFlowLayout(spacing: 6) {
                                ForEach(organizationRoles.prefix(3)) { item in
                                    UserManagementStatusBadge(title: roleTitle(item.role), tint: AppTheme.accentPrimaryForeground)
                                }
                                if organizationRoles.count > 3 {
                                    UserManagementStatusBadge(
                                        title: AppStrings.UserManagement.organizationRolesAdditionalCount(organizationRoles.count - 3),
                                        tint: AppTheme.accentPrimaryForeground
                                    )
                                }
                            }
                        }
                    }
                }

                Divider()

                UserManagementMetadataRow(systemImage: "number", title: AppStrings.UserManagement.uid, value: user.id)
                UserManagementMetadataRow(systemImage: "at", title: "Telegram", value: user.telegramUsername ?? AppStrings.Common.notAvailable)
                UserManagementMetadataRow(systemImage: "mappin.and.ellipse", title: AppStrings.UserManagement.cityRegion, value: locationText)
                UserManagementMetadataRow(systemImage: "calendar", title: AppStrings.UserManagement.joined, value: LocalizationStore.dateString(from: user.createdAt, dateStyle: .medium, timeStyle: .none))
                if let securityMetadata {
                    UserManagementMetadataRow(
                        systemImage: securityMetadata.emailVerified ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                        title: AppStrings.UserManagement.emailVerification,
                        value: securityMetadata.emailVerified
                            ? AppStrings.UserManagement.emailVerified
                            : AppStrings.UserManagement.emailNotVerified
                    )
                    UserManagementMetadataRow(
                        systemImage: "clock.arrow.circlepath",
                        title: AppStrings.UserManagement.lastSignIn,
                        value: securityMetadata.lastSignInTime.map {
                            LocalizationStore.dateString(from: $0, dateStyle: .medium, timeStyle: .short)
                        } ?? AppStrings.UserManagement.neverSignedIn
                    )
                    UserManagementMetadataRow(
                        systemImage: "key.horizontal",
                        title: AppStrings.UserManagement.signInProvider,
                        value: securityMetadata.providerIDs.isEmpty
                            ? AppStrings.Common.notAvailable
                            : securityMetadata.providerIDs.joined(separator: ", ")
                    )
                }
                if let banExpiresAt = user.banExpiresAt {
                    UserManagementMetadataRow(systemImage: "clock", title: AppStrings.UserManagement.blockedUntil, value: LocalizationStore.dateString(from: banExpiresAt, dateStyle: .medium, timeStyle: .short))
                }
            }
        }
    }

    private var organizationRolesCard: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                SectionHeaderBlock(title: AppStrings.UserManagement.organizationRolesTitle, subtitle: AppStrings.UserManagement.organizationRolesSubtitle)

                if organizationRoles.isEmpty {
                    Text(AppStrings.UserManagement.organizationRolesEmpty)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                } else {
                    ForEach(organizationRoles) { item in
                        let organization = item.organization
                        HStack(spacing: AppTheme.eventsMetadataSpacing) {
                            Image(systemName: roleIcon(item.role))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.accentPrimaryForeground)
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(organization.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AppTheme.textPrimary)

                                Text(roleTitle(item.role))
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }

                            Spacer(minLength: 0)

                            Button {
                                pendingRoleRemoval = organization
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(AppTheme.accentDestructiveForeground)
                                    .frame(
                                        width: AppTheme.minimumInteractiveTarget,
                                        height: AppTheme.minimumInteractiveTarget
                                    )
                            }
                            .accessibilityLabel(AppStrings.UserManagement.removeOrganizationRoleButton)
                            .disabled(
                                actor.map { !viewModel.canManageOrganizationRoles(in: organization, actor: $0) } ?? true
                                    || item.role == .communityOwner
                                    || isUpdating
                            )
                        }
                    }
                }
            }
        }
    }

    private var platformRolesCard: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                SectionHeaderBlock(
                    title: AppStrings.UserManagement.platformRolesTitle,
                    subtitle: AppStrings.UserManagement.platformRolesSubtitle
                )

                if isUpdating {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                platformRoleStatusRow(
                    systemImage: platformRoleIcon,
                    title: AppStrings.UserManagement.currentPlatformRole,
                    value: user.globalRole.title,
                    tint: platformRoleTint
                )

                if PermissionService.hasOwnerRoleForDisplay(user: user) {
                    Text(AppStrings.UserManagement.ownerRoleImmutableNotice)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                } else if actor?.id == user.id {
                    Text(AppStrings.UserManagement.selfRoleChangeNotice)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                VStack(spacing: 8) {
                    if canShowAppAdminRoleControls {
                        roleActionButton(.assignAppAdmin, isEnabled: canAssignAppAdmin)
                        roleActionButton(.removeAppAdmin, isEnabled: canRemoveAppAdmin)
                    }
                }

                if securityMetadata?.emailVerified == false,
                   user.globalRole.authorizationRole != .admin {
                    Label(AppStrings.UserManagement.organizationRoleTargetEmailUnverified, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var roleAssignmentCard: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                SectionHeaderBlock(
                    title: AppStrings.UserManagement.assignRoleSectionTitle,
                    subtitle: AppStrings.UserManagement.assignRoleSectionSubtitle
                )

                HStack(spacing: AppTheme.eventsMetadataSpacing) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AppTheme.textSecondary)

                    TextField(AppStrings.UserManagement.organizationSearchPlaceholder, text: $organizationSearchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.subheadline)
                        .focused($focusedField, equals: .organizationSearch)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }

                    if !organizationSearchText.isEmpty {
                        AppSearchClearButton {
                            organizationSearchText = ""
                        }
                    }
                }
                .padding(.horizontal, AppTheme.inputHorizontalPadding)
                .frame(minHeight: AppTheme.searchControlHeight)
                .background(AppTheme.surfaceControl.opacity(0.45), in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                        .strokeBorder(AppTheme.borderSubtle)
                )
                .disabled(assignmentOrganizations.isEmpty)

                Picker(AppStrings.UserManagement.organizationPicker, selection: Binding(
                    get: { selectedOrganizationID ?? assignmentOrganizations.first?.id ?? "" },
                    set: { selectedOrganizationID = $0 }
                )) {
                    ForEach(filteredOrganizations) { organization in
                        Text(organization.name).tag(organization.id)
                    }
                }
                .pickerStyle(.menu)
                .disabled(filteredOrganizations.isEmpty)

                if assignmentOrganizations.isEmpty {
                    Text(AppStrings.UserManagement.roleAssignmentUnavailable)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                } else if filteredOrganizations.isEmpty {
                    Text(AppStrings.UserManagement.organizationsNotFound)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Picker(AppStrings.UserManagement.rolePicker, selection: $selectedRole) {
                    ForEach(assignableRoles, id: \.self) { role in
                        Text(roleTitle(role)).tag(role)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!canManageSelectedOrganizationRoles || selectedOrganization?.ownerId == user.id)

                if selectedOrganization?.ownerId == user.id {
                    Text(AppStrings.UserManagement.ownerTransferOnly)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                TextField(AppStrings.UserManagement.requiredReasonPlaceholder, text: $roleReason, axis: .vertical)
                    .lineLimit(2...4)
                    .font(.subheadline)
                    .padding(AppTheme.inputHorizontalPadding)
                    .background(AppTheme.surfaceControl.opacity(0.36), in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
                    .focused($focusedField, equals: .roleReason)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
                    .disabled(!canManageSelectedOrganizationRoles || selectedOrganization?.ownerId == user.id)

                if let roleAssignmentBlockingMessage {
                    Label(roleAssignmentBlockingMessage, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                PrimaryActionButton(
                    title: selectedRole == .communityOwner ? AppStrings.UserManagement.changeOwnerButton : AppStrings.UserManagement.assignRoleButton,
                    isEnabled: canManageSelectedOrganizationRoles && canAssignSelectedOrganizationRole && roleAssignmentBlockingMessage == nil,
                    isLoading: isUpdating,
                    systemImage: selectedRole == .communityOwner ? "person.crop.circle.badge.checkmark" : "person.badge.key"
                ) {
                    guard let selectedOrganization else { return }
                    guard let actor else { return }
                    let currentUser = user
                    let submittedReason = roleReason
                    let submittedRole = selectedRole
                    if submittedRole == .communityOwner {
                        pendingOwnershipTransfer = PendingOwnershipTransfer(
                            organization: selectedOrganization,
                            target: currentUser,
                            reason: submittedReason
                        )
                    } else {
                        Task {
                            await viewModel.assignRole(submittedRole, in: selectedOrganization, to: currentUser, actor: actor, reason: submittedReason)
                            if viewModel.statusMessage == AppStrings.UserManagement.changesSaved {
                                roleReason = ""
                            }
                        }
                    }
                }
            }
        }
    }

    private var accountActionsCard: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                SectionHeaderBlock(
                    title: AppStrings.UserManagement.accountActionsTitle,
                    subtitle: AppStrings.UserManagement.accountActionsSubtitle
                )

                ForEach(availableAccountActions) { action in
                    Button { pendingAction = action } label: {
                        actionLabel(action, tint: accountActionTint(action))
                    }
                    .disabled(!canManage || isUpdating)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var locationText: String {
        let region = user.selectedFederalState?.rawValue
        let locationParts: [String] = [user.city, region].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        return locationParts.isEmpty ? AppStrings.Common.notAvailable : locationParts.joined(separator: " · ")
    }

    private var statusTint: Color {
        switch user.blockState {
        case .active:
            AppTheme.accentPrimary
        case .warned:
            AppTheme.accentSupport
        case .suspendedUntil, .blocked, .bannedPermanent, .deactivated:
            AppTheme.accentDestructive
        }
    }

    private var platformRoleIcon: String {
        switch user.globalRole.authorizationRole {
        case .owner:
            "crown"
        case .admin:
            "person.badge.key"
        case .user, .topAdmin:
            "person"
        }
    }

    private var platformRoleTint: Color {
        switch user.globalRole.authorizationRole {
        case .owner:
            AppTheme.accentSupport
        case .admin:
            AppTheme.accentPrimary
        case .user, .topAdmin:
            AppTheme.textSecondary
        }
    }

    private var canChangePlatformRoles: Bool {
        guard let actor else { return false }
        return viewModel.canManagePlatformRole(target: user, actor: actor)
            && !isUpdating
            && !PermissionService.hasOwnerRoleForDisplay(user: user)
            && actor.id != user.id
    }

    private var canShowAppAdminRoleControls: Bool {
        guard let actor else { return false }
        return PermissionService.canAssignAppAdmin(user: actor)
    }

    private var canAssignAppAdmin: Bool {
        guard let actor else { return false }
        return canChangePlatformRoles
            && PermissionService.canAssignAppAdmin(user: actor)
            && securityMetadata?.emailVerified != false
            && user.globalRole.authorizationRole != .admin
    }

    private var canRemoveAppAdmin: Bool {
        guard let actor else { return false }
        return canChangePlatformRoles
            && PermissionService.canAssignAppAdmin(user: actor)
            && user.globalRole.authorizationRole == .admin
    }

    private func actionLabel(_ action: UserAdminAction, tint: Color) -> some View {
        Label(action.title, systemImage: action.systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .multilineTextAlignment(.center)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .frame(minHeight: AppTheme.iconButtonSize)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous))
    }

    private func accountActionTint(_ action: UserAdminAction) -> Color {
        switch action {
        case .warningIssued:
            AppTheme.accentSupport
        case .unblocked:
            AppTheme.accentPrimaryForeground
        case .suspended, .banned, .deactivated:
            AppTheme.accentDestructiveForeground
        }
    }

    private func roleActionButton(_ action: PlatformRoleAction, isEnabled: Bool) -> some View {
        Button {
            pendingPlatformRoleAction = action
        } label: {
            Label(action.title, systemImage: action.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(action.isRemoval ? AppTheme.accentDestructiveForeground : AppTheme.accentPrimaryForeground)
                .multilineTextAlignment(.center)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .frame(minHeight: AppTheme.iconButtonSize)
                .background(
                    (action.isRemoval ? AppTheme.accentDestructive : AppTheme.accentPrimary).opacity(0.10),
                    in: RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .overlay(alignment: .trailing) {
            if isUpdating && isEnabled {
                ProgressView()
                    .padding(.trailing, 12)
            }
        }
    }

    private func platformRoleStatusRow(
        systemImage: String,
        title: String,
        value: String,
        tint: Color
    ) -> some View {
        HStack(spacing: AppTheme.eventsMetadataSpacing) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 20)

            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)

            Spacer(minLength: 8)

            UserManagementStatusBadge(title: value, tint: tint)
        }
    }

    private func ensureSelectedOrganization(allowFilteredMatch: Bool = false) {
        let candidates = allowFilteredMatch ? filteredOrganizations : assignmentOrganizations
        if let selectedOrganizationID, candidates.contains(where: { $0.id == selectedOrganizationID }) {
            return
        }
        selectedOrganizationID = candidates.first?.id ?? assignmentOrganizations.first?.id
    }

    private func ensureSelectedRole() {
        guard !assignableRoles.contains(selectedRole) else { return }
        selectedRole = assignableRoles.first ?? .communityModerator
    }

    private func performOwnershipTransfer(_ transfer: PendingOwnershipTransfer) {
        guard let actor else { return }
        Task {
            await viewModel.changeOwner(
                in: transfer.organization,
                to: transfer.target,
                actor: actor,
                reason: transfer.reason
            )
            if viewModel.statusMessage == AppStrings.UserManagement.changesSaved {
                roleReason = ""
            }
        }
    }

    private func roleTitle(_ role: CommunityRole) -> String {
        switch role {
        case .communityOwner:
            AppStrings.Organizations.communityOwner
        case .communityAdmin:
            AppStrings.Organizations.communityAdmin
        case .communityModerator:
            AppStrings.Organizations.communityModerator
        case .member:
            AppStrings.Organizations.communityMember
        }
    }

    private func roleIcon(_ role: CommunityRole) -> String {
        switch role {
        case .communityOwner:
            "crown"
        case .communityAdmin:
            "person.badge.key"
        case .communityModerator:
            "shield"
        case .member:
            "person"
        }
    }
}

private struct UserAuditHistoryCard: View {
    let userId: String
    let refreshToken: Int
    @State private var items: [UserAuditHistoryItem] = []
    @State private var isLoading = false
    @State private var loadError = false
    @State private var canLoadMore = false
    @State private var lastDocument: QueryDocumentSnapshot?

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                SectionHeaderBlock(
                    title: AppStrings.UserManagement.auditHistoryTitle,
                    subtitle: AppStrings.UserManagement.auditHistorySubtitle
                )

                if isLoading && items.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if loadError && items.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(AppStrings.UserManagement.auditHistoryLoadError)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                        Button(AppStrings.UserManagement.retry) {
                            Task { await load(reset: true) }
                        }
                    }
                } else if items.isEmpty {
                    Text(AppStrings.UserManagement.auditHistoryEmpty)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                } else {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.textPrimary)

                                Spacer(minLength: 8)

                                Text(LocalizationStore.dateString(from: item.createdAt, dateStyle: .short, timeStyle: .short))
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }

                            Text(item.reason)
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                                .lineLimit(2)

                            if !item.performedBy.isEmpty {
                                Text(AppStrings.UserManagement.auditPerformedBy(item.performedBy))
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .textSelection(.enabled)
                            }

                            if let changeSummary = item.changeSummary {
                                Text(changeSummary)
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    if canLoadMore {
                        Button(AppStrings.UserManagement.loadMore) {
                            Task { await load(reset: false) }
                        }
                        .disabled(isLoading)
                    }
                }
            }
        }
        .task(id: "\(userId)|\(refreshToken)") {
            await load(reset: true)
        }
    }

    private func load(reset: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        loadError = false
        defer { isLoading = false }

        do {
            var query: Query = Firestore.firestore()
                .collection("auditLogs")
                .whereField("targetUserId", isEqualTo: userId)
                .order(by: "createdAt", descending: true)
                .limit(to: 20)
            if !reset, let lastDocument {
                query = query.start(afterDocument: lastDocument)
            }
            let snapshot = try await query.getDocuments()

            let newItems = snapshot.documents.map { document in
                let data = document.data()
                return UserAuditHistoryItem(
                    id: document.documentID,
                    actionType: data["actionType"] as? String ?? "unknown",
                    reason: data["reason"] as? String ?? "",
                    performedBy: data["performedBy"] as? String ?? "",
                    previousValue: data["previousValue"] as? [String: Any] ?? [:],
                    newValue: data["newValue"] as? [String: Any] ?? [:],
                    createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? .distantPast
                )
            }
            items = reset ? newItems : items + newItems
            lastDocument = snapshot.documents.last
            canLoadMore = snapshot.documents.count == 20
        } catch {
            loadError = true
            if reset {
                items = []
                lastDocument = nil
                canLoadMore = false
            }
        }
    }
}

private struct UserAuditHistoryItem: Identifiable {
    let id: String
    let actionType: String
    let reason: String
    let performedBy: String
    let previousValue: [String: Any]
    let newValue: [String: Any]
    let createdAt: Date

    var title: String {
        switch actionType {
        case "userWarned": AppStrings.UserManagement.actionWarn
        case "userSuspended": AppStrings.UserManagement.actionSuspend
        case "userBanned": AppStrings.UserManagement.actionBan
        case "userDeactivated": AppStrings.UserManagement.actionDeactivate
        case "userRestored": AppStrings.UserManagement.actionUnblock
        case "appAdminAssigned": AppStrings.UserManagement.assignAppAdmin
        case "appAdminRemoved": AppStrings.UserManagement.removeAppAdmin
        case "organizationRoleAssigned": AppStrings.UserManagement.assignRoleButton
        case "organizationRoleRemoved": AppStrings.UserManagement.removeOrganizationRoleButton
        case "organizationOwnerChanged": AppStrings.UserManagement.changeOwnerButton
        default: actionType
        }
    }

    var changeSummary: String? {
        let keys = ["accountStatus", "blockState", "globalRole", "role", "organizationId"]
        let changes = keys.compactMap { key -> String? in
            let previous = displayValue(previousValue[key])
            let next = displayValue(newValue[key])
            guard previous != next, previous != nil || next != nil else { return nil }
            return "\(key): \(previous ?? "—") → \(next ?? "—")"
        }
        return changes.isEmpty ? nil : changes.joined(separator: " · ")
    }

    private func displayValue(_ value: Any?) -> String? {
        switch value {
        case let string as String: string
        case let number as NSNumber: number.stringValue
        case nil: nil
        default: String(describing: value!)
        }
    }
}
