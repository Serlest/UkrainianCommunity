import Combine
import CryptoKit
import FirebaseFunctions
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

enum PlatformRoleAction: String, Identifiable {
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

struct ManagedOrganization: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let city: String
    let logoURL: String?
    let ownerId: String?
    let adminIds: [String]
    let moderatorIds: [String]
    var accessRevision: String? = nil
    var moderationStatus: ModerationStatus? = nil

    func asOrganization() -> Organization {
        var value = Organization(
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
            moderationStatus: moderationStatus ?? .approved,
            likeCount: 0,
            likeState: .notLiked
        )
        value.accessRevision = accessRevision
        return value
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
    @Published private(set) var totalRegisteredUsers: Int?
    @Published private(set) var users: [AppUser] = []
    @Published private(set) var organizations: [ManagedOrganization] = [] {
        didSet { rebuildOrganizationRoleIndex() }
    }
    private var organizationRolesByUserID: [String: [UserOrganizationRole]] = [:]
    private var detailUsersByID: [String: AppUser] = [:]
    @Published private(set) var organizationsLoaded = false
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var isSearching = false
    @Published private(set) var searchResults: [AppUser] = []
    @Published private(set) var regionalNextCursor: String?
    private var regionalQuery: (text: String, region: String)?
    @Published private(set) var searchTotalMatches = 0
    @Published private(set) var searchFailed = false
    @Published private(set) var loadingSecurityUserIDs = Set<String>()
    @Published private(set) var failedSecurityUserIDs = Set<String>()
    @Published private(set) var securityMetadataByUserID: [String: ManagedUserSecurityMetadata] = [:]
    @Published private(set) var canLoadMore = false
    @Published private(set) var error: AppError?
    @Published var statusMessage: String?
    @Published private(set) var updatingUserIDs = Set<String>()
    @Published private(set) var sessionRevocationRetryActions: [String: UserAdminAction] = [:]
    @Published private(set) var mutationRevision = 0

    private lazy var db = Firestore.firestore()
    private lazy var roleManagementService: OrganizationRoleManagementService = suppliedRoleManagementService ?? FirestoreOrganizationRoleManagementService()
    private let suppliedRoleManagementService: OrganizationRoleManagementService?
    private let reads: UserManagementReads
    private let detailReadDeadline: RefreshRequest.Deadline
    private var refreshRevision = 0
    private var sessionRevision = 0
    private var detailRevisions: [String: Int] = [:]
    private var metadataRevisions: [String: Int] = [:]
    private var organizationsRevision = 0
    private let pageSize = 40
    private var loadedActorKey: String?
    private var lastUserDocument: QueryDocumentSnapshot?
    private var searchGeneration = 0
    private var adminMutationJournal = AdminUserMutationJournal()

    private var usersCollection: CollectionReference { db.collection("users") }
    private var organizationsCollection: CollectionReference { db.collection("organizations") }

    init(roleManagementService: OrganizationRoleManagementService? = nil, reads: UserManagementReads? = nil,
         detailReadDeadline: @escaping RefreshRequest.Deadline = RefreshRequest.continuousDeadline) {
        self.suppliedRoleManagementService = roleManagementService
        self.reads = reads ?? .live
        self.detailReadDeadline = detailReadDeadline
    }

    var usesDirectory: Bool { reads.directory != nil }
    @Published private(set) var directoryTotal = 0
    @Published private(set) var directoryCursor: String?
    private var directoryQuery: UserDirectoryQuery?
    private var directoryGeneration = UUID()
    @Published private(set) var organizationCursor: String?
    @Published private(set) var isLoadingOrganizations = false
    private var organizationQuery = ""
    private var organizationGeneration = UUID()

    @Published private(set) var directoryHasLoaded = false
    @Published private(set) var unavailableUserIDs = Set<String>()
    private var directoryRequest: Task<Void, Never>?
    private var directoryRequestKey: String?

    func isDirectoryCurrent(actor: AppUser?, query: UserDirectoryQuery) -> Bool {
        managementActorKey(for: actor) == loadedActorKey && directoryQuery == query
    }

    /// Preserve confirmed pages until a different actor/query is actually selected.
    func prepareDirectory() {
        isLoading = !directoryHasLoaded
    }

    func prepareDirectory(actor: AppUser?, query: UserDirectoryQuery) {
        let key = managementActorKey(for: actor)
        if key != loadedActorKey { reset(for: key) }
        guard key != nil else { return }
        if directoryQuery != query {
            directoryGeneration = UUID()
            directoryRequest?.cancel(); directoryRequest = nil; directoryRequestKey = nil
            directoryQuery = query; users = []; directoryCursor = nil; directoryTotal = 0
            directoryHasLoaded = false; error = nil; isLoadingMore = false
        }
        prepareDirectory()
    }

    func ensureDirectory(actor: AppUser?, query: UserDirectoryQuery) async {
        prepareDirectory(actor: actor, query: query)
        guard !directoryHasLoaded else { return }
        await loadDirectory(actor: actor, query: query)
    }

    func loadDirectory(actor: AppUser?, query: UserDirectoryQuery, more: Bool = false) async {
        prepareDirectory(actor: actor, query: query)
        let actorKey = managementActorKey(for: actor)
        guard let actor, actorKey != nil, let fetch = reads.directory else { return }
        let after = more ? directoryCursor : nil
        if more, after == nil { return }
        let requestKey = [actorKey!, query.search, query.region ?? "", query.filter, query.sort, after ?? "first"].joined(separator: "\u{0}")
        if let directoryRequest, requestKey == directoryRequestKey {
            await directoryRequest.value
            return
        }
        if more, directoryRequest != nil { return }
        directoryRequest?.cancel()
        directoryGeneration = UUID()
        let generation = directoryGeneration
        directoryRequestKey = requestKey
        if more { isLoadingMore = true } else { isLoading = true; isLoadingMore = false }
        error = nil
        let task = Task { [self] in
            defer {
                if generation == directoryGeneration {
                    isLoading = false; isLoadingMore = false
                    directoryRequest = nil; directoryRequestKey = nil
                }
            }
            do {
                let page = try await RefreshRequest.run { try await fetch(actor.id, query, after) }
                guard generation == directoryGeneration, actorKey == loadedActorKey, !Task.isCancelled else { return }
                var ids = Set(more ? users.map(\.id) : [])
                let newUsers = page.users.filter { ids.insert($0.id).inserted }
                users = more ? users + newUsers : newUsers
                for user in page.users { detailUsersByID.removeValue(forKey: user.id); unavailableUserIDs.remove(user.id) }
                for org in page.organizations {
                    if let i = organizations.firstIndex(where: { $0.id == org.id }) { organizations[i] = org }
                    else { organizations.append(org) }
                }
                organizationsLoaded = true; directoryHasLoaded = true
                directoryTotal = page.total; directoryCursor = page.cursor
                if query.search.isEmpty && query.region == nil && query.filter == "all" { totalRegisteredUsers = page.total }
                else if totalRegisteredUsers == nil { await refreshTotalCount(session: sessionRevision, revision: refreshRevision) }
            } catch is CancellationError {
                return
            } catch {
                guard generation == directoryGeneration, actorKey == loadedActorKey, !Task.isCancelled else { return }
                self.error = .network
            }
        }
        directoryRequest = task
        await task.value
    }

    func loadOrganizationChoices(actor: AppUser?, search: String = "", more: Bool = false) async {
        guard let actor, managementActorKey(for: actor) == loadedActorKey, let fetch = reads.organizationPage else { return }
        if more { guard !isLoadingOrganizations, organizationCursor != nil, search == organizationQuery else { return } }
        else { organizationGeneration = UUID(); organizationCursor = nil; organizationQuery = search; organizationChoices = [] }
        let generation = organizationGeneration, session = sessionRevision
        isLoadingOrganizations = true
        defer { if generation == organizationGeneration { isLoadingOrganizations = false } }
        do {
            let page = try await RefreshRequest.run { try await fetch(actor.id, search, more ? self.organizationCursor : nil) }
            guard generation == organizationGeneration, session == sessionRevision, !Task.isCancelled else { return }
            let ids = Set(organizationChoices.map(\.id)); organizationChoices += page.organizations.filter { !ids.contains($0.id) }
            organizationCursor = page.cursor; organizationsLoaded = true
        } catch { guard generation == organizationGeneration, session == sessionRevision else { return }; statusMessage = AppStrings.UserManagement.refreshFailed }
    }
    @Published private(set) var organizationChoices: [ManagedOrganization] = []

    func loadMemberships(userID: String, actor: AppUser?) async {
        guard let actor, managementActorKey(for: actor) == loadedActorKey, let fetch = reads.memberships else { return }
        let session = sessionRevision
        do {
            let items = try await RefreshRequest.run { try await fetch(actor.id, userID) }
            guard session == sessionRevision, !Task.isCancelled else { return }
            let refreshedIDs = Set(items.map(\.id))
            organizations.removeAll { $0.role(for: userID) != nil || refreshedIDs.contains($0.id) }
            organizations += items
            organizationsLoaded = true
        } catch { guard session == sessionRevision else { return }; self.error = .network }
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

        async let count: Void = refreshTotalCount(session: session, revision: revision)
        async let roles: Void = refreshOrganizations(session: session)
        do {
            let page = try await RefreshRequest.run { [reads, pageSize] in
                try await reads.users(pageSize)
            }
            guard session == sessionRevision, revision == refreshRevision, !Task.isCancelled else { return }
            users = page.users
            for user in page.users { detailUsersByID.removeValue(forKey: user.id) }
            lastUserDocument = page.cursor
            canLoadMore = page.hasMore
        } catch {
            guard session == sessionRevision, revision == refreshRevision, !Task.isCancelled else { return }
            self.error = .network
        }
        await roles
        await count
    }

    private func refreshTotalCount(session: Int, revision: Int) async {
        // Never replace a failed aggregate request with the first page's size.
        let count = try? await RefreshRequest.run { [reads] in try await reads.totalCount() }
        guard session == sessionRevision, revision == refreshRevision, !Task.isCancelled else { return }
        totalRegisteredUsers = count
    }

    private func refreshOrganizations(session: Int) async {
        guard session == sessionRevision, !Task.isCancelled else { return }
        organizationsRevision &+= 1
        let revision = organizationsRevision
        do {
            let refreshed = try await RefreshRequest.run { [reads] in try await reads.organizations() }
            guard session == sessionRevision, revision == organizationsRevision, !Task.isCancelled else { return }
            organizations = refreshed
            organizationsLoaded = true
        } catch {
            guard session == sessionRevision, revision == organizationsRevision, !Task.isCancelled else { return }
            organizationsLoaded = false
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

    func loadMoreRegional(actor: AppUser?) async {
        guard PermissionService.canManageUsers(user: actor), managementActorKey(for: actor) == loadedActorKey,
              let query = regionalQuery, let cursor = regionalNextCursor, !isSearching, !isLoadingMore else { return }
        let generation = searchGeneration
        isLoadingMore = true
        defer { if generation == searchGeneration { isLoadingMore = false } }
        do {
            let response = try await RefreshRequest.run { [reads] in try await reads.regionalSearch(query.text, query.region, cursor) }
            guard generation == searchGeneration, !Task.isCancelled else { return }
            let ids = Set(searchResults.map(\.id))
            searchResults += response.users.filter { !ids.contains($0.id) }
            searchTotalMatches = response.totalMatches
            regionalNextCursor = response.nextCursor
        } catch { guard generation == searchGeneration else { return }; statusMessage = AppStrings.UserManagement.loadMoreFailed }
    }

    func search(query: String, actor: AppUser?, region: String? = nil) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.count >= 2 || region != nil else {
            clearSearch()
            return
        }
        guard let actor, PermissionService.canManageUsers(user: actor), managementActorKey(for: actor) == loadedActorKey else {
            clearSearch()
            return
        }

        searchGeneration &+= 1
        let generation = searchGeneration
        regionalQuery = region.map { (trimmedQuery.count >= 2 ? trimmedQuery : "", $0) }
        regionalNextCursor = nil
        isSearching = true
        searchFailed = false
        defer {
            if generation == searchGeneration {
                isSearching = false
            }
        }

        do {
            let response = try await RefreshRequest.run { [reads] in
                if let region { return try await reads.regionalSearch(trimmedQuery.count >= 2 ? trimmedQuery : "", region, nil) }
                return try await reads.search(trimmedQuery)
            }
            guard generation == searchGeneration, !Task.isCancelled else { return }
            searchResults = response.users
            for user in response.users { detailUsersByID.removeValue(forKey: user.id) }
            searchTotalMatches = response.totalMatches
            regionalNextCursor = response.nextCursor
        } catch {
            guard generation == searchGeneration, !Task.isCancelled else { return }
            searchResults = []
            searchTotalMatches = 0
            searchFailed = true
        }
    }

    func prepareSearch() {
        clearSearch()
        isSearching = true
    }

    func clearSearch() {
        regionalQuery = nil
        regionalNextCursor = nil
        isLoadingMore = false
        searchGeneration &+= 1
        isSearching = false
        searchResults = []
        searchTotalMatches = 0
        searchFailed = false
    }

    func loadSecurityMetadata(userID: String, actor: AppUser?) async {
        guard PermissionService.canManageUsers(user: actor), managementActorKey(for: actor) == loadedActorKey else { return }
        guard !loadingSecurityUserIDs.contains(userID) else { return }
        loadingSecurityUserIDs.insert(userID)
        failedSecurityUserIDs.remove(userID)
        let session = sessionRevision
        defer { if session == sessionRevision { loadingSecurityUserIDs.remove(userID) } }
        metadataRevisions[userID, default: 0] &+= 1
        let revision = metadataRevisions[userID]
        do {
            let metadata = try await RefreshRequest.run { [reads] in try await reads.securityMetadata(userID) }
            guard session == sessionRevision, revision == metadataRevisions[userID], !Task.isCancelled else { return }
            securityMetadataByUserID[userID] = metadata
        } catch {
            guard session == sessionRevision, revision == metadataRevisions[userID], !Task.isCancelled else { return }
            failedSecurityUserIDs.insert(userID)
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
        async let roles: Void = usesDirectory ? loadMemberships(userID: userID, actor: actor) : refreshOrganizations(session: sessionRevision)
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

        let mutation = adminMutationJournal.request(actor: actor.id, target: target, action: action.rawValue, reason: trimmedReason, days: suspensionDays)
        await updateUser(
            target,
            actor: actor,
            failureMessage: accountStatusFailureMessage(from:),
            sessionRevocationAction: action
        ) {
            switch action {
            case .warningIssued:
                _ = try await CloudFunctionsClient.shared.warnUser(userId: target.id, reason: trimmedReason, review: mutation?.review)
            case .suspended:
                let suspendedUntil = mutation?.until ?? Date().addingTimeInterval(TimeInterval(suspensionDays * 86400))
                _ = try await CloudFunctionsClient.shared.suspendUser(userId: target.id, until: suspendedUntil, reason: trimmedReason, review: mutation?.review)
            case .banned:
                _ = try await CloudFunctionsClient.shared.banUser(userId: target.id, reason: trimmedReason, review: mutation?.review)
            case .unblocked:
                _ = try await CloudFunctionsClient.shared.restoreUser(userId: target.id, reason: trimmedReason, review: mutation?.review)
            case .deactivated:
                _ = try await CloudFunctionsClient.shared.deactivateUser(userId: target.id, reason: trimmedReason, review: mutation?.review)
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

        let mutation = adminMutationJournal.request(actor: actor.id, target: target, action: action.rawValue, reason: trimmedReason)
        await updateUser(target, actor: actor, failureMessage: platformRoleFailureMessage(from:)) {
            switch action {
            case .assignAppAdmin:
                _ = try await CloudFunctionsClient.shared.assignAppAdmin(userId: target.id, reason: trimmedReason, review: mutation?.review)
            case .removeAppAdmin:
                _ = try await CloudFunctionsClient.shared.removeAppAdmin(userId: target.id, reason: trimmedReason, review: mutation?.review)
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
        detailUsersByID[id] ?? users.first { $0.id == id } ?? searchResults.first { $0.id == id }
    }

    func organizationRoles(for user: AppUser) -> [UserOrganizationRole] {
        organizationRolesByUserID[user.id] ?? []
    }

    private func rebuildOrganizationRoleIndex() {
        var index: [String: [UserOrganizationRole]] = [:]
        for organization in organizations {
            let members = Set(([organization.ownerId].compactMap { $0 }) + organization.adminIds + organization.moderatorIds)
            for id in members {
                guard let role = organization.role(for: id) else { continue }
                index[id, default: []].append(UserOrganizationRole(organization: organization, role: role))
            }
        }
        organizationRolesByUserID = index
    }

    func sessionRevocationRetryAction(for userID: String) -> UserAdminAction? {
        sessionRevocationRetryActions[userID]
    }

    private func updateUser(_ target: AppUser, actor: AppUser, operation: () async throws -> Void) async {
        await updateUser(target, actor: actor, failureMessage: nil, operation: operation)
    }

    private func updateUser(
        _ target: AppUser,
        actor: AppUser,
        failureMessage: ((Error) -> String?)?,
        sessionRevocationAction: UserAdminAction? = nil,
        operation: () async throws -> Void
    ) async {
        guard !updatingUserIDs.contains(target.id) else { return }
        updatingUserIDs.insert(target.id)
        statusMessage = nil
        let session = sessionRevision
        defer { if session == sessionRevision { updatingUserIDs.remove(target.id) } }

        do {
            try await operation()
            guard session == sessionRevision else { return }
            if sessionRevocationAction != nil {
                sessionRevocationRetryActions.removeValue(forKey: target.id)
            }
            statusMessage = AppStrings.UserManagement.changesSaved
            mutationRevision &+= 1
            await reloadUser(id: target.id, actor: actor)
        } catch {
            guard session == sessionRevision else { return }
            if (error as NSError).domain == FunctionsErrorDomain && (error as NSError).code == FunctionsErrorCode.aborted.rawValue {
                await refreshDetail(userID: target.id, actor: actor)
                if session == sessionRevision { statusMessage = UserDirectoryCopy.changed }
                return
            }
            if Self.isCommittedSessionRevocationFailure(error) {
                if let sessionRevocationAction {
                    sessionRevocationRetryActions[target.id] = sessionRevocationAction
                }
                mutationRevision &+= 1
                await reloadUser(id: target.id, actor: actor, afterMutation: false)
                statusMessage = LocalizationStore.localizedString(
                    "user_management.account_status.session_revocation_failed",
                    defaultValue: "Обмеження збережено, але активні сесії не вдалося відкликати. Спробуйте дію ще раз."
                )
            } else {
                statusMessage = failureMessage?(error) ?? AppStrings.UserManagement.changesFailed
            }
        }
    }

    private static func isCommittedSessionRevocationFailure(_ error: Error) -> Bool {
        let failure = error as NSError
        if let details = failure.userInfo[FunctionsErrorDetailsKey] as? [String: Any],
           details["reason"] as? String == "session-revocation-failed",
           details["accountStatusCommitted"] as? Bool == true {
            return true
        }
        if let details = failure.userInfo[FunctionsErrorDetailsKey] as? NSDictionary,
           details["reason"] as? String == "session-revocation-failed",
           details["accountStatusCommitted"] as? Bool == true {
            return true
        }

        let message = failure.localizedDescription.lowercased()
        return message.contains("account restriction was saved")
            && message.contains("sessions could not be revoked")
    }

    private func reloadUser(id: String, actor: AppUser, afterMutation: Bool = true) async {
        guard managementActorKey(for: actor) == loadedActorKey else { return }
        let session = sessionRevision
        detailRevisions[id, default: 0] &+= 1
        let revision = detailRevisions[id]
        do {
            let refreshedUser = try await RefreshRequest.run(deadline: detailReadDeadline) { [reads] in try await reads.user(id) }
            guard session == sessionRevision, revision == detailRevisions[id], !Task.isCancelled else { return }
            guard let refreshedUser else {
                unavailableUserIDs.insert(id)
                detailUsersByID.removeValue(forKey: id)
                users.removeAll { $0.id == id }; searchResults.removeAll { $0.id == id }
                self.error = .notFound
                if afterMutation { statusMessage = AppStrings.UserManagement.changesSavedRefreshFailed }
                return
            }
            unavailableUserIDs.remove(id)
            if let index = users.firstIndex(where: { $0.id == id }) { users[index] = refreshedUser }
            detailUsersByID[id] = refreshedUser
            if let index = searchResults.firstIndex(where: { $0.id == id }) { searchResults[index] = refreshedUser }
        } catch {
            guard session == sessionRevision, revision == detailRevisions[id], !Task.isCancelled else { return }
            self.error = .network
            if afterMutation { statusMessage = AppStrings.UserManagement.changesSavedRefreshFailed }
        }
    }

    private func reloadOrganizationAfterSuccessfulMutation(id: String) async {
        guard statusMessage == AppStrings.UserManagement.changesSaved || statusMessage == UserDirectoryCopy.changed else { return }
        let session = sessionRevision
        do {
            let document = try await organizationsCollection.document(id).getDocument(source: .server)
            guard session == sessionRevision else { return }
            guard document.exists, let data = document.data() else {
                statusMessage = AppStrings.UserManagement.organizationMissing
                return
            }
            let refreshedOrganization = Self.makeManagedOrganization(id: document.documentID, data: data)
            if let index = organizationChoices.firstIndex(where: { $0.id == id }) { organizationChoices[index] = refreshedOrganization }
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
            guard session == sessionRevision else { return }
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

    static func adminReviewRevision(_ data: [String: Any]) -> String {
        func stamp(_ key: String) -> String { (data[key] as? Timestamp).map { "\($0.seconds):\($0.nanoseconds)" } ?? "" }
        var parts = ["globalRole", "accountStatus", "blockState"].map { data[$0] as? String ?? "" }
        parts += [String(data["warningCount"] as? Int ?? 0), (data["isBlocked"] as? Bool == true) ? "true" : "false", stamp("banExpiresAt"), stamp("statusUpdatedAt"), stamp("roleUpdatedAt")]
        return SHA256.hash(data: Data(parts.joined(separator: "\u{0}").utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func makeUser(from document: QueryDocumentSnapshot) -> AppUser {
        Self.makeUser(id: document.documentID, data: document.data())
    }

    static func makeUser(id: String, data: [String: Any], revision: String? = nil) -> AppUser {
        let legacyRole = UserRole(rawValue: data["role"] as? String ?? "") ?? .user
        let globalRole = (data["globalRole"] as? String).flatMap(GlobalRole.init(rawValue:)) ?? .user
        let isBlocked = data["isBlocked"] as? Bool ?? false
        let blockState = UserBlockState(rawValue: data["blockState"] as? String ?? "") ?? (isBlocked ? .suspendedUntil : .active)
        var result = AppUser(
            id: id,
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
        result.managementRevision = revision ?? adminReviewRevision(data)
        return result
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
            moderatorIds: data["moderatorIds"] as? [String] ?? [],
            accessRevision: (data["updatedAt"] as? Timestamp).map { "\($0.seconds):\($0.nanoseconds)" },
            moderationStatus: (data["moderationStatus"] as? String).flatMap(ModerationStatus.init(rawValue:))
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
        directoryGeneration = UUID(); directoryQuery = nil; directoryCursor = nil; directoryTotal = 0
        directoryRequest?.cancel(); directoryRequest = nil; directoryRequestKey = nil
        directoryHasLoaded = false; unavailableUserIDs = []
        organizationGeneration = UUID(); organizationChoices = []; organizationCursor = nil; isLoadingOrganizations = false
        sessionRevision &+= 1
        refreshRevision &+= 1
        isLoading = false
        isLoadingMore = false
        detailRevisions = [:]
        metadataRevisions = [:]
        statusMessage = nil
        updatingUserIDs = []
        sessionRevocationRetryActions = [:]
        users = []
        totalRegisteredUsers = nil
        organizations = []
        organizationsLoaded = false
        error = nil
        canLoadMore = false
        lastUserDocument = nil
        clearSearch()
        securityMetadataByUserID = [:]
        loadingSecurityUserIDs = []
        failedSecurityUserIDs = []
        detailUsersByID = [:]
    }

}

/// Presentation uses the more restrictive persisted field, including legacy profiles.
/// A stale blockState must never label a banned account as active.
extension AppUser {
    var managedAccountState: UserBlockState {
        let account: UserBlockState = switch accountStatus {
        case .active: .active
        case .warned: .warned
        case .suspendedUntil, .temporarilyBanned: .suspendedUntil
        case .bannedPermanent, .permanentlyBanned: .bannedPermanent
        case .deactivated: .deactivated
        }
        func rank(_ state: UserBlockState) -> Int {
            switch state {
            case .active: 0
            case .warned: 1
            case .suspendedUntil, .blocked: 2
            case .bannedPermanent: 3
            case .deactivated: 4
            }
        }
        return rank(account) > rank(blockState) ? account : blockState
    }
}
