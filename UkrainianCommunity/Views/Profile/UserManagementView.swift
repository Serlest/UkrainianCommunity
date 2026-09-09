import SwiftUI

private enum UserManagementFilter: CaseIterable, Identifiable {
    case all
    case active
    case warned
    case suspended
    case banned
    case organizationOwners
    case organizationAdmins
    case organizationModerators

    var id: String { title }
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
            AppStrings.UserManagement.filterActive
        case .warned:
            AppStrings.UserManagement.filterWarned
        case .suspended:
            AppStrings.UserManagement.filterSuspended
        case .banned:
            AppStrings.UserManagement.filterBanned
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
            user.blockState == .active && user.accountStatus == .active
        case .warned:
            user.blockState == .warned || user.accountStatus == .warned
        case .suspended:
            user.blockState == .suspendedUntil || user.blockState == .blocked || user.accountStatus == .suspendedUntil || user.accountStatus == .temporarilyBanned
        case .banned:
            user.blockState == .bannedPermanent || user.blockState == .deactivated || user.accountStatus == .bannedPermanent || user.accountStatus == .permanentlyBanned || user.accountStatus == .deactivated
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
    @State private var searchText = ""
    @State private var selectedFilter: UserManagementFilter = .all
    @State private var sortOption: AppListSortOption = .newest
    @State private var isShowingRoleGuide = false
    @FocusState private var isSearchFocused: Bool

    private var actor: AppUser? { authState.user }
    private var canAccessUserManagement: Bool {
        PermissionService.canManageUsers(user: actor)
    }

    private var actorLoadKey: String {
        guard let actor else { return "signed-out" }
        return "\(actor.id)|\(actor.globalRole.authorizationRole.rawValue)|\(canAccessUserManagement)"
    }

    private var filteredUsers: [AppUser] {
        candidateUsers.filter { user in
            selectedFilter.matches(user, organizationRoles: viewModel.organizationRoles(for: user))
        }.sorted(by: userSort)
    }

    private var normalizedSearch: String {
        LocalSearchMatcher.normalized(searchText)
    }

    private var candidateUsers: [AppUser] {
        if normalizedSearch.isEmpty {
            return viewModel.users
        }
        if normalizedSearch.count < 2 {
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
            subtitle: AppStrings.UserManagement.contentSubtitle,
            tabBarHidden: false
        ) {
            userManagementContent
        }
        .onChange(of: actorLoadKey) { _, _ in selectedUserRoute = nil }
        .task(id: actorLoadKey) {
            await viewModel.load(actor: actor)
        }
        .task(id: normalizedSearch) {
            guard normalizedSearch.count >= 2 else {
                viewModel.clearSearch()
                return
            }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await viewModel.search(query: normalizedSearch, actor: actor)
        }
        .appRefreshable {
            await viewModel.refresh(actor: actor)
            if normalizedSearch.count >= 2 {
                await viewModel.search(query: normalizedSearch, actor: actor)
            }
        }
        .navigationDestination(item: $selectedUserRoute) { route in
            UserDetailView(userID: route.user.id, fallbackUser: route.user, viewModel: viewModel, actor: actor)
        }
        .alert(AppStrings.UserManagement.title, isPresented: Binding(
            get: { viewModel.statusMessage != nil },
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
                if normalizedSearch.count == 1 {
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
                    Label("\(viewModel.users.count)", systemImage: "person.3")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Text(viewModel.canLoadMore ? AppStrings.UserManagement.loadedUsers : AppStrings.UserManagement.registeredUsers)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)

                    Spacer(minLength: 0)

                    if viewModel.isLoading {
                        ProgressView()
                    }
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
                .accessibilityIdentifier("userManagement.search")
                .submitLabel(.search)
                .onSubmit { isSearchFocused = false }

            if !searchText.isEmpty {
                AppSearchClearButton {
                    searchText = ""
                }
            }


            if viewModel.isSearching {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, AppTheme.inputHorizontalPadding)
        .frame(minHeight: AppTheme.searchControlHeight)
        .background(AppTheme.surfaceControl.opacity(0.45), in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle)
        )
    }

    private var filterRow: some View {
        VStack(alignment: .leading, spacing: AppTheme.eventsMetadataSpacing) {
            ViewThatFits(in: .horizontal) {
                HStack { filterMenu; Spacer(minLength: 8); sortMenu }
                VStack(alignment: .leading, spacing: 8) { filterMenu; sortMenu }
            }
            if viewModel.canLoadMore && normalizedSearch.count < 2 {
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
                    Text("\(filter.title) · \(countLabel(for: filter))").tag(filter)
                        .disabled(filter.isOrganizationFilter && !viewModel.organizationsLoaded)
                }
            }
        } label: {
            AppFilterChip(title: selectedFilter.title, systemImage: selectedFilter.systemImage, isSelected: true)
        }
        .accessibilityIdentifier("userManagement.filter")
    }

    private var sortMenu: some View {
        AppSortMenu(selection: $sortOption, options: [.newest, .oldest, .nameAscending, .nameDescending])
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
        if viewModel.isSearching {
            LoadingStateCard(title: AppStrings.UserManagement.searching)
        } else if normalizedSearch.count >= 2 && viewModel.searchFailed {
            UnifiedEmptyStateCard(systemImage: "exclamationmark.triangle", title: AppStrings.UserManagement.title,
                                  message: AppStrings.UserManagement.searchFailed) {
                PrimaryActionButton(title: AppStrings.UserManagement.retry, systemImage: "arrow.clockwise") {
                    Task { await viewModel.search(query: normalizedSearch, actor: actor) }
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
                    Task { await viewModel.refresh(actor: actor) }
                }
            }
        } else if selectedFilter.isOrganizationFilter && !viewModel.organizationsLoaded {
            InlineMessageCard(style: .error, message: AppStrings.UserManagement.organizationsNotLoaded)
            PrimaryActionButton(title: AppStrings.UserManagement.retry, systemImage: "arrow.clockwise") {
                Task { await viewModel.refresh(actor: actor) }
            }
        } else if filteredUsers.isEmpty {
            VStack(spacing: AppTheme.dashboardSpacing) {
                UnifiedEmptyStateCard(
                    systemImage: "person.crop.circle.badge.questionmark",
                    title: AppStrings.UserManagement.noResultsTitle,
                    message: AppStrings.UserManagement.noResultsMessage
                )
                if normalizedSearch.count < 2 { loadMoreButton }
            }
        } else {
            VStack(spacing: AppTheme.feedRowSpacing) {
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
                if normalizedSearch.count < 2 {
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
        if viewModel.canLoadMore {
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
