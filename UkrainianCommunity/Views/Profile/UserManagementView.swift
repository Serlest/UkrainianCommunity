import SwiftUI

private enum UserManagementFilter: String, CaseIterable, Identifiable {
    case all
    case active
    case warned
    case suspended
    case banned
    case deactivated
    case organizationOwners
    case organizationAdmins
    case organizationModerators

    var id: String { rawValue }
    var isOrganizationFilter: Bool {
        switch self {
        case .organizationOwners, .organizationAdmins, .organizationModerators: true
        default: false
        }
    }

    var title: String {
        switch self {
        case .all:
            AppStrings.UserManagement.filterAll
        case .active:
            AppStrings.UserManagement.unrestrictedStatus
        case .warned:
            AppStrings.UserManagement.filterWarned
        case .suspended:
            AppStrings.UserManagement.filterSuspended
        case .banned:
            AppStrings.UserManagement.filterBanned
        case .deactivated:
            AppStrings.Common.deactivated
        case .organizationOwners:
            AppStrings.UserManagement.filterOrganizationOwners
        case .organizationAdmins:
            AppStrings.UserManagement.filterOrganizationAdmins
        case .organizationModerators:
            AppStrings.UserManagement.filterOrganizationModerators
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
        case .deactivated:
            "person.crop.circle.badge.xmark"
        case .organizationOwners:
            "crown"
        case .organizationAdmins:
            "person.badge.key"
        case .organizationModerators:
            "shield"
        }
    }

    func matches(_ user: AppUser, organizationRoles: [UserOrganizationRole]) -> Bool {
        switch self {
        case .all:
            true
        case .active:
            user.managedAccountState == .active
        case .warned:
            user.managedAccountState == .warned
        case .suspended:
            user.managedAccountState == .suspendedUntil || user.managedAccountState == .blocked
        case .banned:
            user.managedAccountState == .bannedPermanent
        case .deactivated:
            user.managedAccountState == .deactivated
        case .organizationOwners:
            organizationRoles.contains { $0.role == .communityOwner }
        case .organizationAdmins:
            organizationRoles.contains { $0.role == .communityAdmin }
        case .organizationModerators:
            organizationRoles.contains { $0.role == .communityModerator }
        }
    }
}

private struct ManagedUserRoute: Identifiable, Hashable {
    let user: AppUser
    var id: String { user.id }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct UserManagementView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel: UserManagementViewModel

    init(reads: UserManagementReads? = nil) {
        _viewModel = StateObject(wrappedValue: UserManagementViewModel(reads: reads))
    }
    @State private var selectedUserRoute: ManagedUserRoute?
    @State private var selectedRegion: String?
    @State private var searchText = ""
    @State private var selectedFilter: UserManagementFilter = .all
    @State private var sortOption: AppListSortOption = .newest
    @State private var isShowingRoleGuide = false
    @FocusState private var isSearchFocused: Bool

    private var directoryQuery: UserDirectoryQuery {
        UserDirectoryQuery(search: normalizedSearch, region: selectedRegion, filter: selectedFilter.rawValue, sort: sortOption.rawValue)
    }
    private var actor: AppUser? { authState.user }
    private var canAccessUserManagement: Bool {
        PermissionService.canManageUsers(user: actor)
    }

    private var actorLoadKey: String {
        guard let actor else { return "signed-out" }
        return "\(actor.id)|\(actor.globalRole.authorizationRole.rawValue)|\(canAccessUserManagement)"
    }

    private var filteredUsers: [AppUser] {
        if viewModel.usesDirectory { return viewModel.users }
        return candidateUsers.filter { user in
            selectedFilter.matches(user, organizationRoles: viewModel.organizationRoles(for: user))
        }.sorted(by: userSort)
    }

    private var normalizedSearch: String {
        LocalSearchMatcher.normalized(searchText)
    }

    private var candidateUsers: [AppUser] {
        if normalizedSearch.isEmpty && selectedRegion == nil {
            return viewModel.users
        }
        if normalizedSearch.count < 2 && selectedRegion == nil {
            return viewModel.users.filter { user in
                LocalSearchMatcher.matches(
                    query: normalizedSearch,
                    values: [user.displayName, user.fullName, user.email, user.telegramUsername ?? "", user.id]
                )
            }
        }
        return viewModel.searchResults
    }

