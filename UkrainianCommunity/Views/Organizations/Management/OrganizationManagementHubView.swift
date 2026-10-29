import Combine
import SwiftUI

private let organizationManagementContentStatsTTL: TimeInterval = 600

private struct CachedManagedOrganizationContentStats {
    let stats: ManagedOrganizationContentStats
    let loadedAt: Date
}

@MainActor
private enum OrganizationManagementContentStatsCache {
    static var cachedStatsByOrganizationID: [String: CachedManagedOrganizationContentStats] = [:]

    static func stats(for organizationID: String) -> ManagedOrganizationContentStats? {
        guard let cached = cachedStatsByOrganizationID[organizationID],
              Date().timeIntervalSince(cached.loadedAt) <= organizationManagementContentStatsTTL else {
            cachedStatsByOrganizationID[organizationID] = nil
            return nil
        }
        return cached.stats
    }

    static func store(_ stats: ManagedOrganizationContentStats, for organizationID: String) {
        cachedStatsByOrganizationID[organizationID] = CachedManagedOrganizationContentStats(
            stats: stats,
            loadedAt: Date()
        )
    }

    static func removeAll() {
        cachedStatsByOrganizationID = [:]
    }
}

struct OrganizationManagementHubView: View {
    @EnvironmentObject private var authState: AuthState
    @ObservedObject private var accessStore = OrganizationAccessStore.shared
    private var accessIdentity: ProfileAccessIdentity { ProfileAccessIdentity(user: authorityUser) }
    let focusedOrganizationID: String?

    private let repository: OrganizationRepository
    private let newsRepository: NewsRepository
    private let eventRepository: EventRepository
    private let legalDocumentRepository: LegalDocumentRepository
    @ObservedObject private var organizationsViewModel: OrganizationsViewModel
    @StateObject private var authoringOrganizations: OrganizationManagementListModel
    @FocusState private var searchFocused: Bool
    @State private var searchText = ""
    @State private var region: AustrianFederalState?
    @State private var statsEpoch = UUID()
    @State private var statsErrors: [String: String] = [:]
    @State private var isShowingCreateOrganization = false
    @State private var editingOrganizationRequest: Organization?
    @State private var previewingOrganizationRequest: Organization?
    @State private var pendingDeleteOrganizationRequest: Organization?
    @State private var deleteRequestErrorDialog: AppErrorDialog?
    @State private var organizationContentStats: [String: ManagedOrganizationContentStats] = [:]
    @State private var loadingContentStatOrganizationIDs = Set<String>()

    private var authorityUser: AppUser? {
        authState.user
    }

    init(
        focusedOrganizationID: String? = nil,
        organizationsViewModel: OrganizationsViewModel,
        repository: OrganizationRepository = FirestoreOrganizationRepository(),
        newsRepository: NewsRepository = FirestoreNewsRepository(),
        eventRepository: EventRepository = FirestoreEventRepository(),
        legalDocumentRepository: LegalDocumentRepository = FirestoreLegalDocumentRepository()
    ) {
        self.focusedOrganizationID = focusedOrganizationID
        self.organizationsViewModel = organizationsViewModel
        _authoringOrganizations = StateObject(wrappedValue: OrganizationManagementListModel(repository: repository))
        self.repository = repository
        self.newsRepository = newsRepository
        self.eventRepository = eventRepository
        self.legalDocumentRepository = legalDocumentRepository
    }

    private var manageableOrganizations: [Organization] {
        guard let authorityUser, authoringOrganizations.error == nil else { return [] }
        let organizations = PermissionService.manageableOrganizations(
            from: authoringOrganizations.organizations,
            user: authorityUser
        )
        guard let focusedOrganizationID else { return organizations }
        return organizations.filter { $0.id == focusedOrganizationID }
    }

    private var organizationRequests: [Organization] {
        guard focusedOrganizationID == nil else { return [] }
        return organizationsViewModel.organizationRequests.filter { organization in
            (region == nil || organization.federalState == region) && LocalSearchMatcher.matches(query: searchText,
                values: [organization.name, organization.localizedName, organization.city])
        }
    }

    private var allOrganizationSectionsAreEmpty: Bool {
        manageableOrganizations.isEmpty && organizationRequests.isEmpty
    }

