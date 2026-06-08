import Combine
import FirebaseFirestore
import SwiftUI

private enum UserManagementFilter: CaseIterable, Identifiable {
    case all
    case active
    case warned
    case suspended
    case banned

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
        }
    }

    func matches(_ user: AppUser) -> Bool {
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
        }
    }
}

private enum UserAdminAction: String {
    case warningIssued
    case suspended
    case banned
    case unblocked
    case deactivated

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
}

private enum PlatformRoleAction: Identifiable {
    case assignAppAdmin
    case removeAppAdmin
    case assignAppModerator
    case removeAppModerator
    case assignGuideEditor
    case removeGuideEditor

    var id: String { title }

    var title: String {
        switch self {
        case .assignAppAdmin:
            AppStrings.UserManagement.assignAppAdmin
        case .removeAppAdmin:
            AppStrings.UserManagement.removeAppAdmin
        case .assignAppModerator:
            AppStrings.UserManagement.assignAppModerator
        case .removeAppModerator:
            AppStrings.UserManagement.removeAppModerator
        case .assignGuideEditor:
            AppStrings.UserManagement.assignGuideEditor
        case .removeGuideEditor:
            AppStrings.UserManagement.removeGuideEditor
        }
    }

    var systemImage: String {
        switch self {
        case .assignAppAdmin, .removeAppAdmin:
            "person.badge.key"
        case .assignAppModerator, .removeAppModerator:
            "shield"
        case .assignGuideEditor, .removeGuideEditor:
            "book"
        }
    }

    var isRemoval: Bool {
        switch self {
        case .removeAppAdmin, .removeAppModerator, .removeGuideEditor:
            true
        case .assignAppAdmin, .assignAppModerator, .assignGuideEditor:
            false
        }
    }

    var defaultReason: String {
        switch self {
        case .assignAppAdmin:
            "App admin assigned"
        case .removeAppAdmin:
            "App admin removed"
        case .assignAppModerator:
            "App moderator assigned"
        case .removeAppModerator:
            "App moderator removed"
        case .assignGuideEditor:
            "Guide editor assigned"
        case .removeGuideEditor:
            "Guide editor removed"
        }
    }
}

private struct ManagedOrganization: Identifiable, Hashable {
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

private struct UserOrganizationRole: Identifiable, Hashable {
    let organization: ManagedOrganization
    let role: CommunityRole

    var id: String { organization.id }
}

@MainActor
private final class UserManagementViewModel: ObservableObject {
    @Published private(set) var users: [AppUser] = []
    @Published private(set) var organizations: [ManagedOrganization] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: AppError?
    @Published var statusMessage: String?
    @Published private(set) var updatingUserIDs = Set<String>()

    private let db = Firestore.firestore()
    private let roleManagementService: OrganizationRoleManagementService
    private var hasLoaded = false

    private var usersCollection: CollectionReference { db.collection("users") }
    private var organizationsCollection: CollectionReference { db.collection("organizations") }

    init(roleManagementService: OrganizationRoleManagementService? = nil) {
        self.roleManagementService = roleManagementService ?? FirestoreOrganizationRoleManagementService()
    }

    func loadIfNeeded(actor: AppUser?) async {
        guard !hasLoaded else { return }
        await refresh(actor: actor)
    }

    func refresh(actor: AppUser?) async {
        guard PermissionService.canManageUsers(user: actor) else {
            users = []
            organizations = []
            hasLoaded = true
            return
        }

        isLoading = true
        error = nil
        defer {
            isLoading = false
            hasLoaded = true
        }

        do {
            async let usersSnapshotTask = usersCollection
                .order(by: "createdAt", descending: true)
                .getDocuments()
            async let approvedOrganizationsSnapshotTask = organizationsCollection
                .whereField("moderationStatus", isEqualTo: ModerationStatus.approved.rawValue)
                .getDocuments()
            async let reviewableOrganizationsSnapshotTask = organizationsCollection
                .whereField(
                    "moderationStatus",
                    in: [
                        ModerationStatus.pendingReview.rawValue,
                        ModerationStatus.needsRevision.rawValue,
                        ModerationStatus.rejected.rawValue
                    ]
                )
                .getDocuments()
            let (usersSnapshot, approvedOrganizationsSnapshot, reviewableOrganizationsSnapshot) = try await (
                usersSnapshotTask,
                approvedOrganizationsSnapshotTask,
                reviewableOrganizationsSnapshotTask
            )
            users = usersSnapshot.documents.map(makeUser(from:))
            organizations = uniqueOrganizationDocuments(
                approvedOrganizationsSnapshot.documents + reviewableOrganizationsSnapshot.documents
            )
                .map(makeManagedOrganization(from:))
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            self.error = .network
        }
    }