    var body: some View {
        AdminScreenShell(
            title: AppStrings.UserManagement.title,
            subtitle: "",
            tabBarHidden: true
        ) {
            userManagementContent
        }
        .onChange(of: actorLoadKey) { _, _ in selectedUserRoute = nil }
        .onChange(of: viewModel.mutationRevision) { _, _ in
            guard viewModel.usesDirectory else { return }
            Task { await viewModel.loadDirectory(actor: actor, query: directoryQuery) }
        }
        .task(id: actorLoadKey) {
            if !viewModel.usesDirectory { await viewModel.load(actor: actor) }
        }
        .task(id: "\(actorLoadKey)|\(normalizedSearch)|\(selectedRegion ?? "all")|\(selectedFilter.rawValue)|\(sortOption.rawValue)") {
            if viewModel.usesDirectory {
                viewModel.prepareDirectory(actor: actor, query: directoryQuery)
                try? await Task.sleep(for: .milliseconds(searchText.isEmpty ? 0 : 350))
                guard !Task.isCancelled else { return }
                await viewModel.ensureDirectory(actor: actor, query: directoryQuery)
                return
            }
            guard normalizedSearch.count >= 2 || selectedRegion != nil else {
                viewModel.clearSearch()
                return
            }
            viewModel.prepareSearch()
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await viewModel.search(query: normalizedSearch, actor: actor, region: selectedRegion)
        }
        .appRefreshable {
            if viewModel.usesDirectory { await viewModel.loadDirectory(actor: actor, query: directoryQuery); return }
            await viewModel.refresh(actor: actor)
            if normalizedSearch.count >= 2 || selectedRegion != nil {
                await viewModel.search(query: normalizedSearch, actor: actor, region: selectedRegion)
            }
        }
        .navigationDestination(item: $selectedUserRoute) { route in
            UserDetailView(userID: route.user.id, fallbackUser: route.user, viewModel: viewModel, actor: actor)
                .toolbar(.hidden, for: .tabBar)
        }
        .alert(AppStrings.UserManagement.title, isPresented: Binding(
            get: { selectedUserRoute == nil && viewModel.statusMessage != nil },
            set: { if !$0 { viewModel.statusMessage = nil } }
        )) {
            Button(AppStrings.Common.ok, role: .cancel) {}
        } message: {
            Text(viewModel.statusMessage ?? "")
        }
        .sheet(isPresented: $isShowingRoleGuide) {
            UserRolePermissionsSheet()
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
                if normalizedSearch.count == 1 && !viewModel.usesDirectory {
                    Label(AppStrings.UserManagement.searchMinimumCharacters, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
                filterRow
                contentList
            }
        }
    }

    private var summaryCard: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                HStack(spacing: AppTheme.eventsMetadataSpacing) {
                    Label(viewModel.totalRegisteredUsers.map(String.init) ?? "—", systemImage: "person.3")
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

                if viewModel.usesDirectory && (!viewModel.isDirectoryCurrent(actor: actor, query: directoryQuery) || !viewModel.directoryHasLoaded) {
                    Text(AppStrings.UserManagement.searching).font(.caption).foregroundStyle(AppTheme.textSecondary)
                } else {
                Text(AppStrings.UserManagement.loadedCount(viewModel.usesDirectory ? viewModel.users.count : selectedRegion == nil ? viewModel.users.count : viewModel.searchResults.count, total: viewModel.usesDirectory ? viewModel.directoryTotal : selectedRegion == nil ? viewModel.totalRegisteredUsers : viewModel.searchTotalMatches))
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .accessibilityIdentifier("userManagement.loadedCount")

                }

                Button {
                    isShowingRoleGuide = true
                } label: {
                    Label(AppStrings.UserManagement.roleGuideButton, systemImage: "questionmark.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppTheme.accentPrimaryForeground)
                .accessibilityIdentifier("userManagement.roleGuide")

            }
        }
    }

    private var searchField: some View {
        AppSearchField(placeholder: AppStrings.UserManagement.searchPlaceholder, text: $searchText, focus: $isSearchFocused, fieldID: "userManagement.search")
    }

    private var filterRow: some View {
        VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
            Picker(AppStrings.UserManagement.regionFilter, selection: $selectedRegion) {
                Text(AppStrings.UserManagement.allRegions).tag(String?.none)
                ForEach(AustrianFederalState.allCases) { region in Text(region.displayName).tag(Optional(region.rawValue)) }
                Text(AppStrings.UserManagement.unknownRegion).tag(Optional("unknown"))
            }.pickerStyle(.menu).tint(AppTheme.accentPrimaryForeground)
            .accessibilityIdentifier("userManagement.regionFilter")
            if selectedRegion != nil && !viewModel.usesDirectory {
                Text(AppStrings.UserManagement.regionMatches(viewModel.searchTotalMatches))
                    .font(.caption).foregroundStyle(AppTheme.textSecondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack { filterMenu; Spacer(minLength: 8); sortMenu }
                VStack(alignment: .leading, spacing: 8) { filterMenu; sortMenu }
            }
            if !viewModel.usesDirectory && (viewModel.regionalNextCursor != nil || (viewModel.canLoadMore && normalizedSearch.count < 2 && selectedRegion == nil)) {
                Text(AppStrings.UserManagement.loadedScope)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker(AppStrings.UserManagement.title, selection: $selectedFilter) {
                ForEach(UserManagementFilter.allCases) { filter in
                    Text(viewModel.usesDirectory ? filter.title : "\(filter.title) · \(countLabel(for: filter))").tag(filter)
                        .disabled(!viewModel.usesDirectory && filter.isOrganizationFilter && !viewModel.organizationsLoaded)
                }
            }
        } label: {
            AppFilterChip(title: selectedFilter.title, systemImage: selectedFilter.systemImage, isSelected: true)
        }
        .accessibilityIdentifier("userManagement.filter")
    }

    private var sortMenu: some View {
        AppSortMenu(selection: $sortOption, options: [.newest, .oldest, .nameAscending, .nameDescending])
            .accessibilityIdentifier("userManagement.sort")
    }

    private func userSort(_ lhs: AppUser, _ rhs: AppUser) -> Bool {
        switch sortOption {
        case .newest:
            lhs.createdAt == rhs.createdAt ? lhs.id < rhs.id : lhs.createdAt > rhs.createdAt
        case .oldest:
            lhs.createdAt == rhs.createdAt ? lhs.id < rhs.id : lhs.createdAt < rhs.createdAt
        case .nameAscending:
            compareUserNames(lhs, rhs, ascending: true)
        case .nameDescending:
            compareUserNames(lhs, rhs, ascending: false)
        case .popular:
            lhs.createdAt == rhs.createdAt ? lhs.id < rhs.id : lhs.createdAt > rhs.createdAt
        }
    }

    private func compareUserNames(_ lhs: AppUser, _ rhs: AppUser, ascending: Bool) -> Bool {
        let result = LocalizationStore.compareForSorting(lhs.preferredDisplayName, rhs.preferredDisplayName)
        guard result != .orderedSame else { return lhs.id < rhs.id }
        return ascending ? result == .orderedAscending : result == .orderedDescending
    }

    @ViewBuilder
    private var contentList: some View {
        if viewModel.usesDirectory && (!viewModel.isDirectoryCurrent(actor: actor, query: directoryQuery) || !viewModel.directoryHasLoaded && viewModel.error == nil) {
            LoadingStateCard(title: AppStrings.UserManagement.title)
                .accessibilityIdentifier("userManagement.loading")
        } else if viewModel.isSearching {
            LoadingStateCard(title: AppStrings.UserManagement.searching)
        } else if (normalizedSearch.count >= 2 || selectedRegion != nil) && viewModel.searchFailed {
            UnifiedEmptyStateCard(systemImage: "exclamationmark.triangle", title: AppStrings.UserManagement.title,
                                  message: AppStrings.UserManagement.searchFailed) {
                PrimaryActionButton(title: AppStrings.UserManagement.retry, systemImage: "arrow.clockwise") {
                    Task { await viewModel.search(query: normalizedSearch, actor: actor, region: selectedRegion) }
                }
            }
            .accessibilityIdentifier("userManagement.searchError")
        } else if viewModel.isLoading && viewModel.users.isEmpty {
            LoadingStateCard(title: AppStrings.UserManagement.title)
        } else if viewModel.users.isEmpty, viewModel.error != nil {
            UnifiedEmptyStateCard(
                systemImage: "exclamationmark.triangle",
                title: AppStrings.UserManagement.title,
                message: AppStrings.UserManagement.loadError
            ) {
                PrimaryActionButton(title: AppStrings.UserManagement.retry, systemImage: "arrow.clockwise") {
                    Task { if viewModel.usesDirectory { await viewModel.loadDirectory(actor: actor, query: directoryQuery) } else { await viewModel.refresh(actor: actor) } }
                }
            }
        } else if !viewModel.usesDirectory && selectedFilter.isOrganizationFilter && !viewModel.organizationsLoaded {
            InlineMessageCard(style: .error, message: AppStrings.UserManagement.organizationsNotLoaded)
            PrimaryActionButton(title: AppStrings.UserManagement.retry, systemImage: "arrow.clockwise") {
                Task { if viewModel.usesDirectory { await viewModel.loadDirectory(actor: actor, query: directoryQuery) } else { await viewModel.refresh(actor: actor) } }
            }
        } else if filteredUsers.isEmpty {
            VStack(spacing: AppTheme.dashboardSpacing) {
                UnifiedEmptyStateCard(
                    systemImage: "person.crop.circle.badge.questionmark",
                    title: AppStrings.UserManagement.noResultsTitle,
                    message: AppStrings.UserManagement.noResultsMessage
                )
                loadMoreButton
            }
        } else {
            LazyVStack(spacing: AppTheme.feedRowSpacing) {
                if viewModel.error != nil {
                    InlineMessageCard(style: .error, message: AppStrings.UserManagement.refreshFailed)
                }
                ForEach(filteredUsers) { user in
                    ManagedUserRow(user: user, organizationRoles: viewModel.organizationRoles(for: user))
                        .contentShape(Rectangle())
                        .onTapGesture { selectedUserRoute = ManagedUserRoute(user: user) }
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction { selectedUserRoute = ManagedUserRoute(user: user) }
                        .accessibilityIdentifier("userManagement.user.\(user.id)")
                }
                if viewModel.usesDirectory || selectedRegion != nil || normalizedSearch.count < 2 {
                    loadMoreButton
                } else if normalizedSearch.count >= 2 {
                    VStack(spacing: 6) {
                        Text(AppStrings.UserManagement.searchResultSummary(shown: filteredUsers.count, found: viewModel.searchTotalMatches))
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)

                        if viewModel.searchTotalMatches > viewModel.searchResults.count {
                            Label(
                                LocalizationStore.localizedFormat(
                                    "user_management.search.result_limit_notice",
                                    defaultValue: "Показано перші %lld із %lld збігів. Уточніть пошук.",
                                    arguments: [viewModel.searchResults.count, viewModel.searchTotalMatches]
                                ),
                                systemImage: "info.circle"
                            )
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("userManagement.searchLimitNotice")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
    }

    @ViewBuilder
    private var loadMoreButton: some View {
        if viewModel.usesDirectory {
            if viewModel.directoryCursor != nil {
                PrimaryActionButton(title: AppStrings.UserManagement.loadMore, isEnabled: !viewModel.isLoading && !viewModel.isLoadingMore, isLoading: viewModel.isLoadingMore, systemImage: "arrow.down.circle") {
                    Task { await viewModel.loadDirectory(actor: actor, query: directoryQuery, more: true) }
                }
            }
        } else if selectedRegion != nil, viewModel.regionalNextCursor != nil {
            PrimaryActionButton(title: AppStrings.UserManagement.loadMore, isEnabled: !viewModel.isLoadingMore,
                isLoading: viewModel.isLoadingMore, systemImage: "arrow.down.circle") {
                Task { await viewModel.loadMoreRegional(actor: actor) }
            }
        } else if selectedRegion == nil && viewModel.canLoadMore {
            PrimaryActionButton(
                title: AppStrings.UserManagement.loadMore,
                isEnabled: !viewModel.isLoadingMore,
                isLoading: viewModel.isLoadingMore,
                systemImage: "arrow.down.circle"
            ) {
                Task { await viewModel.loadMore(actor: actor) }
            }
        }
    }

    private func countLabel(for filter: UserManagementFilter) -> String {
        filter.isOrganizationFilter && !viewModel.organizationsLoaded ? "—" : String(count(for: filter))
    }

    private func count(for filter: UserManagementFilter) -> Int {
        candidateUsers.filter {
            filter.matches($0, organizationRoles: viewModel.organizationRoles(for: $0))
        }.count
    }

}
