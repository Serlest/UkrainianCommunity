import Combine
import FirebaseFirestore
import Foundation

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

    init(response: ManagedUserSecurityMetadataFunctionResponse) {
        emailVerified = response.emailVerified
        authDisabled = response.authDisabled
        creationTime = response.creationTime.flatMap(Self.parseAuthDate)
        lastSignInTime = response.lastSignInTime.flatMap(Self.parseAuthDate)
        providerIDs = response.providerIds
    }

    nonisolated private static func parseAuthDate(_ value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Firebase Admin UserMetadata uses Date.toUTCString(), not ISO 8601.
        let firebaseDate = DateFormatter()
        firebaseDate.locale = Locale(identifier: "en_US_POSIX")
        firebaseDate.calendar = Calendar(identifier: .gregorian)
        firebaseDate.timeZone = TimeZone(secondsFromGMT: 0)
        firebaseDate.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = firebaseDate.date(from: trimmed) {
            return date
        }

        // Also accept ISO timestamps if the callable's serialization changes.
        let isoDate = ISO8601DateFormatter()
        if let date = isoDate.date(from: trimmed) {
            return date
        }
        isoDate.formatOptions.insert(.withFractionalSeconds)
        return isoDate.date(from: trimmed)
    }
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

    private lazy var db = Firestore.firestore()
    private lazy var roleManagementService: OrganizationRoleManagementService = suppliedRoleManagementService ?? FirestoreOrganizationRoleManagementService()
    private let suppliedRoleManagementService: OrganizationRoleManagementService?
    private let reads: UserManagementReads
    private var refreshRevision = 0
    private var sessionRevision = 0
    private var detailRevisions: [String: Int] = [:]
    private var metadataRevisions: [String: Int] = [:]
    private var organizationsRevision = 0
    private let pageSize = 40
    private var loadedActorKey: String?
    private var lastUserDocument: QueryDocumentSnapshot?
    private var searchGeneration = 0

    private var usersCollection: CollectionReference { db.collection("users") }
    private var organizationsCollection: CollectionReference { db.collection("organizations") }

    init(roleManagementService: OrganizationRoleManagementService? = nil, reads: UserManagementReads? = nil) {
        self.suppliedRoleManagementService = roleManagementService
        self.reads = reads ?? .live
    }

    func load(actor: AppUser?) async {
        let actorKey = managementActorKey(for: actor)
        guard loadedActorKey != actorKey || users.isEmpty else { return }
        await refresh(actor: actor)
    }

    func refresh(actor: AppUser?) async {
        let actorKey = managementActorKey(for: actor)
        if loadedActorKey != actorKey { reset(for: actorKey) }
        guard PermissionService.canManageUsers(user: actor) else { return }
        refreshRevision &+= 1
        isLoadingMore = false
        let revision = refreshRevision
        let session = sessionRevision
        isLoading = true
        error = nil
        defer { if revision == refreshRevision { isLoading = false } }

        async let roles: Void = refreshOrganizations(session: session)
        do {
            let page = try await RefreshRequest.run { [reads, pageSize] in
                try await reads.users(pageSize)
            }
            guard session == sessionRevision, revision == refreshRevision, !Task.isCancelled else { return }
            users = page.users
            lastUserDocument = page.cursor
            canLoadMore = page.hasMore
        } catch {
            guard session == sessionRevision, revision == refreshRevision, !Task.isCancelled else { return }
            self.error = .network
        }
        await roles
    }

    private func refreshOrganizations(session: Int) async {
        guard session == sessionRevision, !Task.isCancelled else { return }
        organizationsRevision &+= 1
        let revision = organizationsRevision
        do {
            let refreshed = try await RefreshRequest.run { [reads] in try await reads.organizations() }
            guard session == sessionRevision, revision == organizationsRevision, !Task.isCancelled else { return }
            organizations = refreshed
        } catch {
            guard session == sessionRevision, revision == organizationsRevision, !Task.isCancelled else { return }
            // Keep the last successful role data; a failed read must not erase the screen.
            self.error = .network
        }
    }

    func loadMore(actor: AppUser?) async {
        guard PermissionService.canManageUsers(user: actor),
              managementActorKey(for: actor) == loadedActorKey,
              canLoadMore,
              !isLoading,
              !isLoadingMore,
              let lastUserDocument else { return }

        let revision = refreshRevision
        let session = sessionRevision
        isLoadingMore = true
        defer { if revision == refreshRevision { isLoadingMore = false } }

        do {
            let snapshot = try await RefreshRequest.run { [self] in
                try await usersCollection.order(by: "createdAt", descending: true)
                    .start(afterDocument: lastUserDocument).limit(to: pageSize).getDocuments(source: .server)
            }
            guard session == sessionRevision, revision == refreshRevision, !Task.isCancelled else { return }

            let existingIDs = Set(users.map(\.id))
            users.append(contentsOf: snapshot.documents.map(Self.makeUser(from:)).filter { !existingIDs.contains($0.id) })
            self.lastUserDocument = snapshot.documents.last
            canLoadMore = snapshot.documents.count == pageSize
        } catch {
            guard session == sessionRevision, revision == refreshRevision, !Task.isCancelled else { return }
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
            let response = try await RefreshRequest.run {
                try await CloudFunctionsClient.shared.searchManagedUsers(query: trimmedQuery)
            }
            guard generation == searchGeneration, !Task.isCancelled else { return }

            var usersByID: [String: AppUser] = [:]
            for userIDs in response.userIds.chunked(into: 30) where !userIDs.isEmpty {
                let snapshot = try await RefreshRequest.run { [self] in
                    try await usersCollection.whereField(FieldPath.documentID(), in: Array(userIDs))
                        .getDocuments(source: .server)
                }
                guard generation == searchGeneration, !Task.isCancelled else { return }
                for document in snapshot.documents {
                    usersByID[document.documentID] = Self.makeUser(from: document)
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
        guard PermissionService.canManageUsers(user: actor), managementActorKey(for: actor) == loadedActorKey else { return }
        let session = sessionRevision
        metadataRevisions[userID, default: 0] &+= 1
        let revision = metadataRevisions[userID]
        do {
            let metadata = try await RefreshRequest.run { [reads] in try await reads.securityMetadata(userID) }
            guard session == sessionRevision, revision == metadataRevisions[userID], !Task.isCancelled else { return }
            securityMetadataByUserID[userID] = metadata
        } catch {
            guard session == sessionRevision, revision == metadataRevisions[userID], !Task.isCancelled else { return }
            self.error = .network
        }
    }

    func loadPresence(userID: String) async throws -> ManagedUserPresenceSnapshot {
        try await reads.presence(userID)
    }

    func securityMetadata(for userID: String) -> ManagedUserSecurityMetadata? {
        securityMetadataByUserID[userID]
    }

    func refreshDetail(userID: String, actor: AppUser?) async {
        guard let actor, PermissionService.canManageUsers(user: actor),
              managementActorKey(for: actor) == loadedActorKey else { return }
        error = nil
        // Keep list, search and pagination intact while refreshing this destination.
        async let user: Void = reloadUser(id: userID, actor: actor, afterMutation: false)
        async let metadata: Void = loadSecurityMetadata(userID: userID, actor: actor)
        async let roles: Void = refreshOrganizations(session: sessionRevision)
        _ = await (user, metadata, roles)
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
        users.first { $0.id == id } ?? searchResults.first { $0.id == id }
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

    private func reloadUser(id: String, actor: AppUser, afterMutation: Bool = true) async {
        guard managementActorKey(for: actor) == loadedActorKey else { return }
        let session = sessionRevision
        detailRevisions[id, default: 0] &+= 1
        let revision = detailRevisions[id]
        do {
            let refreshedUser = try await RefreshRequest.run { [reads] in try await reads.user(id) }
            guard session == sessionRevision, revision == detailRevisions[id], !Task.isCancelled else { return }
            guard let refreshedUser else { self.error = .notFound; return }
            if let index = users.firstIndex(where: { $0.id == id }) { users[index] = refreshedUser }
            else { users.append(refreshedUser) }
            if let index = searchResults.firstIndex(where: { $0.id == id }) { searchResults[index] = refreshedUser }
        } catch {
            guard session == sessionRevision, revision == detailRevisions[id], !Task.isCancelled else { return }
            self.error = .network
            if afterMutation { statusMessage = AppStrings.UserManagement.changesSavedRefreshFailed }
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
            let refreshedOrganization = Self.makeManagedOrganization(id: document.documentID, data: data)
            if let index = organizations.firstIndex(where: { $0.id == id }) {
                organizations[index] = refreshedOrganization
            } else {
                organizations.append(refreshedOrganization)
                organizations.sort {
                    let result = LocalizationStore.compareForSorting($0.name, $1.name)
                    return result == .orderedSame ? $0.id < $1.id : result == .orderedAscending
                }
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

        if message.contains("owner account status cannot be changed")
            || message.contains("app owner accounts cannot be changed")
            || message.contains("owner role cannot be changed") {
            return AppStrings.UserManagement.platformRoleTargetOwnerProtected
        }
        if message.contains("only the app owner can change an app admin") {
            return AppStrings.UserManagement.platformRolePermissionDenied
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

    static func makeUser(from document: QueryDocumentSnapshot) -> AppUser {
        Self.makeUser(id: document.documentID, data: document.data())
    }

    static func makeUser(id: String, data: [String: Any]) -> AppUser {
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

    static func makeManagedOrganization(from document: QueryDocumentSnapshot) -> ManagedOrganization {
        Self.makeManagedOrganization(id: document.documentID, data: document.data())
    }

    static func makeManagedOrganization(id: String, data: [String: Any]) -> ManagedOrganization {
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

    static func uniqueOrganizationDocuments(_ documents: [QueryDocumentSnapshot]) -> [QueryDocumentSnapshot] {
        var seenIDs = Set<String>()
        return documents.filter { seenIDs.insert($0.documentID).inserted }
    }

    private func managementActorKey(for actor: AppUser?) -> String? {
        guard let actor, PermissionService.canManageUsers(user: actor) else { return nil }
        return "\(actor.id)|\(actor.globalRole.authorizationRole.rawValue)"
    }

    private func reset(for actorKey: String?) {
        loadedActorKey = actorKey
        sessionRevision &+= 1
        refreshRevision &+= 1
        isLoading = false
        isLoadingMore = false
        detailRevisions = [:]
        users = []
        organizations = []
        error = nil
        canLoadMore = false
        lastUserDocument = nil
        clearSearch()
        securityMetadataByUserID = [:]
    }

}