    func perform(_ action: UserAdminAction, target: AppUser, actor: AppUser, reason: String) async {
        guard canManage(target: target, actor: actor) else {
            statusMessage = AppStrings.UserManagement.statusPermissionDenied
            return
        }

        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalReason = trimmedReason.isEmpty ? "Owner action" : trimmedReason

        await updateUser(target, actor: actor, failureMessage: accountStatusFailureMessage(from:)) {
            switch action {
            case .warningIssued:
                _ = try await CloudFunctionsClient.shared.warnUser(userId: target.id, reason: finalReason)
            case .suspended:
                let suspendedUntil = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date().addingTimeInterval(7 * 24 * 60 * 60)
                _ = try await CloudFunctionsClient.shared.suspendUser(userId: target.id, until: suspendedUntil, reason: finalReason)
            case .banned:
                _ = try await CloudFunctionsClient.shared.banUser(userId: target.id, reason: finalReason)
            case .unblocked:
                _ = try await CloudFunctionsClient.shared.restoreUser(userId: target.id, reason: finalReason)
            case .deactivated:
                _ = try await CloudFunctionsClient.shared.deactivateUser(userId: target.id, reason: finalReason)
            }
        }
    }

    func assignRole(_ role: CommunityRole, in organization: ManagedOrganization, to target: AppUser, actor: AppUser, reason: String) async {
        guard canManageOrganizationRoles(target: target, actor: actor) else {
            statusMessage = AppStrings.UserManagement.rolePermissionDenied
            return
        }

        if role == .communityOwner {
            await changeOwner(in: organization, to: target, actor: actor, reason: reason)
            return
        }

        guard role != .member else { return }

        await updateUser(target, actor: actor) {
            try await updateOrganizationRole(
                role: role,
                organization: organization,
                target: target,
                actor: actor,
                reason: reason,
                isRemoval: false
            )
        }
    }

    func changeOwner(in organization: ManagedOrganization, to target: AppUser, actor: AppUser, reason: String) async {
        guard canManage(target: target, actor: actor), PermissionService.canInitiateOwnershipTransferWorkflow(user: actor) else {
            statusMessage = AppStrings.UserManagement.ownerChangePermissionDenied
            return
        }

        guard organization.ownerId != target.id else {
            statusMessage = AppStrings.UserManagement.ownerChangeSelectNewOwner
            return
        }

        await updateUser(target, actor: actor) {
            try await updateOrganizationOwner(
                organization: organization,
                newOwner: target,
                actor: actor,
                reason: reason
            )
        }
    }

