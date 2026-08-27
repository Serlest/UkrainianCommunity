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
        .appRefreshable {
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
            SoftContentCard(padding: AppTheme.rowCardPadding) {
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
        } else if let error = organizationsViewModel.error, allOrganizationSectionsAreEmpty {
            ErrorStateCard(
                title: AppStrings.Profile.myOrganizations,
                message: organizationErrorMessage(error),
                retryTitle: AppStrings.Action.retry
            ) {
                Task {
                    await organizationsViewModel.refresh()
                    await organizationsViewModel.loadOrganizationRequests(for: authorityUser)
                }
            }
        } else if allOrganizationSectionsAreEmpty {
            ProfileDestinationEmptyStateCard(
                systemImage: "building.2",
                title: AppStrings.Profile.myOrganizations,
                message: AppStrings.Profile.noOrganizations
            )
        } else {
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
                            isLoadingContentStats: loadingContentStatOrganizationIDs.contains(organization.id)
                        )
                    }
                }
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

    private func loadManageableOrganizationContentStats(force: Bool = false) async {
        let organizationIDs = Set(manageableOrganizations.map(\.id))
        organizationContentStats = organizationContentStats.filter { organizationIDs.contains($0.key) }
        loadingContentStatOrganizationIDs = loadingContentStatOrganizationIDs.intersection(organizationIDs)

        var organizationIDsToLoad: [String] = []
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
            organizationIDsToLoad.append(organizationID)
        }

        // Start a small batch at a time. Network work can overlap while the cap
        // prevents the platform-owner account from issuing an unbounded burst.
        for batchStart in stride(from: 0, to: organizationIDsToLoad.count, by: 4) {
            let batchEnd = min(batchStart + 4, organizationIDsToLoad.count)
            let batch = organizationIDsToLoad[batchStart..<batchEnd]
            let tasks = batch.map { organizationID in
                Task { @MainActor in
                    (organizationID, await fetchContentStats(for: organizationID))
                }
            }

            for task in tasks {
                let (organizationID, stats) = await task.value
                organizationContentStats[organizationID] = stats
                if let stats {
                    OrganizationManagementContentStatsCache.store(stats, for: organizationID)
                }
                loadingContentStatOrganizationIDs.remove(organizationID)
            }
        }
    }

    private func fetchContentStats(for organizationID: String) async -> ManagedOrganizationContentStats? {
        do {
            async let newsCount = RefreshRequest.run { [self] in
                try await newsRepository.fetchOrganizationNewsCount(organizationID: organizationID)
            }
            async let eventCount = RefreshRequest.run { [self] in
                try await eventRepository.fetchOrganizationEventCount(organizationID: organizationID)
            }
            return ManagedOrganizationContentStats(
                newsCount: try await newsCount,
                eventCount: try await eventCount
            )
        } catch {
            return nil
        }
    }
}
