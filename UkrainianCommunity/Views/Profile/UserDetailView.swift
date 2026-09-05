import FirebaseFirestore
import SwiftUI

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

struct UserDetailView: View {
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
    @StateObject private var presenceModel: ManagedUserPresenceViewModel

    init(userID: String, fallbackUser: AppUser, viewModel: UserManagementViewModel, actor: AppUser?) {
        self.userID = userID
        self.fallbackUser = fallbackUser
        self.viewModel = viewModel
        self.actor = actor
        _presenceModel = StateObject(wrappedValue: ManagedUserPresenceViewModel(load: viewModel.loadPresence))
    }
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
                    if viewModel.error != nil {
                        InlineMessageCard(style: .error, message: AppStrings.UserManagement.refreshFailed)
                            .accessibilityIdentifier("user.detail.refreshError")
                    }
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
            .appRefreshable {
                async let details: Void = viewModel.refreshDetail(userID: userID, actor: actor)
                async let presence: Void = presenceModel.refresh(userID: userID, actor: actor)
                _ = await (details, presence)
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
                            UserManagementStatusBadge(title: user.globalRole.title, tint: PermissionService.hasOwnerRoleForDisplay(user: user) ? AppTheme.accentSupportForeground : AppTheme.textSecondary)
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
                ManagedUserPresenceView(userID: userID, actor: actor,
                    refreshToken: "\(viewModel.mutationRevision)", model: presenceModel)
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
            AppTheme.accentPrimaryForeground
        case .warned:
            AppTheme.accentSupportForeground
        case .suspendedUntil, .blocked, .bannedPermanent, .deactivated:
            AppTheme.accentDestructiveForeground
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
            AppTheme.accentSupportForeground
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
                        UserManagementAuditRow(
                            title: item.title,
                            date: LocalizationStore.dateString(from: item.createdAt, dateStyle: .short, timeStyle: .short),
                            reason: item.reason,
                            performedBy: item.performedBy,
                            changeSummary: item.changeSummary
                        )
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