    func removeRole(in organization: ManagedOrganization, from target: AppUser, actor: AppUser, reason: String) async {
        guard canManageOrganizationRoles(target: target, actor: actor) else {
            statusMessage = AppStrings.UserManagement.removeRolePermissionDenied
            return
        }

        await updateUser(target, actor: actor) {
            try await updateOrganizationRole(
                role: .member,
                organization: organization,
                target: target,
                actor: actor,
                reason: reason,
                isRemoval: true
            )
        }
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
        let finalReason = trimmedReason.isEmpty ? action.defaultReason : trimmedReason

        await updateUser(target, actor: actor, failureMessage: platformRoleFailureMessage(from:)) {
            switch action {
            case .assignAppAdmin:
                _ = try await CloudFunctionsClient.shared.assignAppAdmin(userId: target.id, reason: finalReason)
            case .removeAppAdmin:
                _ = try await CloudFunctionsClient.shared.removeAppAdmin(userId: target.id, reason: finalReason)
            case .assignAppModerator:
                _ = try await CloudFunctionsClient.shared.assignAppModerator(userId: target.id, reason: finalReason)
            case .removeAppModerator:
                _ = try await CloudFunctionsClient.shared.removeAppModerator(userId: target.id, reason: finalReason)
            case .assignGuideEditor:
                _ = try await CloudFunctionsClient.shared.assignGuideEditor(userId: target.id, reason: finalReason)
            case .removeGuideEditor:
                _ = try await CloudFunctionsClient.shared.removeGuideEditor(userId: target.id, reason: finalReason)
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

    func canManageOrganizationRoles(target: AppUser, actor: AppUser) -> Bool {
        PermissionService.canManageUserTarget(actor: actor, target: target)
            && PermissionService.canInitiateOrganizationRoleWorkflow(user: actor)
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
            await refresh(actor: actor)
        } catch {
            self.error = .permissionDenied
            statusMessage = failureMessage?(error) ?? AppStrings.UserManagement.changesFailed
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
        let data = document.data()
        let legacyRole = UserRole(rawValue: data["role"] as? String ?? "") ?? .user
        let globalRole = (data["globalRole"] as? String).flatMap(GlobalRole.init(rawValue:)) ?? .user
        let isBlocked = data["isBlocked"] as? Bool ?? false
        let blockState = UserBlockState(rawValue: data["blockState"] as? String ?? "") ?? (isBlocked ? .suspendedUntil : .active)
        return AppUser(
            id: data["id"] as? String ?? document.documentID,
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
            canManageGuide: data["canManageGuide"] as? Bool ?? false,
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

    private func uniqueOrganizationDocuments(_ documents: [QueryDocumentSnapshot]) -> [QueryDocumentSnapshot] {
        var seenIDs = Set<String>()
        return documents.filter { document in
            seenIDs.insert(document.documentID).inserted
        }
    }

    private func makeManagedOrganization(from document: QueryDocumentSnapshot) -> ManagedOrganization {
        let data = document.data()
        return ManagedOrganization(
            id: document.documentID,
            name: data["name"] as? String ?? document.documentID,
            city: data["city"] as? String ?? "",
            logoURL: data["logoURL"] as? String ?? data["imageURL"] as? String,
            ownerId: data["ownerId"] as? String,
            adminIds: data["adminIds"] as? [String] ?? [],
            moderatorIds: data["moderatorIds"] as? [String] ?? []
        )
    }


}

struct UserManagementView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel = UserManagementViewModel()
    @State private var searchText = ""
    @State private var selectedFilter: UserManagementFilter = .all
    @FocusState private var isSearchFocused: Bool

    private var actor: AppUser? { authState.user }
    private var canAccessUserManagement: Bool {
        PermissionService.canManageUsers(user: actor)
    }

    private var filteredUsers: [AppUser] {
        viewModel.users.filter { user in
            selectedFilter.matches(user) && matchesSearch(user)
        }
    }

    var body: some View {
        AdminScreenShell(
            title: AppStrings.UserManagement.title,
            subtitle: AppStrings.UserManagement.contentSubtitle,
            tabBarHidden: false
        ) {
            userManagementContent
        }
        .task {
            await viewModel.loadIfNeeded(actor: actor)
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
            HStack(spacing: AppTheme.eventsMetadataSpacing) {
                Label("\(viewModel.users.count)", systemImage: "person.3")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(AppStrings.UserManagement.registeredUsers)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)

                Spacer(minLength: 0)

                if viewModel.isLoading {
                    ProgressView()
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

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AppTheme.inputHorizontalPadding)
        .frame(height: AppTheme.searchControlHeight)
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
                        title: filter.title,
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
        if viewModel.isLoading && viewModel.users.isEmpty {
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
            UnifiedEmptyStateCard(
                systemImage: "person.crop.circle.badge.questionmark",
                title: AppStrings.UserManagement.noResultsTitle,
                message: AppStrings.UserManagement.noResultsMessage
            )
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
            }
        }
    }

    private func matchesSearch(_ user: AppUser) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }

        return [
            user.displayName,
            user.fullName,
            user.email,
            user.telegramUsername ?? "",
            user.id,
            user.city,
            user.selectedFederalState?.rawValue ?? ""
        ]
        .contains { $0.lowercased().contains(query) }
    }
}

private struct ManagedUserRow: View {
    let user: AppUser
    let organizationRoles: [UserOrganizationRole]

    var body: some View {
        AppEditorSectionCard {
            HStack(alignment: .center, spacing: 12) {
                UserAvatarView(user: user, size: 46)

                VStack(alignment: .leading, spacing: 6) {
                    Text(user.preferredDisplayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)

                    Text(secondaryLine)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        UserStatusBadge(title: user.blockState.title, tint: statusTint)

                        if !user.city.isEmpty {
                            UserStatusBadge(title: user.city, tint: AppTheme.textSecondary)
                        }

                        if let primaryOrganizationRole {
                            UserStatusBadge(title: primaryOrganizationRole, tint: AppTheme.accentPrimary)
                        }

                        if organizationRoles.count > 1 {
                            UserStatusBadge(title: AppStrings.UserManagement.organizationRolesAdditionalCount(organizationRoles.count), tint: AppTheme.accentPrimary)
                        }
                    }
                }

                Spacer(minLength: 0)

                Text(LocalizationStore.dateString(from: user.createdAt, dateStyle: .short, timeStyle: .none))
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.trailing)
            }
        }
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
    case reason
}

private struct UserDetailView: View {
    let userID: String
    let fallbackUser: AppUser
    @ObservedObject var viewModel: UserManagementViewModel
    let actor: AppUser?

