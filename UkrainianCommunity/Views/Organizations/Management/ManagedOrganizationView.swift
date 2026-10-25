import SwiftUI

struct ManagedOrganizationView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authState: AuthState

    let organization: Organization
    @ObservedObject var organizationsViewModel: OrganizationsViewModel
    @ObservedObject private var accessStore = OrganizationAccessStore.shared

    let newsRepository: NewsRepository
    let eventRepository: EventRepository
    @StateObject private var teamViewModel: OrganizationTeamViewModel

    init(organization: Organization, organizationsViewModel: OrganizationsViewModel,
         newsRepository: NewsRepository = FirestoreNewsRepository(), eventRepository: EventRepository = FirestoreEventRepository()) {
        self.organization = organization
        self.organizationsViewModel = organizationsViewModel
        self.newsRepository = newsRepository
        self.eventRepository = eventRepository
        _teamViewModel = StateObject(wrappedValue: OrganizationTeamViewModel(organizationRepository: organizationsViewModel.editorRepository))
    }
    @State private var authorityOrganization: Organization?
    @State private var authorityDenied = false
    @State private var authorityListener: AppRealtimeListener?
    @State private var authorityObservationID = UUID()
    @State private var contentDestination: String?
    @State private var isShowingSubscribers = false
    @State private var isShowingNewsEditor = false
    @State private var isShowingEventEditor = false
    @State private var isShowingOrganizationEditor = false
    @State private var isShowingTeamSearch = false
    @State private var isShowingDeleteConfirmation = false
    @State private var isDeletingOrganization = false
    @State private var deleteErrorMessage: String?
    @State private var pendingTeamAction: OrganizationTeamAction?
    @State private var pendingTeamOrganization: Organization?
    @State private var pendingTeamIdentity: ProfileAccessIdentity?
    @State private var selectedTeamRole: OrganizationTeamRole = .moderator
    @State private var teamSearchText = ""
    @State private var isChangingOwner = false

    private var currentOrganization: Organization {
        authorityOrganization ?? organizationsViewModel.organization(for: organization.id) ?? organization
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
        PermissionService.canManageOrganizationPhotos(currentOrganization, user: authState.user)
    }

    private var canDeleteOrganization: Bool {
        PermissionService.canDeleteOrganization(currentOrganization, user: authState.user)
    }

    private var canAccessManagement: Bool {
        !authorityDenied && PermissionService.canAccessManagedOrganization(currentOrganization, user: authState.user)
    }

    private var accessIdentity: ProfileAccessIdentity { ProfileAccessIdentity(user: authState.user) }

    var body: some View {
        ProfileDestinationLayout(
            title: currentOrganization.localizedName,
            introSubtitle: AppStrings.Profile.organizationManagementSubtitle
        ) {
            if canAccessManagement {
                organizationSummaryCard
                managementHubCard
                contactSectionCard
                teamSectionCard
                if PermissionService.canViewOrganizationSubscriberIdentities(currentOrganization, user: authState.user) {
                    AppEditorSectionCard {
                        managementHubButton(title: OrganizationWorkspaceCopy.subscribers, subtitle: OrganizationWorkspaceCopy.subscribersHelper,
                            systemImage: "person.2") { isShowingSubscribers = true }
                            .accessibilityIdentifier("organization.management.subscribers")
                    }
                }
                photoSectionCard
            } else if isRevalidating("manageContent") {
                ProgressView(AppStrings.Startup.loading)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .accessibilityIdentifier("organization.management.authorityLoading")
            } else {
                InlineMessageCard(style: .error, message: AppStrings.Errors.permissionDenied)
            }
        }
        .navigationDestination(isPresented: Binding(get: { contentDestination != nil }, set: { if !$0 { contentDestination = nil } })) {
            if let type = contentDestination { OrganizationWorkspaceContentList(organization: currentOrganization, contentType: type,
                newsRepository: newsRepository, eventRepository: eventRepository) }
        }
        .navigationDestination(isPresented: $isShowingSubscribers) { OrganizationWorkspaceSubscribers(organization: currentOrganization) }
        .sheet(isPresented: $isShowingNewsEditor) {
            NavigationStack {
                NewsEditorView(
                    repository: newsRepository,
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
                    repository: eventRepository,
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
                    onSaved: {
                        authorityOrganization = organizationsViewModel.organization(for: currentOrganization.id) ?? currentOrganization
                    }
                )
            }
        }
        .appDestructiveActionDialog(Binding(
            get: {
                guard isShowingDeleteConfirmation else { return nil }
                return AppDestructiveActionDialog(
                    title: AppStrings.Organizations.deleteConfirmation,
                    message: deleteOrganizationCascadeMessage,
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
        .task(id: accessIdentity) {
            beginAuthorityObservation()
            guard canAccessManagement else { return }
            await teamViewModel.load(organization: currentOrganization, actor: authState.user)
        }
        .onDisappear { stopAuthorityObservation() }
        .onChange(of: accessIdentity) { _, _ in closeManagementSheets() }
        .onChange(of: canAccessManagement) { _, allowed in
            if !allowed && !isRevalidating("manageContent") { closeManagementSheets() }
            else if allowed { reloadAuthorizedTeam() }
        }
        .onChange(of: canManageTeam) { _, allowed in
            if !allowed && !isRevalidating("manageTeam") {
                isShowingTeamSearch = false; pendingTeamAction = nil
                pendingTeamOrganization = nil; pendingTeamIdentity = nil
            }
        }
        .onChange(of: canEditOrganization) { _, allowed in
            if !allowed && !isRevalidating("editInfo") { isShowingOrganizationEditor = false }
        }
        .onChange(of: canCreateNews) { _, allowed in
            if !allowed && !isRevalidating("createNews") { isShowingNewsEditor = false }
        }
        .onChange(of: canCreateEvent) { _, allowed in
            if !allowed && !isRevalidating("createEvent") { isShowingEventEditor = false }
        }
        .onChange(of: canDeleteOrganization) { _, allowed in
            if !allowed { isShowingDeleteConfirmation = false }
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
                            .accessibilityIdentifier("organization.team.cancelSearch")
                        }
                    }
            }
            .task(id: "\(isChangingOwner)-\(teamSearchText)-\(accessIdentity)") {
                if !teamSearchText.isEmpty { try? await Task.sleep(for: .milliseconds(300)); guard !Task.isCancelled else { return } }
                await reloadTeamCandidates()
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
                    guard let reviewedOrganization = pendingTeamOrganization, let reviewedIdentity = pendingTeamIdentity else { return }
                    Task {
                        await performTeamAction(pendingTeamAction, organization: reviewedOrganization, reviewedIdentity: reviewedIdentity)
                    }
                }
                .accessibilityIdentifier("organization.team.confirm")
            }

            Button(AppStrings.Organizations.cancel, role: .cancel) {
                pendingTeamAction = nil
                pendingTeamOrganization = nil; pendingTeamIdentity = nil
            }
        }
    }

    private func stopAuthorityObservation() {
        authorityObservationID = UUID()
        authorityListener?.cancel()
        authorityListener = nil
    }

    private func beginAuthorityObservation() {
        stopAuthorityObservation()
        let observationID = authorityObservationID
        let identity = accessIdentity
        authorityDenied = false
        authorityListener = organizationsViewModel.observeManagedOrganization(id: organization.id) { updated in
            guard authorityObservationID == observationID, accessIdentity == identity else { return }
            let previous = currentOrganization
            let previouslyAllowed = canAccessManagement
            authorityOrganization = updated
            let teamChanged = previous.ownerId != updated.ownerId || Set(previous.adminIds) != Set(updated.adminIds)
                || Set(previous.moderatorIds) != Set(updated.moderatorIds)
            let actorRoleChanged = identity.userID.map { uid in
                (previous.ownerId == uid) != (updated.ownerId == uid)
                    || previous.adminIds.contains(uid) != updated.adminIds.contains(uid)
                    || previous.moderatorIds.contains(uid) != updated.moderatorIds.contains(uid)
            } ?? false
            let authorityChanged = previous.moderationStatus != updated.moderationStatus
                || (identity.role != GlobalRole.owner.rawValue && actorRoleChanged)
            if authorityChanged {
                if let uid = identity.userID { accessStore.invalidateAuthority(for: uid) }
                closeManagementSheets()
            }
            // Another teammate's role change must not discard this user's open draft.
            if (teamChanged || authorityChanged) && previouslyAllowed && canAccessManagement { reloadAuthorizedTeam() }
        } onError: { error in
            guard authorityObservationID == observationID, accessIdentity == identity else { return }
            if error == .permissionDenied || error == .notFound {
                authorityDenied = true
                closeManagementSheets()
            }
        }
    }

    private func reloadAuthorizedTeam() {
        let identity = accessIdentity
        let observationID = authorityObservationID
        Task { @MainActor in
            guard accessIdentity == identity, authorityObservationID == observationID, canAccessManagement else { return }
            await teamViewModel.load(organization: currentOrganization, actor: authState.user)
        }
    }

    private func isRevalidating(_ action: String) -> Bool {
        PermissionService.isUsableAccount(user: authState.user)
            && accessStore.isRevalidatingPreviousGrant(action, organizationID: currentOrganization.id, userID: authState.user?.id)
    }

    private func closeManagementSheets() {
        contentDestination = nil; isShowingSubscribers = false
        isShowingNewsEditor = false
        isShowingEventEditor = false
        isShowingOrganizationEditor = false
        isShowingTeamSearch = false
        isShowingDeleteConfirmation = false
        pendingTeamAction = nil
        pendingTeamOrganization = nil; pendingTeamIdentity = nil
        teamViewModel.reset()
    }

    private var organizationSummaryCard: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
                HStack(alignment: .top, spacing: 12) {
                    AppFeedThumbnail(
                        imageURL: currentOrganization.imageURL,
                        fallbackSystemImage: "building.2",
                        tint: AppTheme.accentPrimaryForeground,
                        fill: AppTheme.accentPrimary.opacity(0.10),
                        size: 52,
                        source: "ManagedOrganizationView"
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text(currentOrganization.localizedName)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(2)

                        HStack(spacing: 6) {
                            if let role = currentManagementRole {
                                ManagementPill(title: role.title, tint: role.tint)
                            }

                            ManagementPill(
                                title: currentOrganization.moderationStatus.title,
                                tint: currentOrganization.moderationStatus == .approved ? AppTheme.accentPrimaryForeground : AppTheme.textSecondary
                            )
                        }

                        Text(currentOrganization.localizedShortDescription)
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
                    .accessibilityIdentifier("organization.management.editInfo")
                }

                if canCreateNews {
                    managementHubButton(
                        title: AppStrings.News.title,
                        subtitle: OrganizationWorkspaceCopy.contentHelper,
                        systemImage: "newspaper"
                    ) {
                        contentDestination = "news"
                    }
                    .accessibilityIdentifier("organization.management.createNews")
                }

                if canCreateEvent {
                    managementHubButton(
                        title: AppStrings.Events.title,
                        subtitle: OrganizationWorkspaceCopy.contentHelper,
                        systemImage: "calendar.badge.plus"
                    ) {
                        contentDestination = "event"
                    }
                    .accessibilityIdentifier("organization.management.createEvent")
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
                            .accessibilityIdentifier("organization.management.addTeamMember")
                        }
                    }
                }

                Text(OrganizationWorkspaceCopy.teamHelper).font(.footnote).foregroundStyle(AppTheme.textSecondary)
                if isPlatformOwner {
                    Text(AppStrings.Profile.organizationTeamOwnerRequiredExplanation)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                if teamViewModel.isLoading && teamViewModel.members.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, AppTheme.dashboardSpacing)
                } else if let errorMessage = teamViewModel.errorMessage,
                          teamViewModel.members.isEmpty {
                    teamLoadFailureState(message: errorMessage)
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
                                    reviewTeamAction(.assign(member: member, role: role))
                                },
                                onRemove: {
                                    reviewTeamAction(.remove(member: member))
                                }
                            )
                        }
                    }
                }

                if let statusMessage = teamViewModel.statusMessage {
                    Label(statusMessage, systemImage: "checkmark.circle")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.accentPrimaryForeground)
                }

                if let errorMessage = teamViewModel.errorMessage,
                   !teamViewModel.members.isEmpty {
                    teamLoadFailureState(message: errorMessage)
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

    private func teamLoadFailureState(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.accentDestructiveForeground)

            Button(AppStrings.Organizations.retry) {
                Task {
                    await teamViewModel.load(
                        organization: currentOrganization,
                        actor: authState.user
                    )
                }
            }
            .font(.caption.weight(.semibold))
            .disabled(teamViewModel.isLoading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var teamSearchSheet: some View {
        List {
            Section {
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
                    .accessibilityIdentifier("organization.team.role")
                }
            }

            Section {
                Text(isPlatformOwner ? OrganizationWorkspaceCopy.candidateHelper : AppStrings.Profile.organizationTeamSubscribeToAssign)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.textSecondary)

                if teamViewModel.isLoadingCandidates {
                    ProgressView()
                } else if let candidateErrorMessage = teamViewModel.candidateErrorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(candidateErrorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(AppTheme.accentDestructiveForeground)

                        Button(AppStrings.Organizations.retry) {
                            Task {
                                await reloadTeamCandidates()
                            }
                        }
                        .disabled(teamViewModel.isLoadingCandidates)
                    }
                } else if filteredTeamCandidateMembers.isEmpty {
                    Text(AppStrings.Profile.organizationTeamNoUsers)
                        .foregroundStyle(AppTheme.textSecondary)
                } else {
                    ForEach(filteredTeamCandidateMembers) { member in
                        Button {
                            reviewTeamAction(isChangingOwner
                                ? .changeOwner(member: member)
                                : .assign(member: member, role: selectedTeamRole))
                            isShowingTeamSearch = false
                        } label: {
                            OrganizationTeamCandidateRow(
                                member: member,
                                role: teamRole(for: member),
                                isOwnerTransfer: isChangingOwner
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("organization.team.candidate.\(member.userID)")
                    }
                }
                if teamViewModel.hasMoreCandidates {
                    Button(AppStrings.Search.loadMoreContent) { Task { await reloadTeamCandidates(more: true) } }
                        .disabled(teamViewModel.isLoadingCandidates)
                }
            }
        }
        .searchable(
            text: $teamSearchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: AppStrings.Profile.organizationTeamSearchPlaceholder
        )
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    }

    private var filteredTeamCandidateMembers: [OrganizationTeamMember] {
        return teamViewModel.candidateMembers.filter { member in
            LocalSearchMatcher.matches(
                query: teamSearchText,
                values: [member.displayName, member.userID, member.locationText]
            )
        }
    }

    @MainActor
    private func reloadTeamCandidates(more: Bool = false) async {
        await teamViewModel.loadCandidateUsers(
            excluding: currentOrganization,
            actor: authState.user,
            allowsExistingTeamMembers: isChangingOwner, search: teamSearchText, more: more
        )
    }

    private var deleteOrganizationCascadeMessage: String {
        AppStrings.Organizations.deleteCascadeMessage
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
    private func reviewTeamAction(_ action: OrganizationTeamAction) {
        pendingTeamOrganization = currentOrganization
        pendingTeamIdentity = accessIdentity
        pendingTeamAction = action
    }

    private func performTeamAction(_ action: OrganizationTeamAction, organization: Organization, reviewedIdentity: ProfileAccessIdentity) async {
        guard accessIdentity == reviewedIdentity, let actor = authState.user else {
            pendingTeamAction = nil
            return
        }

        let identity = accessIdentity
        let organizationID = organization.id
        let didUpdate = await teamViewModel.apply(action, organization: organization, actor: actor)
        guard accessIdentity == identity else { return }
        pendingTeamAction = nil
        pendingTeamOrganization = nil; pendingTeamIdentity = nil

        guard didUpdate else { return }
        let fresh = await organizationsViewModel.resolveOrganization(id: organizationID, force: true)
        guard accessIdentity == identity else { return }
        let refreshedOrganization = fresh ?? currentOrganization
        authorityOrganization = refreshedOrganization
        await teamViewModel.load(organization: refreshedOrganization, actor: actor)

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
                tint: role == .destructive ? AppTheme.accentDestructiveForeground : AppTheme.accentPrimaryForeground
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private func managementCompactActionLabel(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AppTheme.accentPrimaryForeground)
            .labelStyle(.iconOnly)
            .frame(
                width: AppTheme.minimumInteractiveTarget,
                height: AppTheme.minimumInteractiveTarget
            )
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