    private func organizationRole(for organization: Organization) -> ManagedOrganizationRole? {
        guard let authorityUser else { return nil }
        if organization.ownerId == authorityUser.id {
            return .owner
        }
        if PermissionService.canUseOwnerOrganizationOverride(user: authorityUser) {
            return .platformOwner
        }
        if organization.adminIds.contains(authorityUser.id) {
            return .admin
        }
        if organization.moderatorIds.contains(authorityUser.id) {
            return .moderator
        }
        return nil
    }

    private var canCreateOrganization: Bool {
        PermissionService.canCreateOrganization(user: authorityUser)
    }

    private var managementTitle: String {
        PermissionService.isAppOwner(user: authorityUser)
            ? OwnerProfileText.organizations
            : AppStrings.Profile.myOrganizations
    }

    var body: some View {
        ProfileDestinationLayout(
            title: managementTitle,
            introSubtitle: AppStrings.Profile.organizationManagementIntro
        ) {
            if canCreateOrganization {
                createOrganizationCard
            }

            searchControls
            managedOrganizationsContent
        }
        .task(id: "\(accessIdentity)-\(searchText)-\(region?.rawValue ?? "all")") {
            // This screen exposes current server-authorized roles. A shared
            // editor snapshot may survive an account switch and may contain an
            // organization deleted by another account, so reconcile it here.
            if !searchText.isEmpty { try? await Task.sleep(for: .milliseconds(300)); guard !Task.isCancelled else { return } }
            await authoringOrganizations.loadIfNeeded(actor: authorityUser, search: searchText, region: region, organizationID: focusedOrganizationID)
        }
        .task(id: accessIdentity) {
            await organizationsViewModel.loadOrganizationRequests(for: authorityUser)
        }
        .appRefreshable {
            await reloadOrganizations()
            await organizationsViewModel.loadOrganizationRequests(for: authorityUser)
            invalidateStats()
        }
        .onReceive(NotificationCenter.default.publisher(for: .organizationsChanged).debounce(for: .milliseconds(250), scheduler: RunLoop.main)) { _ in
            Task {
                await reloadOrganizations()
                await organizationsViewModel.loadOrganizationRequests(for: authorityUser)
                invalidateStats()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newsChanged)) { _ in invalidateStats() }
        .onReceive(NotificationCenter.default.publisher(for: .eventsChanged)) { _ in invalidateStats() }
        .onChange(of: accessIdentity) { _, _ in
            authoringOrganizations.reset()
            editingOrganizationRequest = nil
            previewingOrganizationRequest = nil
            pendingDeleteOrganizationRequest = nil
            isShowingCreateOrganization = false
            organizationContentStats = [:]
            loadingContentStatOrganizationIDs = []
            OrganizationManagementContentStatsCache.removeAll()
        }

        .sheet(isPresented: $isShowingCreateOrganization) {
            NavigationStack {
                OrganizationEditorView(
                    organizationsViewModel: organizationsViewModel,
                    legalDocumentRepository: legalDocumentRepository,
                    onSaved: {
                                    await organizationsViewModel.loadOrganizationRequests(for: authorityUser)
                    }
                )
            }
            .environmentObject(authState)
        }
        .sheet(item: $editingOrganizationRequest) { organization in
            NavigationStack {
                OrganizationEditorView(
                    organizationsViewModel: organizationsViewModel,
                    organization: organization,
                    legalDocumentRepository: legalDocumentRepository,
                    onSaved: {
                        await organizationsViewModel.loadOrganizationRequests(for: authorityUser)
                    }
                )
            }
            .environmentObject(authState)
        }
        .sheet(item: $previewingOrganizationRequest) { organization in
            NavigationStack {
                OrganizationRequestPreviewView(organization: organization)
            }
        }
        .appDestructiveActionDialog(Binding(
            get: {
                guard let organization = pendingDeleteOrganizationRequest else { return nil }
                let isPending = organization.moderationStatus == .pendingReview
                return AppDestructiveActionDialog(
                    title: isPending
                        ? AppStrings.Organizations.withdrawRequestTitle
                        : AppStrings.Organizations.deleteRequestTitle,
                    message: AppStrings.Organizations.requestDeleteMessage,
                    destructiveActionTitle: isPending
                        ? AppStrings.Organizations.withdrawRequest
                        : AppStrings.Organizations.deleteRequest
                ) {
                    Task { await deleteOrganizationRequest(organization) }
                }
            },
            set: { if $0 == nil { pendingDeleteOrganizationRequest = nil } }
        ))
        .appErrorDialog($deleteRequestErrorDialog)
    }