    @State private var selectedOrganizationID: String?
    @State private var selectedRole: CommunityRole = .communityModerator
    @State private var organizationSearchText = ""
    @State private var reason = ""
    @State private var pendingAction: UserAdminAction?
    @State private var pendingRoleRemoval: ManagedOrganization?
    @State private var pendingPlatformRoleAction: PlatformRoleAction?
    @FocusState private var focusedField: UserDetailFocusField?

    private var selectedOrganization: ManagedOrganization? {
        organizations.first { $0.id == selectedOrganizationID }
    }

    private var user: AppUser {
        viewModel.user(withID: userID) ?? fallbackUser
    }

    private var organizations: [ManagedOrganization] {
        viewModel.organizations
    }

    private var organizationRoles: [UserOrganizationRole] {
        viewModel.organizationRoles(for: user)
    }

    private var filteredOrganizations: [ManagedOrganization] {
        let query = organizationSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return organizations }

        return organizations.filter { organization in
            [organization.name, organization.city, organization.id]
                .contains { $0.lowercased().contains(query) }
        }
    }

    private var canAssignSelectedOrganizationRole: Bool {
        guard let selectedOrganization else { return false }
        let query = organizationSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty || filteredOrganizations.contains(where: { $0.id == selectedOrganization.id }) else {
            return false
        }
        if selectedRole == .communityOwner {
            return selectedOrganization.ownerId != user.id
        }
        return true
    }

    private var assignableRoles: [CommunityRole] {
        guard selectedOrganization?.ownerId != user.id else {
            return [.communityOwner]
        }
        return [.communityOwner, .communityAdmin, .communityModerator]
    }

    private var isUpdating: Bool {
        viewModel.updatingUserIDs.contains(userID)
    }

    private var canManage: Bool {
        actor.map { viewModel.canManage(target: user, actor: $0) } ?? false
    }

    private var canManageOrganizationRoles: Bool {
        actor.map { viewModel.canManageOrganizationRoles(target: user, actor: $0) } ?? false
    }

