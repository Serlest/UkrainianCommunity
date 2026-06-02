import Combine
import SwiftUI

struct OrganizationManagementHubView: View {
    @EnvironmentObject private var authState: AuthState
    let focusedOrganizationID: String?

    private let repository: OrganizationRepository
    private let newsRepository: NewsRepository
    private let eventRepository: EventRepository
    @StateObject private var organizationsViewModel: OrganizationsViewModel
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
        repository: OrganizationRepository = FirestoreOrganizationRepository(),
        newsRepository: NewsRepository = FirestoreNewsRepository(),
        eventRepository: EventRepository = FirestoreEventRepository()
    ) {
        self.focusedOrganizationID = focusedOrganizationID
        self.repository = repository
        self.newsRepository = newsRepository
        self.eventRepository = eventRepository
        _organizationsViewModel = StateObject(wrappedValue: OrganizationsViewModel(repository: repository))
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
                organizationsViewModel.resetForAuthChange()
            } else {
                Task {
                    organizationsViewModel.resetForAuthChange()
                    organizationContentStats = [:]
                    loadingContentStatOrganizationIDs = []
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
            if loadingContentStatOrganizationIDs.contains(organizationID) {
                continue
            }

            loadingContentStatOrganizationIDs.insert(organizationID)
            do {
                async let newsCount = newsRepository.fetchOrganizationNewsCount(organizationID: organizationID)
                async let eventCount = eventRepository.fetchOrganizationEventCount(organizationID: organizationID)
                organizationContentStats[organizationID] = ManagedOrganizationContentStats(
                    newsCount: try await newsCount,
                    eventCount: try await eventCount
                )
            } catch {
                organizationContentStats[organizationID] = nil
            }
            loadingContentStatOrganizationIDs.remove(organizationID)
        }
    }
}
