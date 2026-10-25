import FirebaseFirestore
import SwiftUI

private enum UserDetailFocusField {
    case roleReason
}

private struct PendingUserReview<Action>: Identifiable {
    let id = UUID()
    let action: Action
    let target: AppUser
    let actor: AppUser
}

private struct PendingOwnershipTransfer: Identifiable {
    let organization: ManagedOrganization
    let target: AppUser
    let reason: String
    let actor: AppUser

    var id: String { "\(organization.id)|\(target.id)" }
}

struct UserDetailView: View {
    @EnvironmentObject private var authState: AuthState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var profileIdentityLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
    }
    let userID: String
    let fallbackUser: AppUser
    @ObservedObject var viewModel: UserManagementViewModel
    let actor: AppUser?

    @State private var selectedOrganizationID: String?
    @State private var selectedRole: CommunityRole = .communityModerator
    @State private var organizationSearchText = ""
    @State private var roleReason = ""
    @State private var historyRefresh = 0
    @State private var isChoosingOrganization = false
    @State private var pendingAction: PendingUserReview<UserAdminAction>?
    @State private var pendingRoleRemoval: PendingUserReview<ManagedOrganization>?
    @State private var pendingPlatformRoleAction: PendingUserReview<PlatformRoleAction>?
    @State private var pendingOwnershipTransfer: PendingOwnershipTransfer?
    @StateObject private var presenceModel: ManagedUserPresenceViewModel

    init(userID: String, fallbackUser: AppUser, viewModel: UserManagementViewModel, actor: AppUser?) {
        self.userID = userID
        self.fallbackUser = fallbackUser
        self.viewModel = viewModel
        self.actor = actor
        _presenceModel = StateObject(wrappedValue: ManagedUserPresenceViewModel(load: viewModel.loadPresence))
    }
    @FocusState private var focusedField: UserDetailFocusField?
    @FocusState private var organizationSearchFocused: Bool

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
        return (viewModel.usesDirectory ? viewModel.organizationChoices : organizations).filter { viewModel.canManageOrganizationRoles(in: $0, actor: actor) }
    }

    private var filteredOrganizations: [ManagedOrganization] {
        return assignmentOrganizations.filter { organization in
            LocalSearchMatcher.matches(
                query: organizationSearchText,
                values: [organization.name, organization.city, organization.id]
            )
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
        guard viewModel.usesDirectory ? viewModel.organizationChoicesLoaded && !viewModel.organizationChoicesFailed : viewModel.organizationsLoaded else {
            return AppStrings.UserManagement.organizationsNotLoaded
        }
        guard !assignmentOrganizations.isEmpty else {
            return AppStrings.UserManagement.roleAssignmentUnavailable
        }
        guard PermissionService.isUsableAccount(user: user) else {
            return AppStrings.UserManagement.platformRoleTargetAccountNotUsable
        }
        if securityMetadata == nil { return AppStrings.UserManagement.securityLoadHint }
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
        if roleReason.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count > 2000 {
            return UserAdministrationCopy.reasonLimit
        }
        if roleReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return AppStrings.UserManagement.reasonRequired
        }
        return nil
    }

    private var availableAccountActions: [UserAdminAction] {
        let regularActions: [UserAdminAction]
        switch user.managedAccountState {
        case .active:
            regularActions = [.warningIssued, .suspended, .banned, .deactivated]
        case .warned:
            regularActions = [.suspended, .banned, .deactivated]
        case .suspendedUntil, .blocked:
            regularActions = [.unblocked, .banned, .deactivated]
        case .bannedPermanent, .deactivated:
            regularActions = [.unblocked]
        }

        guard let retryAction = viewModel.sessionRevocationRetryAction(for: userID),
              !regularActions.contains(retryAction) else {
            return regularActions
        }
        return [retryAction] + regularActions
    }

    var body: some View {
        lifecycleScreen
            .toolbar(.hidden, for: .tabBar)
            .sheet(item: $pendingAction) { action in
                AccountActionConfirmationSheet(
                    action: action.action,
                    target: action.target,
                    actor: action.actor,
                    viewModel: viewModel
                )
            }
            .sheet(item: $pendingPlatformRoleAction) { action in
                PlatformRoleConfirmationSheet(
                    action: action.action,
                    target: action.target,
                    actor: action.actor,
                    viewModel: viewModel
                )
            }
            .sheet(item: $pendingRoleRemoval) { organization in
                OrganizationRoleRemovalSheet(
                    organization: organization.action,
                    target: organization.target,
                    actor: organization.actor,
                    viewModel: viewModel
                )
            }
            .sheet(item: $pendingOwnershipTransfer) { transfer in
                UserOwnershipTransferReviewSheet(organization: transfer.organization,
                    target: transfer.target, actor: transfer.actor, reason: transfer.reason, viewModel: viewModel) {
                        roleReason = ""
                    }
            }
    }

    private var canReviewCurrentUser: Bool {
        guard let actor else { return false }
        return viewModel.isReviewCurrent(target: user, actor: actor, currentActor: authState.user)
    }

    private var baseScreen: some View {
        PushedScreenShell(
            title: AppStrings.UserManagement.title,
            tabBarHidden: true
        ) {
            AppGroupedContentPlane {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    if viewModel.unavailableUserIDs.contains(userID) {
                        UnifiedEmptyStateCard(systemImage: "person.crop.circle.badge.xmark", title: AppStrings.UserManagement.title,
                            message: UserAdministrationCopy.unavailable)
                            .accessibilityIdentifier("user.detail.unavailable")
                    } else {
                    profileCard
                    if viewModel.loadingDetailUserIDs.contains(userID) {
                        ProgressView().accessibilityIdentifier("user.detail.loading")
                    } else if viewModel.failedDetailUserIDs.contains(userID) {
                        InlineMessageCard(style: .error, message: AppStrings.UserManagement.refreshFailed)
                        Button(AppStrings.UserManagement.retry) { Task { await viewModel.refreshDetail(userID: userID, actor: actor) } }
                            .accessibilityIdentifier("user.detail.retry")
                    }
                    if let message = viewModel.statusMessage {
                        UserManagementOperationMessage(message: message)
                    }
                    if viewModel.error != nil {
                        InlineMessageCard(style: .error, message: AppStrings.UserManagement.refreshFailed)
                            .accessibilityIdentifier("user.detail.refreshError")
                    }
                    accountActionsCard
                    platformRolesCard
                    organizationRolesCard
                    if viewModel.usesDirectory {
                        AppEditorSectionCard {
                            Button { isChoosingOrganization.toggle() } label: {
                                HStack(alignment: .center, spacing: 12) {
                                    Text(AppStrings.UserManagement.assignRoleSectionTitle)
                                        .font(.headline).fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: isChoosingOrganization ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 18, weight: .semibold)).accessibilityHidden(true)
                                }.frame(minHeight: AppTheme.minimumInteractiveTarget).contentShape(Rectangle())
                            }.buttonStyle(.plain).foregroundStyle(AppTheme.accentPrimaryForeground)
                                .accessibilityIdentifier("user.detail.organizationAssignment")
                        }
                        if isChoosingOrganization { roleAssignmentCard }
                    } else { roleAssignmentCard }
                    securityCard
                    UserAuditHistoryCard(userID: user.id, actor: authState.user,
                        refreshToken: "\(viewModel.mutationRevision)|\(historyRefresh)", load: viewModel.loadAuditHistory)
                    }
                }
            }
        }
    }

    private var lifecycleScreen: some View {
        baseScreen
            .contentShape(Rectangle())
            .appRefreshable {
                async let details: Void = viewModel.refreshDetail(userID: userID, actor: actor)
                async let presence: Void = presenceModel.refresh(userID: userID, actor: actor)
                _ = await (details, presence)
                historyRefresh += 1
                ensureSelectedOrganization()
                ensureSelectedRole()
            }
            .task {
                ensureSelectedOrganization()
                ensureSelectedRole()
                await viewModel.refreshDetail(userID: userID, actor: actor)
            }
            .task(id: "\(isChoosingOrganization)|\(organizationSearchText)") {
                guard viewModel.usesDirectory, isChoosingOrganization else { return }
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                await viewModel.loadOrganizationChoices(actor: actor, search: organizationSearchText)
                ensureSelectedOrganization(); ensureSelectedRole()
            }
            .onChange(of: ProfileAccessIdentity(user: authState.user)) { _, _ in
                pendingAction = nil; pendingRoleRemoval = nil; pendingPlatformRoleAction = nil; pendingOwnershipTransfer = nil
                dismiss()
            }
            .onChange(of: viewModel.organizationChoices.count) { _, _ in ensureSelectedOrganization(); ensureSelectedRole() }
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
                profileIdentityLayout {
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
                            UserManagementStatusBadge(title: user.managedAccountState == .active ? AppStrings.UserManagement.unrestrictedStatus : user.managedAccountState.title, tint: statusTint)
                            UserManagementStatusBadge(title: user.globalRole.title, tint: PermissionService.hasOwnerRoleForDisplay(user: user) ? AppTheme.accentSupportForeground : AppTheme.textSecondary)
                            if !organizationRoles.isEmpty {
                                UserManagementStatusBadge(
                                    title: AppStrings.UserManagement.organizationRolesAdditionalCount(organizationRoles.count),
                                    tint: AppTheme.accentPrimaryForeground
                                )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()

                ManagedUserPresenceView(userID: userID, actor: actor,
                    refreshToken: "\(viewModel.mutationRevision)", model: presenceModel)

                Divider()

                UserManagementMetadataRow(systemImage: "number", title: AppStrings.UserManagement.uid, value: user.id)
                UserManagementMetadataRow(systemImage: "at", title: "Telegram", value: telegramDisplayText)
                UserManagementMetadataRow(systemImage: "mappin.and.ellipse", title: AppStrings.UserManagement.cityRegion, value: locationText)
                UserManagementMetadataRow(systemImage: "calendar", title: AppStrings.UserManagement.joined, value: user.createdAt == .distantPast ? AppStrings.Common.notAvailable : LocalizationStore.dateString(from: user.createdAt, dateStyle: .medium, timeStyle: .none))
                if let banExpiresAt = user.banExpiresAt {
                    UserManagementMetadataRow(systemImage: "clock", title: AppStrings.UserManagement.blockedUntil, value: LocalizationStore.dateString(from: banExpiresAt, dateStyle: .medium, timeStyle: .short))
                }
            }
        }
    }

    private var securityCard: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                SectionHeaderBlock(title: AppStrings.UserManagement.securityTitle,
                                   subtitle: AppStrings.UserManagement.securitySubtitle)
                if let securityMetadata {
                    UserManagementMetadataRow(
                        systemImage: securityMetadata.authDisabled ? "lock.fill" : "lock.open.fill",
                        title: LocalizationStore.localizedString(
                            "user_management.security.auth_status",
                            defaultValue: "Статус входу"
                        ),
                        value: user.managedAccountState.isRestricted ? user.managedAccountState.title : LocalizationStore.localizedString(
                            securityMetadata.authDisabled
                                ? "user_management.security.auth_disabled"
                                : "user_management.security.auth_enabled",
                            defaultValue: securityMetadata.authDisabled ? "Вхід вимкнено" : "Вхід дозволено"
                        ),
                        tint: (securityMetadata.authDisabled || user.managedAccountState.isRestricted) ? AppTheme.accentDestructiveForeground : nil
                    )
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
                            : securityMetadata.providerIDs.map { provider in
                                switch provider {
                                case "password": AppStrings.UserManagement.emailPasswordProvider
                                case "apple.com": "Apple"
                                case "google.com": "Google"
                                default: provider
                                }
                            }.joined(separator: ", ")
                    )
                }
                if viewModel.loadingSecurityUserIDs.contains(userID) {
                    ProgressView().frame(maxWidth: .infinity)
                } else if securityMetadata == nil || viewModel.failedSecurityUserIDs.contains(userID) {
                    Text(viewModel.failedSecurityUserIDs.contains(userID)
                         ? AppStrings.UserManagement.refreshFailed : AppStrings.UserManagement.securityLoadHint)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                    Button(AppStrings.UserManagement.retry) {
                        Task { await viewModel.loadSecurityMetadata(userID: userID, actor: actor) }
                    }
                }
            }
        }
    }

    private var organizationRolesCard: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                SectionHeaderBlock(title: AppStrings.UserManagement.organizationRolesTitle, subtitle: AppStrings.UserManagement.organizationRolesSubtitle)

                if viewModel.usesDirectory && viewModel.failedMembershipUserIDs.contains(userID) {
                    Text(AppStrings.UserManagement.refreshFailed).foregroundStyle(AppTheme.textSecondary)
                    Button(AppStrings.UserManagement.retry) { Task { await viewModel.loadMemberships(userID: userID, actor: actor) } }
                        .accessibilityIdentifier("user.detail.memberships.retry")
                }
                if viewModel.usesDirectory && !viewModel.confirmedMembershipUserIDs.contains(userID) {
                    if viewModel.loadingMembershipUserIDs.contains(userID) { ProgressView() }
                    Text(AppStrings.UserManagement.organizationsNotLoaded)
                        .font(.subheadline).foregroundStyle(AppTheme.textSecondary)
                } else if !viewModel.usesDirectory && !viewModel.organizationsLoaded {
                    Text(AppStrings.UserManagement.organizationsNotLoaded)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                } else if organizationRoles.isEmpty {
                    Text(AppStrings.UserManagement.organizationRolesEmpty)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                } else {
                    ForEach(organizationRoles) { item in
                        let organization = item.organization
                        profileIdentityLayout {
                            Image(systemName: roleIcon(item.role))
                                .font(.system(size: 18, weight: .semibold))
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

                            if item.role == .communityOwner {
                                Image(systemName: "lock.fill")
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                                    .frame(width: AppTheme.minimumInteractiveTarget, height: AppTheme.minimumInteractiveTarget)
                                    .accessibilityLabel(AppStrings.UserManagement.ownerTransferOnly)
                            } else if let actor, viewModel.canManageOrganizationRoles(in: organization, actor: actor) {
                                Button {
                                    viewModel.statusMessage = nil
                                    pendingRoleRemoval = .init(action: organization, target: user, actor: actor)
                                } label: {
                                    Image(systemName: "minus.circle")
                                        .foregroundStyle(AppTheme.accentDestructiveForeground)
                                        .frame(
                                            width: AppTheme.minimumInteractiveTarget,
                                            height: AppTheme.minimumInteractiveTarget
                                        )
                                }
                                .accessibilityLabel(AppStrings.UserManagement.removeOrganizationRoleButton)
                                .accessibilityIdentifier("user.detail.organizationRole.remove.\(organization.id)")
                                .disabled(isUpdating || !canReviewCurrentUser)
                            }
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
                        .accessibilityIdentifier("user.detail.platformRole.protected")
                } else if actor?.id == user.id {
                    Text(AppStrings.UserManagement.selfRoleChangeNotice)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                if canShowAppAdminRoleControls, canChangePlatformRoles {
                    if user.globalRole.authorizationRole == .admin {
                        roleActionButton(.removeAppAdmin, isEnabled: canRemoveAppAdmin)
                    } else {
                        roleActionButton(.assignAppAdmin, isEnabled: canAssignAppAdmin)
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

                AppSearchField(placeholder: AppStrings.UserManagement.organizationSearchPlaceholder,
                               text: $organizationSearchText, focus: $organizationSearchFocused, fieldID: "user.detail.organizationSearch")

                Menu {
                    ForEach(filteredOrganizations) { organization in
                        Button { selectedOrganizationID = organization.id } label: {
                            if selectedOrganizationID == organization.id { Label(organization.name, systemImage: "checkmark") }
                            else { Text(organization.name) }
                        }
                    }
                } label: {
                    selectionLabel(title: AppStrings.UserManagement.organizationPicker,
                        value: selectedOrganization?.name ?? AppStrings.UserManagement.organizationsNotFound)
                }
                .tint(AppTheme.accentPrimaryForeground).disabled(filteredOrganizations.isEmpty)
                .accessibilityIdentifier("user.detail.organizationPicker")

                if viewModel.isLoadingOrganizations { ProgressView() }
                if viewModel.organizationChoicesFailed {
                    Text(AppStrings.UserManagement.refreshFailed).foregroundStyle(AppTheme.textSecondary)
                    Button(AppStrings.UserManagement.retry) { Task { await viewModel.loadOrganizationChoices(actor: actor, search: organizationSearchText) } }
                        .accessibilityIdentifier("user.detail.organizations.retry")
                }
                if viewModel.usesDirectory, viewModel.organizationCursor != nil {
                    Button(AppStrings.UserManagement.loadMore) { Task { await viewModel.loadOrganizationChoices(actor: actor, search: organizationSearchText, more: true) } }
                        .disabled(viewModel.isLoadingOrganizations)
                }
                if !viewModel.isLoadingOrganizations && (!viewModel.usesDirectory || viewModel.organizationChoicesLoaded) && assignmentOrganizations.isEmpty {
                    Text(AppStrings.UserManagement.roleAssignmentUnavailable)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                } else if !viewModel.isLoadingOrganizations && (!viewModel.usesDirectory || viewModel.organizationChoicesLoaded) && filteredOrganizations.isEmpty {
                    Text(AppStrings.UserManagement.organizationsNotFound)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        Menu {
                            ForEach(assignableRoles, id: \.self) { role in
                                Button { selectedRole = role } label: {
                                    if selectedRole == role { Label(roleTitle(role), systemImage: "checkmark") }
                                    else { Text(roleTitle(role)) }
                                }
                            }
                        } label: { selectionLabel(title: AppStrings.UserManagement.rolePicker, value: roleTitle(selectedRole)) }
                    } else {
                        Picker(AppStrings.UserManagement.rolePicker, selection: $selectedRole) {
                            ForEach(assignableRoles, id: \.self) { role in Text(roleTitle(role)).tag(role) }
                        }.pickerStyle(.segmented)
                    }
                }
                .accessibilityIdentifier("user.detail.rolePicker")
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
                    .accessibilityIdentifier("user.detail.roleReason")
                    .focused($focusedField, equals: .roleReason)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
                    .disabled(!canManageSelectedOrganizationRoles || selectedOrganization?.ownerId == user.id)

                Text(UserAdministrationCopy.reasonLimit).font(.caption).foregroundStyle(AppTheme.textSecondary)
                if let roleAssignmentBlockingMessage {
                    Label(roleAssignmentBlockingMessage, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                PrimaryActionButton(
                    title: selectedRole == .communityOwner ? AppStrings.UserManagement.changeOwnerButton : AppStrings.UserManagement.assignRoleButton,
                    isEnabled: canReviewCurrentUser && canManageSelectedOrganizationRoles && canAssignSelectedOrganizationRole && roleAssignmentBlockingMessage == nil,
                    isLoading: isUpdating,
                    systemImage: selectedRole == .communityOwner ? "person.crop.circle.badge.checkmark" : "person.badge.key"
                ) {
                    guard let selectedOrganization else { return }
                    guard let actor else { return }
                    let currentUser = user
                    let submittedReason = roleReason
                    let submittedRole = selectedRole
                    if submittedRole == .communityOwner {
                        viewModel.statusMessage = nil
                        pendingOwnershipTransfer = PendingOwnershipTransfer(
                            organization: selectedOrganization,
                            target: currentUser,
                            reason: submittedReason,
                            actor: actor
                        )
                    } else {
                        Task {
                            await viewModel.assignRole(submittedRole, in: selectedOrganization, to: currentUser, actor: actor, reason: submittedReason)
                            if viewModel.statusMessage == AppStrings.UserManagement.changesSaved {
                                roleReason = ""
                            }
                        }
                    }
                }.accessibilityIdentifier("user.detail.assignRole")
            }
        }
    }

    private func selectionLabel(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(AppTheme.textSecondary)
            HStack(alignment: .center, spacing: 12) {
                Text(value).font(.body).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 16, weight: .semibold)).accessibilityHidden(true)
            }
        }.padding(12).background(AppTheme.surfaceControl, in: RoundedRectangle(cornerRadius: AppTheme.inputRadius))
            .contentShape(Rectangle())
    }

    private var accountActionsCard: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                SectionHeaderBlock(
                    title: AppStrings.UserManagement.accountActionsTitle,
                    subtitle: AppStrings.UserManagement.accountActionsSubtitle
                )

                if canManage {
                    ForEach(availableAccountActions) { action in
                        Button { if let actor { viewModel.statusMessage = nil; pendingAction = .init(action: action, target: user, actor: actor) } } label: {
                            actionLabel(action, tint: accountActionTint(action))
                        }
                        .accessibilityIdentifier("user.detail.accountAction.\(action.rawValue)")
                        .disabled(isUpdating || !canReviewCurrentUser)
                    }
                } else {
                    Label(accountActionsUnavailableMessage, systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("user.detail.accountActions.unavailable")
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var locationText: String {
        let region = user.selectedFederalState?.displayName
        let city = user.city.trimmingCharacters(in: .whitespacesAndNewlines)
        if city.contains(" · ") || city.contains(" / ") {
            return city
        }
        let locationParts: [String] = [user.city, region].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        return locationParts.isEmpty ? AppStrings.Common.notAvailable : locationParts.joined(separator: " · ")
    }

    private var telegramDisplayText: String {
        guard var username = user.telegramUsername?.trimmingCharacters(in: .whitespacesAndNewlines),
              !username.isEmpty else {
            return AppStrings.Common.notAvailable
        }
        for prefix in ["https://t.me/", "http://t.me/", "t.me/"] where username.lowercased().hasPrefix(prefix) {
            username.removeFirst(prefix.count)
            break
        }
        username = username.trimmingCharacters(in: CharacterSet(charactersIn: "@/"))
        return username.isEmpty ? AppStrings.Common.notAvailable : "@\(username)"
    }

    private var statusTint: Color {
        switch user.managedAccountState {
        case .active:
            AppTheme.accentPrimaryForeground
        case .warned:
            AppTheme.accentSupportForeground
        case .suspendedUntil, .blocked, .bannedPermanent, .deactivated:
            AppTheme.accentDestructiveForeground
        }
    }

    private var accountActionsUnavailableMessage: String {
        if PermissionService.hasOwnerRoleForDisplay(user: user) {
            return AppStrings.UserManagement.ownerAccountImmutableNotice
        }
        if actor?.id == user.id {
            return AppStrings.UserManagement.selfAccountChangeNotice
        }
        return AppStrings.UserManagement.statusPermissionDenied
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
            AppTheme.accentSupportForeground
        case .admin:
            AppTheme.accentPrimaryForeground
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
        return canReviewCurrentUser && canChangePlatformRoles
            && PermissionService.canAssignAppAdmin(user: actor)
            && securityMetadata?.emailVerified == true
            && user.globalRole.authorizationRole != .admin
    }

    private var canRemoveAppAdmin: Bool {
        guard let actor else { return false }
        return canReviewCurrentUser && canChangePlatformRoles
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
            AppTheme.accentSupportForeground
        case .unblocked:
            AppTheme.accentPrimaryForeground
        case .suspended, .banned, .deactivated:
            AppTheme.accentDestructiveForeground
        }
    }

    private func roleActionButton(_ action: PlatformRoleAction, isEnabled: Bool) -> some View {
        Button {
            if let actor { viewModel.statusMessage = nil; pendingPlatformRoleAction = .init(action: action, target: user, actor: actor) }
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
        .accessibilityIdentifier("user.detail.platformRole.\(action.id)")
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
        profileIdentityLayout {
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