    private var createOrganizationCard: some View {
        Button {
            isShowingCreateOrganization = true
        } label: {
            SoftContentCard(padding: AppTheme.rowCardPadding) {
                AppNavigationRow(
                    title: AppStrings.Profile.ownerCreateOrganization,
                    subtitle: OrganizationWorkspaceCopy.createSubtitle,
                    systemImage: "plus.circle"
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("organization.management.create")
        .accessibilityLabel(AppStrings.Profile.ownerCreateOrganization)
    }

    @ViewBuilder
    private var managedOrganizationsContent: some View {
        if (organizationsViewModel.isLoading || authoringOrganizations.isLoading || !authoringOrganizations.hasLoaded && authoringOrganizations.error == nil) && allOrganizationSectionsAreEmpty {
            LoadingStateCard(title: nil)
                .accessibilityIdentifier("organization.management.loading")
        } else if let error = authoringOrganizations.error, organizationRequests.isEmpty {
            // Cached organizations include role-bearing fields. If the server
            // cannot confirm them, keep the snapshot for a retry but do not
            // present its owner/admin/moderator role as current authority.
            ErrorStateCard(
                title: managementTitle,
                message: organizationErrorMessage(error),
                retryTitle: AppStrings.Action.retry
            ) {
                Task {
                    await reloadOrganizations()
                            await organizationsViewModel.loadOrganizationRequests(for: authorityUser)
                }
            }
        } else if let error = organizationsViewModel.error, allOrganizationSectionsAreEmpty {
            ErrorStateCard(
                title: managementTitle,
                message: organizationErrorMessage(error),
                retryTitle: AppStrings.Action.retry
            ) {
                Task {
                    await reloadOrganizations()
                            await organizationsViewModel.loadOrganizationRequests(for: authorityUser)
                }
            }
        } else if allOrganizationSectionsAreEmpty {
            ProfileDestinationEmptyStateCard(
                systemImage: "building.2",
                title: managementTitle,
                message: !searchText.isEmpty || region != nil ? OrganizationWorkspaceCopy.noMatches : AppStrings.Profile.noOrganizations
            )
            .accessibilityIdentifier("organization.management.empty")
        } else {
            if let error = authoringOrganizations.error {
                ErrorStateCard(
                    title: managementTitle,
                    message: organizationErrorMessage(error),
                    retryTitle: AppStrings.Action.retry
                ) {
                    Task {
                        await reloadOrganizations()
                                    await organizationsViewModel.loadOrganizationRequests(for: authorityUser)
                    }
                }
            }

            if !manageableOrganizations.isEmpty {
                AppEditorSectionTitle(title: AppStrings.Profile.managedOrganizations)
                    .padding(.horizontal, 2)

                LazyVStack(spacing: AppTheme.feedRowSpacing) {
                    ForEach(manageableOrganizations) { organization in
                        ManagedOrganizationCard(
                            organization: organization,
                            role: organizationRole(for: organization) ?? .moderator,
                            organizationsViewModel: organizationsViewModel,
                            contentStats: organizationContentStats[organization.id],
                            isLoadingContentStats: loadingContentStatOrganizationIDs.contains(organization.id),
                            statsError: statsErrors[organization.id],
                            retryStats: { Task { await loadStats(for: organization.id, force: true) } },
                            newsRepository: newsRepository, eventRepository: eventRepository
                        )
                        .accessibilityIdentifier("organization.management.card.\(organization.id)")
                        .task(id: "\(accessIdentity)-\(organization.id)-\(statsEpoch)") { await loadStats(for: organization.id) }
                    }
                }
            }

            if authoringOrganizations.hasMore {
                PrimaryActionButton(title: AppStrings.Search.loadMoreContent, isEnabled: !authoringOrganizations.isLoading,
                    isLoading: authoringOrganizations.isLoading, systemImage: "arrow.down.circle") {
                    Task { await authoringOrganizations.load(actor: authorityUser, search: searchText, region: region, more: true, organizationID: focusedOrganizationID) }
                }.accessibilityIdentifier("organization.management.more")
            }

            if !organizationRequests.isEmpty {
                AppEditorSectionTitle(title: AppStrings.Profile.organizationRequests)
                    .padding(.horizontal, 2)

                LazyVStack(spacing: AppTheme.feedRowSpacing) {
                    ForEach(organizationRequests) { organization in
                        OrganizationRequestCard(
                            organization: organization,
                            previewAction: {
                                previewingOrganizationRequest = organization
                            },
                            editAction: {
                                editingOrganizationRequest = organization
                            },
                            deleteAction: {
                                pendingDeleteOrganizationRequest = organization
                            }
                        )
                    }
                }
            }

            if let error = organizationsViewModel.error {
                InlineMessageCard(style: .error, message: organizationErrorMessage(error))
            }
        }
    }

    private func deleteOrganizationRequest(_ organization: Organization) async {
        do {
            try await organizationsViewModel.deleteOrganization(id: organization.id, user: authorityUser)
            pendingDeleteOrganizationRequest = nil
        } catch {
            deleteRequestErrorDialog = AppErrorDialog(
                message: AppStrings.Organizations.requestDeleteFailed
            )
        }
    }

    private func organizationErrorMessage(_ error: AppError) -> String {
        switch error {
        case .network:
            AppStrings.Organizations.loadNetworkError
        case .permissionDenied:
            AppStrings.Organizations.loadPermissionError
        case .validationFailed, .notFound:
            AppStrings.Organizations.loadValidationError
        case .unknown:
            AppStrings.Organizations.loadUnknownError
        }
    }

    private func reloadOrganizations() async {
        await authoringOrganizations.load(actor: authorityUser, search: searchText, region: region, organizationID: focusedOrganizationID)
    }
    private func invalidateStats() {
        OrganizationManagementContentStatsCache.removeAll(); organizationContentStats = [:]; statsErrors = [:]; loadingContentStatOrganizationIDs = []; statsEpoch = UUID()
    }
    private var searchControls: some View {
        VStack(spacing: 12) {
            AppSearchField(placeholder: OrganizationWorkspaceCopy.search, text: $searchText,
                           focus: $searchFocused, fieldID: "organization.management.search")
            Picker(AppStrings.Profile.region, selection: $region) {
                Text(OrganizationWorkspaceCopy.allRegions).tag(Optional<AustrianFederalState>.none)
                ForEach(AustrianFederalState.allCases) { Text($0.displayName).tag(Optional($0)) }
            }.pickerStyle(.menu).tint(AppTheme.accentPrimaryForeground).frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("organization.management.region")
        }
    }
    private func loadStats(for id: String, force: Bool = false) async {
        let expected = accessIdentity, epoch = statsEpoch
        guard let user = authorityUser, !loadingContentStatOrganizationIDs.contains(id) else { return }
        if !force, let cached = OrganizationManagementContentStatsCache.stats(for: id) { organizationContentStats[id] = cached; return }
        loadingContentStatOrganizationIDs.insert(id); statsErrors[id] = nil
        defer { if accessIdentity == expected, statsEpoch == epoch { loadingContentStatOrganizationIDs.remove(id) } }
        do {
            let stats: ManagedOrganizationContentStats
            if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
                async let news = newsRepository.fetchOrganizationNewsCount(organizationID: id)
                async let events = eventRepository.fetchOrganizationEventCount(organizationID: id)
                stats = try await .init(newsCount: news, eventCount: events)
            } else {
                let response: OrganizationWorkspaceResponse = try await RefreshRequest.run {
                    try await CloudFunctionsClient.shared.call(.manageOrganizationWorkspace,
                        request: OrganizationWorkspaceRequest(action: "stats", principalId: user.id, organizationId: id))
                }
                stats = .init(newsCount: response.counts?["news"] ?? 0, eventCount: response.counts?["events"] ?? 0)
            }
            guard accessIdentity == expected, statsEpoch == epoch else { return }
            organizationContentStats[id] = stats; OrganizationManagementContentStatsCache.store(stats, for: id)
        } catch {
            if accessIdentity == expected, statsEpoch == epoch { statsErrors[id] = AppStrings.Organizations.loadUnknownError }
        }
    }
}