    var body: some View {
        PushedScreenShell(
            title: user.preferredDisplayName
        ) {
            AppGroupedContentPlane {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    profileCard
                    platformRolesCard
                    organizationRolesCard
                    if canManageOrganizationRoles && !organizations.isEmpty {
                        roleAssignmentCard
                    }
                    accountActionsCard
                    UserAuditHistoryCard(userId: user.id)
                }
            }
        }
        .contentShape(Rectangle())
        .refreshable {
            await viewModel.refresh(actor: actor)
            ensureSelectedOrganization()
            ensureSelectedRole()
        }
        .task {
            ensureSelectedOrganization()
            ensureSelectedRole()
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
        .confirmationDialog(
            pendingAction?.title ?? AppStrings.UserManagement.actionFallbackTitle,
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingAction {
                Button(pendingAction.title, role: pendingAction == .unblocked ? nil : .destructive) {
                    guard let actor else { return }
                    let currentUser = user
                    Task { await viewModel.perform(pendingAction, target: currentUser, actor: actor, reason: reason) }
                    reason = ""
                }
            }
            Button(AppStrings.Common.cancel, role: .cancel) {}
        } message: {
            Text(AppStrings.UserManagement.actionAuditNotice)
        }
        .confirmationDialog(
            AppStrings.UserManagement.removeOrganizationRoleTitle,
            isPresented: Binding(
                get: { pendingRoleRemoval != nil },
                set: { if !$0 { pendingRoleRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingRoleRemoval {
                Button(AppStrings.UserManagement.removeOrganizationRoleButton, role: .destructive) {
                    guard let actor else { return }
                    let currentUser = user
                    Task { await viewModel.removeRole(in: pendingRoleRemoval, from: currentUser, actor: actor, reason: reason) }
                    reason = ""
                }
            }
            Button(AppStrings.Common.cancel, role: .cancel) {}
        } message: {
            Text(AppStrings.UserManagement.removeOwnerRoleWarning)
        }
        .confirmationDialog(
            pendingPlatformRoleAction?.title ?? AppStrings.UserManagement.platformRoleActionFallbackTitle,
            isPresented: Binding(
                get: { pendingPlatformRoleAction != nil },
                set: { if !$0 { pendingPlatformRoleAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingPlatformRoleAction {
                Button(pendingPlatformRoleAction.title, role: pendingPlatformRoleAction.isRemoval ? .destructive : nil) {
                    guard let actor else { return }
                    let currentUser = user
                    Task {
                        await viewModel.performPlatformRoleAction(
                            pendingPlatformRoleAction,
                            target: currentUser,
                            actor: actor,
                            reason: reason
                        )
                    }
                    reason = ""
                }
            }
            Button(AppStrings.Common.cancel, role: .cancel) {}
        } message: {
            Text(AppStrings.UserManagement.platformRoleAuditNotice)
        }
    }

    private var profileCard: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                HStack(spacing: 12) {
                    UserAvatarView(user: user, size: 64)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(user.preferredDisplayName)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)

                        Text(user.email.isEmpty ? user.id : user.email)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            UserStatusBadge(title: user.blockState.title, tint: statusTint)
                            UserStatusBadge(title: user.globalRole.title, tint: PermissionService.hasOwnerRoleForDisplay(user: user) ? AppTheme.accentSupport : AppTheme.textSecondary)
                        }

                        if !organizationRoles.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(organizationRoles.prefix(3)) { item in
                                    UserStatusBadge(title: roleTitle(item.role), tint: AppTheme.accentPrimary)
                                }
                            }
                        }
                    }
                }

                Divider()

                UserManagementMetadataRow(systemImage: "number", title: "UID", value: user.id)
                UserManagementMetadataRow(systemImage: "at", title: "Telegram", value: user.telegramUsername ?? AppStrings.Common.notAvailable)
                UserManagementMetadataRow(systemImage: "mappin.and.ellipse", title: AppStrings.UserManagement.cityRegion, value: locationText)
                UserManagementMetadataRow(systemImage: "calendar", title: "Joined", value: LocalizationStore.dateString(from: user.createdAt, dateStyle: .medium, timeStyle: .none))
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
                                .foregroundStyle(AppTheme.accentPrimary)
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
                                    .foregroundStyle(AppTheme.accentDestructive)
                            }
                            .disabled(!canManageOrganizationRoles || item.role == .communityOwner || isUpdating)
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

