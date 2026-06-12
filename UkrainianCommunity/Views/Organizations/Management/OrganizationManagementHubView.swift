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
    let focusedOrganizationID: String?

    private let repository: OrganizationRepository
    private let newsRepository: NewsRepository
    private let eventRepository: EventRepository
    @ObservedObject private var organizationsViewModel: OrganizationsViewModel
    @State private var isShowingCreateOrganization = false
    @State private var editingOrganizationRequest: Organization?
    @State private var previewingOrganizationRequest: Organization?
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
        eventRepository: EventRepository = FirestoreEventRepository()
    ) {
        self.focusedOrganizationID = focusedOrganizationID
        self.organizationsViewModel = organizationsViewModel
        self.repository = repository
        self.newsRepository = newsRepository
        self.eventRepository = eventRepository
    }

    private var manageableOrganizations: [Organization] {
        guard let authorityUser else { return [] }
        let organizations = PermissionService.manageableOrganizations(
            from: organizationsViewModel.organizations,
            user: authorityUser
        )
        guard let focusedOrganizationID else { return organizations }
        return organizations.filter { $0.id == focusedOrganizationID }
    }

    private var organizationRequests: [Organization] {
        focusedOrganizationID == nil ? organizationsViewModel.organizationRequests : []
    }

    private var subscribedOrganizations: [Organization] {
        guard focusedOrganizationID == nil else { return [] }
        let managedIDs = Set(manageableOrganizations.map(\.id))
        let requestIDs = Set(organizationRequests.map(\.id))
        return organizationsViewModel.organizations
            .filter {
                $0.isSubscribed
                    && $0.moderationStatus == .approved
                    && !managedIDs.contains($0.id)
                    && !requestIDs.contains($0.id)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var allOrganizationSectionsAreEmpty: Bool {
        manageableOrganizations.isEmpty && organizationRequests.isEmpty && subscribedOrganizations.isEmpty
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

    var body: some View {
        ProfileDestinationLayout(
            title: AppStrings.Profile.myOrganizations,
            introSubtitle: AppStrings.Profile.organizationManagementIntro
        ) {
            if canCreateOrganization {
                createOrganizationCard
            }

            managedOrganizationsContent
        }
        .task {
            await organizationsViewModel.loadIfNeeded()
            await organizationsViewModel.refreshIfStale()
            await organizationsViewModel.loadOrganizationRequests(for: authorityUser)
            await loadManageableOrganizationContentStats()
        }
        .refreshable {
            await organizationsViewModel.refresh()
            await organizationsViewModel.loadOrganizationRequests(for: authorityUser)
            await loadManageableOrganizationContentStats(force: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .organizationsChanged).debounce(for: .milliseconds(250), scheduler: RunLoop.main)) { _ in
            Task {
                await organizationsViewModel.refresh()
                await organizationsViewModel.loadOrganizationRequests(for: authorityUser)
                await loadManageableOrganizationContentStats(force: true)
            }
        }
        .onChange(of: authState.user?.id) { _, newUserID in
            if newUserID == nil {
                isShowingCreateOrganization = false
                organizationContentStats = [:]
                loadingContentStatOrganizationIDs = []
                OrganizationManagementContentStatsCache.removeAll()
            } else {
                Task {
                    organizationContentStats = [:]
                    loadingContentStatOrganizationIDs = []
                    OrganizationManagementContentStatsCache.removeAll()
                    await organizationsViewModel.refresh()
                    await organizationsViewModel.loadOrganizationRequests(for: authorityUser)
                    await loadManageableOrganizationContentStats(force: true)
                }
            }
        }
        .sheet(isPresented: $isShowingCreateOrganization) {
            NavigationStack {
                OrganizationEditorView(
                    organizationsViewModel: organizationsViewModel,
                    onSaved: {
                        await organizationsViewModel.refresh()
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
    }

    private var createOrganizationCard: some View {
        Button {
            isShowingCreateOrganization = true
        } label: {
            AppEditorSectionCard {
                AppNavigationRow(
                    title: AppStrings.Profile.ownerCreateOrganization,
                    subtitle: AppStrings.Profile.organizationManagementSubtitle,
                    systemImage: "plus.circle",
                    accessory: .none
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("organization.management.create")
        .accessibilityLabel(AppStrings.Profile.ownerCreateOrganization)
    }

    @ViewBuilder
    private var managedOrganizationsContent: some View {
        if organizationsViewModel.isLoading && allOrganizationSectionsAreEmpty {
            LoadingStateCard(title: nil)
        } else if allOrganizationSectionsAreEmpty {
            ProfileDestinationEmptyStateCard(
                systemImage: "building.2",
                title: AppStrings.Profile.myOrganizations,
                message: AppStrings.Profile.noOrganizations
            )
        } else {
            if !manageableOrganizations.isEmpty {
                VStack(spacing: AppTheme.feedRowSpacing) {
                    ForEach(manageableOrganizations) { organization in
                        ManagedOrganizationCard(
                            organization: organization,
                            role: organizationRole(for: organization) ?? .moderator,
                            organizationsViewModel: organizationsViewModel,
                            contentStats: organizationContentStats[organization.id],
                            isLoadingContentStats: loadingContentStatOrganizationIDs.contains(organization.id)
                        )
                    }
                }
            }

            if !organizationRequests.isEmpty {
                AppEditorSectionCard {
                    AppEditorSectionTitle(title: AppStrings.Profile.organizationRequests)
                }

                VStack(spacing: AppTheme.feedRowSpacing) {
                    ForEach(organizationRequests) { organization in
                        OrganizationRequestCard(
                            organization: organization,
                            previewAction: {
                                previewingOrganizationRequest = organization
                            },
                            editAction: {
                                editingOrganizationRequest = organization
                            }
                        )
                    }
                }
            }

            if !subscribedOrganizations.isEmpty {
                AppEditorSectionCard {
                    AppEditorSectionTitle(title: AppStrings.Profile.subscribedOrganizations)
                }

                VStack(spacing: AppTheme.feedRowSpacing) {
                    ForEach(subscribedOrganizations) { organization in
                        NavigationLink {
                            OrganizationDetailView(
                                viewModel: organizationsViewModel,
                                organizationID: organization.id
                            )
                        } label: {
                            ProfileOrganizationListCard(organization: organization)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func loadManageableOrganizationContentStats(force: Bool = false) async {
        let organizationIDs = Set(manageableOrganizations.map(\.id))
        organizationContentStats = organizationContentStats.filter { organizationIDs.contains($0.key) }
        loadingContentStatOrganizationIDs = loadingContentStatOrganizationIDs.intersection(organizationIDs)

        for organizationID in organizationIDs.sorted() {
            if !force && organizationContentStats[organizationID] != nil {
                continue
            }
            if !force, let cachedStats = OrganizationManagementContentStatsCache.stats(for: organizationID) {
                organizationContentStats[organizationID] = cachedStats
                continue
            }
            if loadingContentStatOrganizationIDs.contains(organizationID) {
                continue
            }

            loadingContentStatOrganizationIDs.insert(organizationID)
            do {
                async let newsCount = newsRepository.fetchOrganizationNewsCount(organizationID: organizationID)
                async let eventCount = eventRepository.fetchOrganizationEventCount(organizationID: organizationID)
                let stats = ManagedOrganizationContentStats(
                    newsCount: try await newsCount,
                    eventCount: try await eventCount
                )
                organizationContentStats[organizationID] = stats
                OrganizationManagementContentStatsCache.store(stats, for: organizationID)
            } catch {
                organizationContentStats[organizationID] = nil
            }
            loadingContentStatOrganizationIDs.remove(organizationID)
        }
    }
}
