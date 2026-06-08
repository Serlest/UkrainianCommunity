import SwiftUI

struct ManagedOrganizationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authState: AuthState

    let organization: Organization
    @ObservedObject var organizationsViewModel: OrganizationsViewModel

    @StateObject private var teamViewModel = OrganizationTeamViewModel()
    @State private var isShowingNewsEditor = false
    @State private var isShowingEventEditor = false
    @State private var isShowingOrganizationEditor = false
    @State private var isShowingTeamSearch = false
    @State private var isShowingDeleteConfirmation = false
    @State private var isDeletingOrganization = false
    @State private var deleteErrorMessage: String?
    @State private var pendingTeamAction: OrganizationTeamAction?
    @State private var selectedTeamRole: OrganizationTeamRole = .moderator
    @State private var teamSearchText = ""
    @State private var isChangingOwner = false

    private var currentOrganization: Organization {
        organizationsViewModel.organization(for: organization.id) ?? organization
    }

    private var canCreateNews: Bool {
        PermissionService.canCreateOrganizationNews(currentOrganization, user: authState.user)
    }

    private var canCreateEvent: Bool {
        PermissionService.canCreateOrganizationEvent(currentOrganization, user: authState.user)
    }

    private var canEditOrganization: Bool {
        PermissionService.canEditOrganizationInfo(currentOrganization, user: authState.user)
    }

    private var canManageTeam: Bool {
        PermissionService.canManageOrganizationRoles(currentOrganization, user: authState.user)
    }

    private var canManagePhotos: Bool {
        PermissionService.canModerateOrganizationContent(currentOrganization, user: authState.user)
    }

    private var canDeleteOrganization: Bool {
        PermissionService.canDeleteOrganization(currentOrganization, user: authState.user)
    }

    var body: some View {
        ProfileDestinationLayout(
            title: currentOrganization.name,
            introSubtitle: AppStrings.Profile.organizationManagementSubtitle
        ) {
            organizationSummaryCard
            managementHubCard
            contactSectionCard
            teamSectionCard
            photoSectionCard
        }
        .sheet(isPresented: $isShowingNewsEditor) {
            NavigationStack {
                NewsEditorView(
                    repository: FirestoreNewsRepository(),
                    organizationId: currentOrganization.id,
                    organizationName: currentOrganization.name,
                    organizationImageURL: currentOrganization.imageURL,
                    organizationFederalState: currentOrganization.federalState
                )
            }
        }
        .sheet(isPresented: $isShowingEventEditor) {
            NavigationStack {
                EventEditorView(
                    repository: FirestoreEventRepository(),
                    organizationId: currentOrganization.id,
                    organizationName: currentOrganization.name,
                    organizationImageURL: currentOrganization.imageURL,
                    organizationFederalState: currentOrganization.federalState
                )
            }
        }
        .sheet(isPresented: $isShowingOrganizationEditor) {
            NavigationStack {
                OrganizationEditorView(
                    organizationsViewModel: organizationsViewModel,
                    organization: currentOrganization,
                    onSaved: {}
                )
            }
        }
        .appDestructiveActionDialog(Binding(
            get: {
                guard isShowingDeleteConfirmation else { return nil }
                return AppDestructiveActionDialog(
                    title: AppStrings.Organizations.deleteConfirmation,
                    message: "",
                    destructiveActionTitle: AppStrings.Organizations.delete,
                    cancelTitle: AppStrings.Organizations.cancel
                ) {
                    Task {
                        await deleteOrganization()
                    }
                }
            },
            set: { if $0 == nil { isShowingDeleteConfirmation = false } }
        ))
        .appErrorDialog(Binding(
            get: {
                deleteErrorMessage.map {
                    AppErrorDialog(
                        title: AppStrings.Organizations.deleteFailed,
                        message: $0,
                        okTitle: AppStrings.Organizations.dismissError
                    )
                }
            },
            set: { if $0 == nil { deleteErrorMessage = nil } }
        ))
        .task(id: currentOrganization.id) {
            await teamViewModel.load(organization: currentOrganization)
        }
        .sheet(isPresented: $isShowingTeamSearch) {
            NavigationStack {
                teamSearchSheet
                    .navigationTitle(isChangingOwner ? AppStrings.Profile.organizationTeamChangeOwner : AppStrings.Profile.organizationTeamAddMember)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(AppStrings.Organizations.cancel) {
                                isShowingTeamSearch = false
                            }
                        }
                    }
            }
            .task(id: isChangingOwner) {
                await teamViewModel.loadCandidateUsers(
                    excluding: currentOrganization,
                    allowsExistingTeamMembers: isChangingOwner
                )
            }
        }
        .confirmationDialog(
            pendingTeamAction?.title ?? "",
            isPresented: Binding(
                get: { pendingTeamAction != nil },
                set: { if !$0 { pendingTeamAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingTeamAction {
                Button(pendingTeamAction.confirmTitle, role: destructiveRole(for: pendingTeamAction)) {
                    Task {
                        await performTeamAction(pendingTeamAction)
                    }
                }
            }

            Button(AppStrings.Organizations.cancel, role: .cancel) {
                pendingTeamAction = nil
            }
        }
    }

    private var organizationSummaryCard: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                HStack(alignment: .top, spacing: 12) {
                    AppFeedThumbnail(
                        imageURL: currentOrganization.imageURL,
                        fallbackSystemImage: "building.2",
                        tint: AppTheme.accentPrimary,
                        fill: AppTheme.accentPrimary.opacity(0.10),
                        size: 52,
                        source: "ManagedOrganizationView"
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text(currentOrganization.name)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(2)

                        HStack(spacing: 6) {
                            if let role = currentManagementRole {
                                ManagementPill(title: role.title, tint: role.tint)
                            }

                            ManagementPill(
                                title: currentOrganization.moderationStatus.title,
                                tint: currentOrganization.moderationStatus == .approved ? AppTheme.accentPrimary : AppTheme.textSecondary
                            )
                        }

                        Text(currentOrganization.shortDescription)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 8) {
                    MetadataRow(label: AppStrings.Common.city, value: currentOrganization.city, systemImage: "mappin.and.ellipse")

                    if let contactEmail = currentOrganization.contactEmail, !contactEmail.isEmpty {
                        MetadataRow(label: AppStrings.Common.contact, value: contactEmail, systemImage: "envelope")
                    }

                    if let website = currentOrganization.website, !website.isEmpty {
                        MetadataRow(label: AppStrings.Common.website, value: website, systemImage: "link")
                    }
                }
            }
        }
    }

    private var currentManagementRole: ManagedOrganizationRole? {
        guard let user = authState.user else { return nil }
        if currentOrganization.ownerId == user.id {
            return .owner
        }
        if PermissionService.canUseOwnerOrganizationOverride(user: user) {
            return .platformOwner
        }
        if currentOrganization.adminIds.contains(user.id) {
            return .admin
        }
        if currentOrganization.moderatorIds.contains(user.id) {
            return .moderator
        }
        return nil
    }

    private var managementHubCard: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                AppEditorSectionTitle(title: AppStrings.Profile.organizationManagement)

                if canEditOrganization {
                    managementHubButton(
                        title: AppStrings.Profile.organizationInfoSection,
                        subtitle: AppStrings.Organizations.editorSubtitle,
                        systemImage: "building.2"
                    ) {
                        isShowingOrganizationEditor = true
                    }
                } else {
                    disabledManagementHubRow(
                        title: AppStrings.Profile.organizationInfoSection,
                        subtitle: AppStrings.Profile.organizationInfoLockedSubtitle,
                        systemImage: "building.2"
                    )
                }

                if canCreateNews {
                    managementHubButton(
                        title: AppStrings.News.title,
                        subtitle: AppStrings.Profile.organizationNewsActionSubtitle,
                        systemImage: "newspaper"
                    ) {
                        isShowingNewsEditor = true
                    }
                }

                if canCreateEvent {
                    managementHubButton(
                        title: AppStrings.Events.title,
                        subtitle: AppStrings.Profile.organizationEventActionSubtitle,
                        systemImage: "calendar.badge.plus"
                    ) {
                        isShowingEventEditor = true
                    }
                }

                if canDeleteOrganization {
                    managementHubButton(
                        title: AppStrings.Organizations.delete,
                        subtitle: AppStrings.Organizations.deleteConfirmation,
                        systemImage: "trash.fill",
                        role: .destructive
                    ) {
                        isShowingDeleteConfirmation = true
                    }
                    .disabled(isDeletingOrganization)
                }
            }
        }
    }

    private var contactSectionCard: some View {
        OrganizationContactCard(
            organization: currentOrganization,
            allowsEditing: canEditOrganization,
            showsManagementActions: true,
            onEdit: canEditOrganization ? { isShowingOrganizationEditor = true } : nil
        )
    }

    private var photoSectionCard: some View {
        OrganizationPhotoGallerySection(
            organizationId: currentOrganization.id,
            canManage: canManagePhotos,
            currentUser: authState.user
        )
    }

    private var teamSectionCard: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                HStack(alignment: .center) {
                    AppEditorSectionTitle(title: AppStrings.Profile.organizationTeamSection)

                    if canManageTeam {
                        HStack(spacing: 8) {
                            if isPlatformOwner {
                                Button {
                                    teamSearchText = ""
                                    selectedTeamRole = .owner
                                    isChangingOwner = true
                                    isShowingTeamSearch = true
                                } label: {
                                    managementCompactActionLabel(
                                        title: AppStrings.Profile.organizationTeamChangeOwner,
                                        systemImage: "person.crop.circle.badge.checkmark"
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            Button {
                                teamSearchText = ""
                                selectedTeamRole = .moderator
                                isChangingOwner = false
                                isShowingTeamSearch = true
                            } label: {
                                managementCompactActionLabel(
                                    title: AppStrings.Profile.organizationTeamAddMember,
                                    systemImage: "plus"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if isPlatformOwner {
                    Text(AppStrings.Profile.organizationTeamOwnerRequiredExplanation)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                if teamViewModel.isLoading && teamViewModel.members.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, AppTheme.dashboardSpacing)
                } else if teamViewModel.members.isEmpty {
                    compactTeamEmptyState
                } else {
                    VStack(spacing: 8) {
                        ForEach(teamViewModel.members) { member in
                            OrganizationTeamMemberRow(
                                member: member,
                                canManage: canManageTeam,
                                canChangeRole: canChangeRole(for: member),
                                availableRoles: availableRoles(for: member),
                                isUpdating: teamViewModel.updatingUserIDs.contains(member.userID),
                                onAssignRole: { role in
                                    pendingTeamAction = .assign(member: member, role: role)
                                },
                                onRemove: {
                                    pendingTeamAction = .remove(member: member)
                                }
                            )
                        }
                    }
                }

                if let statusMessage = teamViewModel.statusMessage {
                    Label(statusMessage, systemImage: "checkmark.circle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.accentPrimary)
                }

                if let errorMessage = teamViewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.accentDestructive)
                }
            }
        }
    }

    private var compactTeamEmptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(AppStrings.Profile.organizationTeamEmptyTitle, systemImage: "person.2")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)

            Text(AppStrings.Profile.organizationTeamEmptyMessage)
                .font(.footnote)
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var teamSearchSheet: some View {
        List {
            Section {
                TextField(AppStrings.Profile.organizationTeamSearchPlaceholder, text: $teamSearchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                if isChangingOwner {
                    Text(AppStrings.Profile.organizationTeamOwnerRequiredExplanation)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                } else {
                    Picker(AppStrings.Profile.organizationTeamRolePicker, selection: $selectedTeamRole) {
                        ForEach(addMemberAssignableRoles) { role in
                            Text(role.title).tag(role)
                        }
                    }
                }
            }

            Section {
                Text(AppStrings.Profile.organizationTeamSubscribeToAssign)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)

                if teamViewModel.isLoadingCandidates {
                    ProgressView()
                } else if filteredTeamCandidateMembers.isEmpty {
                    Text(AppStrings.Profile.organizationTeamNoUsers)
                        .foregroundStyle(AppTheme.textSecondary)
                } else {
                    ForEach(filteredTeamCandidateMembers) { member in
                        Button {
                            pendingTeamAction = isChangingOwner
                                ? .changeOwner(member: member)
                                : .assign(member: member, role: selectedTeamRole)
                            isShowingTeamSearch = false
                        } label: {
                            OrganizationTeamCandidateRow(
                                member: member,
                                role: teamRole(for: member),
                                isOwnerTransfer: isChangingOwner
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var filteredTeamCandidateMembers: [OrganizationTeamMember] {
        let query = teamSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return teamViewModel.candidateMembers }

        return teamViewModel.candidateMembers.filter { member in
            member.displayName.lowercased().contains(query)
                || member.userID.lowercased().contains(query)
                || (member.locationText?.lowercased().contains(query) ?? false)
        }
    }

    private var availableAssignableRoles: [OrganizationTeamRole] {
        guard let user = authState.user else { return [] }
        if PermissionService.canInitiateOwnershipTransferWorkflow(user: user) {
            return [.owner, .admin, .moderator]
        }
        return [.admin, .moderator]
    }

    private var addMemberAssignableRoles: [OrganizationTeamRole] {
        availableAssignableRoles.filter { $0 != .owner }
    }

    private var roleManagementAssignableRoles: [OrganizationTeamRole] {
        availableAssignableRoles.filter { $0 != .owner }
    }

    private var isPlatformOwner: Bool {
        PermissionService.canUseOwnerOrganizationOverride(user: authState.user)
    }

    private func teamRole(for member: OrganizationTeamMember) -> OrganizationTeamRole? {
        if currentOrganization.ownerId == member.userID {
            return .owner
        }
        if currentOrganization.adminIds.contains(member.userID) {
            return .admin
        }
        if currentOrganization.moderatorIds.contains(member.userID) {
            return .moderator
        }
        return .member
    }

    private func availableRoles(for member: OrganizationTeamMember) -> [OrganizationTeamRole] {
        roleManagementAssignableRoles.filter { $0 != member.role }
    }

    private func canChangeRole(for member: OrganizationTeamMember) -> Bool {
        guard canManageTeam else { return false }
        guard let user = authState.user else { return false }
        if PermissionService.canInitiateOrganizationRoleWorkflow(user: user) {
            return member.role != .owner
        }
        return member.role != .owner && member.userID != user.id
    }

    private func destructiveRole(for action: OrganizationTeamAction) -> ButtonRole? {
        switch action {
        case .assign, .changeOwner:
            nil
        case .remove:
            .destructive
        }
    }

    @MainActor
    private func performTeamAction(_ action: OrganizationTeamAction) async {
        guard let actor = authState.user else {
            pendingTeamAction = nil
            return
        }

        let didUpdate = await teamViewModel.apply(action, organization: currentOrganization, actor: actor)
        pendingTeamAction = nil

        guard didUpdate else { return }
        await organizationsViewModel.refresh()
        let refreshedOrganization = organizationsViewModel.organization(for: currentOrganization.id) ?? currentOrganization
        await teamViewModel.load(organization: refreshedOrganization)

        switch action {
        case let .assign(member, _):
            if member.userID == actor.id {
                await authState.loadUser(uid: actor.id)
            }
        case let .changeOwner(member):
            if member.userID == actor.id || currentOrganization.ownerId == actor.id {
                await authState.loadUser(uid: actor.id)
            }
        case let .remove(member):
            if member.userID == actor.id {
                await authState.loadUser(uid: actor.id)
            }
        }
    }

    private func managementHubButton(
        title: String,
        subtitle: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            OrganizationManagementRow(
                title: title,
                subtitle: subtitle,
                systemImage: systemImage,
                tint: role == .destructive ? AppTheme.accentDestructive : AppTheme.accentPrimary
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func disabledManagementHubRow(title: String, subtitle: String, systemImage: String) -> some View {
        OrganizationManagementRow(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            tint: AppTheme.textSecondary,
            isEnabled: false
        )
        .accessibilityHint(AppStrings.Profile.accessLocked)
    }

    private func managementCompactActionLabel(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.accentPrimary)
            .labelStyle(.iconOnly)
            .frame(width: 34, height: 34)
            .background(AppTheme.accentPrimarySoft, in: Circle())
            .overlay(Circle().strokeBorder(AppTheme.accentPrimary.opacity(0.16)))
            .accessibilityLabel(title)
    }

    @MainActor
    private func deleteOrganization() async {
        guard !isDeletingOrganization else { return }
        isDeletingOrganization = true
        defer { isDeletingOrganization = false }

        do {
            try await organizationsViewModel.deleteOrganization(id: currentOrganization.id, user: authState.user)
            organizationsViewModel.removeDeletedOrganization(id: currentOrganization.id)
            dismiss()
        } catch let appError as AppError {
            deleteErrorMessage = readableManagedOrganizationErrorText(appError)
        } catch {
            deleteErrorMessage = readableManagedOrganizationErrorText(.unknown)
        }
    }

    private func readableManagedOrganizationErrorText(_ error: AppError?) -> String {
        switch error {
        case .network:
            AppStrings.Organizations.loadNetworkError
        case .permissionDenied:
            AppStrings.Organizations.actionPermissionError
        case .validationFailed:
            AppStrings.Organizations.actionValidationError
        case .notFound:
            AppStrings.Organizations.actionNotFoundError
        case .unknown:
            AppStrings.Organizations.actionUnknownError
        case nil:
            AppStrings.Organizations.actionUnknownError
        }
    }
}