                VStack(alignment: .leading, spacing: 8) {
                    platformRoleStatusRow(
                        systemImage: platformRoleIcon,
                        title: AppStrings.UserManagement.currentPlatformRole,
                        value: user.globalRole.title,
                        tint: platformRoleTint
                    )

                    platformRoleStatusRow(
                        systemImage: "book",
                        title: AppStrings.UserManagement.guideEditorRole,
                        value: user.canManageGuide ? AppStrings.UserManagement.guideEditorEnabled : AppStrings.UserManagement.guideEditorDisabled,
                        tint: user.canManageGuide ? AppTheme.accentPrimary : AppTheme.textSecondary
                    )
                }

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
                    roleActionButton(.assignAppModerator, isEnabled: canAssignAppModerator)
                    roleActionButton(.removeAppModerator, isEnabled: canRemoveAppModerator)
                    roleActionButton(.assignGuideEditor, isEnabled: canAssignGuideEditor)
                    roleActionButton(.removeGuideEditor, isEnabled: canRemoveGuideEditor)
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
                        Button {
                            organizationSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, AppTheme.inputHorizontalPadding)
                .frame(height: AppTheme.searchControlHeight)
                .background(AppTheme.surfaceControl.opacity(0.45), in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                        .strokeBorder(AppTheme.borderSubtle)
                )
                .disabled(organizations.isEmpty || !canManageOrganizationRoles)

                Picker(AppStrings.UserManagement.organizationPicker, selection: Binding(
                    get: { selectedOrganizationID ?? organizations.first?.id ?? "" },
                    set: { selectedOrganizationID = $0 }
                )) {
                    ForEach(filteredOrganizations) { organization in
                        Text(organization.name).tag(organization.id)
                    }
                }
                .pickerStyle(.menu)
                .disabled(filteredOrganizations.isEmpty || !canManageOrganizationRoles)

                if organizations.isEmpty {
                    Text(AppStrings.UserManagement.organizationsNotLoaded)
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
                .disabled(!canManageOrganizationRoles)

                if selectedOrganization?.ownerId == user.id {
                    Text(AppStrings.UserManagement.ownerTransferOnly)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                TextField(AppStrings.UserManagement.reasonPlaceholder, text: $reason, axis: .vertical)
                    .lineLimit(2...4)
                    .font(.subheadline)
                    .padding(AppTheme.inputHorizontalPadding)
                    .background(AppTheme.surfaceControl.opacity(0.36), in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
                    .focused($focusedField, equals: .reason)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }

                PrimaryActionButton(
                    title: selectedRole == .communityOwner ? AppStrings.UserManagement.changeOwnerButton : AppStrings.UserManagement.assignRoleButton,
                    isEnabled: canManageOrganizationRoles && canAssignSelectedOrganizationRole,
                    isLoading: isUpdating,
                    systemImage: selectedRole == .communityOwner ? "person.crop.circle.badge.checkmark" : "person.badge.key"
                ) {
                    guard let selectedOrganization else { return }
                    guard let actor else { return }
                    let currentUser = user
                    if selectedRole == .communityOwner {
                        Task { await viewModel.changeOwner(in: selectedOrganization, to: currentUser, actor: actor, reason: reason) }
                    } else {
                        Task { await viewModel.assignRole(selectedRole, in: selectedOrganization, to: currentUser, actor: actor, reason: reason) }
                    }
                    reason = ""
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

                Button { pendingAction = .warningIssued } label: {
                    actionLabel(.warningIssued, tint: AppTheme.accentSupport)
                }
                .disabled(!canManage || isUpdating)

                Button { pendingAction = .suspended } label: {
                    actionLabel(.suspended, tint: AppTheme.accentDestructive)
                }
                .disabled(!canManage || isUpdating)

                Button { pendingAction = .banned } label: {
                    actionLabel(.banned, tint: AppTheme.accentDestructive)
                }
                .disabled(!canManage || isUpdating)

                Button { pendingAction = .unblocked } label: {
                    actionLabel(.unblocked, tint: AppTheme.accentPrimary)
                }
                .disabled(!canManage || isUpdating)

                Button { pendingAction = .deactivated } label: {
                    actionLabel(.deactivated, tint: AppTheme.accentDestructive)
                }
                .disabled(!canManage || isUpdating)
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
        case .moderator:
            "shield"
        case .user, .topAdmin, .appModerator:
            "person"
        }
    }

    private var platformRoleTint: Color {
        switch user.globalRole.authorizationRole {
        case .owner:
            AppTheme.accentSupport
        case .admin, .moderator:
            AppTheme.accentPrimary
        case .user, .topAdmin, .appModerator:
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
            && user.globalRole.authorizationRole != .admin
    }

    private var canRemoveAppAdmin: Bool {
        guard let actor else { return false }
        return canChangePlatformRoles
            && PermissionService.canAssignAppAdmin(user: actor)
            && user.globalRole.authorizationRole == .admin
    }

    private var canAssignAppModerator: Bool {
        guard let actor else { return false }
        return canChangePlatformRoles
            && PermissionService.canAssignAppModerator(user: actor)
            && user.globalRole.authorizationRole != .moderator
    }

    private var canRemoveAppModerator: Bool {
        guard let actor else { return false }
        return canChangePlatformRoles
            && PermissionService.canAssignAppModerator(user: actor)
            && user.globalRole.authorizationRole == .moderator
    }

    private var canAssignGuideEditor: Bool {
        guard let actor else { return false }
        return canChangePlatformRoles
            && PermissionService.canAssignGuideEditor(user: actor)
            && !user.canManageGuide
    }

    private var canRemoveGuideEditor: Bool {
        guard let actor else { return false }
        return canChangePlatformRoles
            && PermissionService.canAssignGuideEditor(user: actor)
            && user.canManageGuide
    }

    private func actionLabel(_ action: UserAdminAction, tint: Color) -> some View {
        Label(action.title, systemImage: action.systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: AppTheme.iconButtonSize)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous))
    }

    private func roleActionButton(_ action: PlatformRoleAction, isEnabled: Bool) -> some View {
        Button {
            pendingPlatformRoleAction = action
        } label: {
            Label(action.title, systemImage: action.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(action.isRemoval ? AppTheme.accentDestructive : AppTheme.accentPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: AppTheme.iconButtonSize)
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

            UserStatusBadge(title: value, tint: tint)
        }
    }

    private func ensureSelectedOrganization(allowFilteredMatch: Bool = false) {
        let candidates = allowFilteredMatch ? filteredOrganizations : organizations
        if let selectedOrganizationID, candidates.contains(where: { $0.id == selectedOrganizationID }) {
            return
        }
        selectedOrganizationID = candidates.first?.id ?? organizations.first?.id
    }

    private func ensureSelectedRole() {
        guard !assignableRoles.contains(selectedRole) else { return }
        selectedRole = assignableRoles.first ?? .communityModerator
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
    @State private var items: [UserAuditHistoryItem] = []
    @State private var isLoading = false

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                SectionHeaderBlock(
                    title: AppStrings.UserManagement.auditHistoryTitle,
                    subtitle: AppStrings.UserManagement.auditHistorySubtitle
                )

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if items.isEmpty {
                    Text(AppStrings.UserManagement.auditHistoryEmpty)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                } else {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.actionType)
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
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .task(id: userId) {
            await load()
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let snapshot = try await Firestore.firestore()
                .collection("auditLogs")
                .whereField("targetUserId", isEqualTo: userId)
                .order(by: "createdAt", descending: true)
                .limit(to: 20)
                .getDocuments()

            items = snapshot.documents.map { document in
                let data = document.data()
                return UserAuditHistoryItem(
                    id: document.documentID,
                    actionType: data["actionType"] as? String ?? "unknown",
                    reason: data["reason"] as? String ?? "",
                    createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? .distantPast
                )
            }
        } catch {
            items = []
        }
    }
}

private struct UserAuditHistoryItem: Identifiable {
    let id: String
    let actionType: String
    let reason: String
    let createdAt: Date
}

private struct UserAvatarView: View {
    let user: AppUser
    let size: CGFloat

    var body: some View {
        AvatarArtworkView(
            avatarURL: user.avatarURL,
            initials: user.initials,
            size: size,
            showsBorder: false,
            shadowOpacity: 0,
            shadowRadius: 0,
            shadowY: 0,
            initialsFont: .subheadline.weight(.semibold),
            placeholderFill: AppTheme.accentPrimary.opacity(0.12)
        )
    }
}

private struct UserStatusBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.10), in: Capsule())
            .lineLimit(1)
    }
}

private struct UserManagementMetadataRow: View {
    let systemImage: String
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(width: 18)

            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)

            Spacer(minLength: 8)

            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }
}
