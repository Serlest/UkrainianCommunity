import Combine
import FirebaseFirestore
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

private enum UserAdminAction: String {
    case warningIssued
    case suspended
    case banned
    case unblocked
    case deactivated

    var title: String {
        switch self {
        case .warningIssued:
            AppStrings.UserManagement.actionWarn
        case .suspended:
            AppStrings.UserManagement.actionSuspend
        case .banned:
            AppStrings.UserManagement.actionBan
        case .unblocked:
            AppStrings.UserManagement.actionUnblock
        case .deactivated:
            AppStrings.UserManagement.actionDeactivate
        }
    }

    var systemImage: String {
        switch self {
        case .warningIssued:
            "exclamationmark.triangle"
        case .suspended:
            "clock.badge.exclamationmark"
        case .banned:
            "lock"
        case .unblocked:
            "lock.open"
        case .deactivated:
            "person.crop.circle.badge.xmark"
        }
    }
}

private struct ManagedOrganization: Identifiable, Hashable {
    let id: String
    let name: String
    let city: String
    let logoURL: String?
    let ownerId: String?
    let adminIds: [String]
    let moderatorIds: [String]

    func role(for userId: String) -> CommunityRole? {
        if ownerId == userId { return .communityOwner }
        if adminIds.contains(userId) { return .communityAdmin }
        if moderatorIds.contains(userId) { return .communityModerator }
        return nil
    }
}

private struct UserOrganizationRole: Identifiable, Hashable {
    let organization: ManagedOrganization
    let role: CommunityRole

    var id: String { organization.id }
}

@MainActor
private final class UserManagementViewModel: ObservableObject {
    @Published private(set) var users: [AppUser] = []
    @Published private(set) var organizations: [ManagedOrganization] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: AppError?
    @Published var statusMessage: String?
    @Published private(set) var updatingUserIDs = Set<String>()

    private let db = Firestore.firestore()
    private var hasLoaded = false

    private var usersCollection: CollectionReference { db.collection("users") }
    private var organizationsCollection: CollectionReference { db.collection("organizations") }
    private var auditCollection: CollectionReference { db.collection("auditLogs") }

    func loadIfNeeded(actor: AppUser?) async {
        guard !hasLoaded else { return }
        await refresh(actor: actor)
    }

    func refresh(actor: AppUser?) async {
        guard isOwner(actor) else {
            users = []
            organizations = []
            hasLoaded = true
            return
        }

        isLoading = true
        error = nil
        defer {
            isLoading = false
            hasLoaded = true
        }

        do {
            async let usersSnapshot = usersCollection.order(by: "createdAt", descending: true).getDocuments()
            async let organizationsSnapshot = organizationsCollection.getDocuments()
            let snapshots = try await (usersSnapshot, organizationsSnapshot)
            users = snapshots.0.documents.map(makeUser(from:))
            organizations = snapshots.1.documents
                .map(makeManagedOrganization(from:))
                .filter { $0.id != Organization.systemOrganizationID }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            self.error = .network
        }
    }

    func perform(_ action: UserAdminAction, target: AppUser, actor: AppUser, reason: String) async {
        guard canManage(target: target, actor: actor) else {
            statusMessage = AppStrings.UserManagement.statusPermissionDenied
            return
        }

        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalReason = trimmedReason.isEmpty ? "Owner action" : trimmedReason
        let previousValue = [
            "blockState": target.blockState.rawValue,
            "accountStatus": target.accountStatus.rawValue,
            "warningCount": String(target.warningCount)
        ]
        let payload: [String: Any]
        let newValue: [String: String]

        switch action {
        case .warningIssued:
            payload = [
                "blockState": UserBlockState.warned.rawValue,
                "accountStatus": AccountStatus.warned.rawValue,
                "warningCount": FieldValue.increment(Int64(1)),
                "isBlocked": false,
                "updatedAt": FieldValue.serverTimestamp()
            ]
            newValue = ["blockState": UserBlockState.warned.rawValue, "accountStatus": AccountStatus.warned.rawValue]
        case .suspended:
            let suspendedUntil = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date().addingTimeInterval(7 * 24 * 60 * 60)
            payload = [
                "blockState": UserBlockState.suspendedUntil.rawValue,
                "accountStatus": AccountStatus.suspendedUntil.rawValue,
                "banExpiresAt": Timestamp(date: suspendedUntil),
                "isBlocked": true,
                "updatedAt": FieldValue.serverTimestamp()
            ]
            newValue = ["blockState": UserBlockState.suspendedUntil.rawValue, "accountStatus": AccountStatus.suspendedUntil.rawValue]
        case .banned:
            payload = [
                "blockState": UserBlockState.bannedPermanent.rawValue,
                "accountStatus": AccountStatus.bannedPermanent.rawValue,
                "banExpiresAt": FieldValue.delete(),
                "isBlocked": true,
                "updatedAt": FieldValue.serverTimestamp()
            ]
            newValue = ["blockState": UserBlockState.bannedPermanent.rawValue, "accountStatus": AccountStatus.bannedPermanent.rawValue]
        case .unblocked:
            payload = [
                "blockState": UserBlockState.active.rawValue,
                "accountStatus": AccountStatus.active.rawValue,
                "banExpiresAt": FieldValue.delete(),
                "isBlocked": false,
                "updatedAt": FieldValue.serverTimestamp()
            ]
            newValue = ["blockState": UserBlockState.active.rawValue, "accountStatus": AccountStatus.active.rawValue]
        case .deactivated:
            payload = [
                "blockState": UserBlockState.deactivated.rawValue,
                "accountStatus": AccountStatus.deactivated.rawValue,
                "banExpiresAt": FieldValue.delete(),
                "isBlocked": true,
                "updatedAt": FieldValue.serverTimestamp()
            ]
            newValue = ["blockState": UserBlockState.deactivated.rawValue, "accountStatus": AccountStatus.deactivated.rawValue]
        }

        await updateUser(target, actor: actor) {
            try await usersCollection.document(target.id).updateData(payload)
            try await writeAuditLog(
                actionType: action.rawValue,
                targetUserId: target.id,
                performedBy: actor.id,
                reason: finalReason,
                previousValue: previousValue,
                newValue: newValue
            )
        }
    }

    func assignRole(_ role: CommunityRole, in organization: ManagedOrganization, to target: AppUser, actor: AppUser, reason: String) async {
        guard canManage(target: target, actor: actor) else {
            statusMessage = AppStrings.UserManagement.rolePermissionDenied
            return
        }

        if role == .communityOwner {
            await changeOwner(in: organization, to: target, actor: actor, reason: reason)
            return
        }

        guard role != .member else { return }

        await updateUser(target, actor: actor) {
            try await updateOrganizationRole(
                role: role,
                organization: organization,
                target: target,
                actor: actor,
                reason: reason,
                isRemoval: false
            )
        }
    }

    func changeOwner(in organization: ManagedOrganization, to target: AppUser, actor: AppUser, reason: String) async {
        guard canManage(target: target, actor: actor), isOwner(actor) else {
            statusMessage = AppStrings.UserManagement.ownerChangePermissionDenied
            return
        }

        guard organization.ownerId != target.id else {
            statusMessage = AppStrings.UserManagement.ownerChangeSelectNewOwner
            return
        }

        await updateUser(target, actor: actor) {
            try await updateOrganizationOwner(
                organization: organization,
                newOwner: target,
                actor: actor,
                reason: reason
            )
        }
    }

    func removeRole(in organization: ManagedOrganization, from target: AppUser, actor: AppUser, reason: String) async {
        guard canManage(target: target, actor: actor) else {
            statusMessage = AppStrings.UserManagement.removeRolePermissionDenied
            return
        }

        await updateUser(target, actor: actor) {
            try await updateOrganizationRole(
                role: .member,
                organization: organization,
                target: target,
                actor: actor,
                reason: reason,
                isRemoval: true
            )
        }
    }

    func canManage(target: AppUser, actor: AppUser) -> Bool {
        isOwner(actor)
    }

    func user(withID id: String) -> AppUser? {
        users.first { $0.id == id }
    }

    func organizationRoles(for user: AppUser) -> [UserOrganizationRole] {
        organizations.compactMap { organization in
            guard let role = organization.role(for: user.id) else { return nil }
            return UserOrganizationRole(organization: organization, role: role)
        }
    }

    private func updateUser(_ target: AppUser, actor: AppUser, operation: () async throws -> Void) async {
        guard !updatingUserIDs.contains(target.id) else { return }
        updatingUserIDs.insert(target.id)
        statusMessage = nil
        defer { updatingUserIDs.remove(target.id) }

        do {
            try await operation()
            statusMessage = AppStrings.UserManagement.changesSaved
            await refresh(actor: actor)
        } catch {
            self.error = .permissionDenied
            statusMessage = AppStrings.UserManagement.changesFailed
        }
    }

    private func updateOrganizationRole(
        role: CommunityRole,
        organization: ManagedOrganization,
        target: AppUser,
        actor: AppUser,
        reason: String,
        isRemoval: Bool
    ) async throws {
        let organizationReference = organizationsCollection.document(organization.id)
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalReason = trimmedReason.isEmpty ? "Organization role update" : trimmedReason

        _ = try await db.runTransaction { transaction, errorPointer in
            do {
                let organizationSnapshot = try transaction.getDocument(organizationReference)
                guard let organizationData = organizationSnapshot.data() else {
                    errorPointer?.pointee = AppError.notFound.asNSError
                    return nil
                }

                let currentOwnerId = organizationData["ownerId"] as? String
                let currentAdminIds = organizationData["adminIds"] as? [String] ?? []
                let currentModeratorIds = organizationData["moderatorIds"] as? [String] ?? []
                let previousRole = Self.role(
                    for: target.id,
                    ownerId: currentOwnerId,
                    adminIds: currentAdminIds,
                    moderatorIds: currentModeratorIds
                )

                if isRemoval, currentOwnerId == target.id {
                    errorPointer?.pointee = AppError.permissionDenied.asNSError
                    return nil
                }

                if !isRemoval, currentOwnerId == target.id, role != .communityOwner {
                    errorPointer?.pointee = AppError.permissionDenied.asNSError
                    return nil
                }

                var updatedAdminIds = currentAdminIds.filter { $0 != target.id }
                var updatedModeratorIds = currentModeratorIds.filter { $0 != target.id }
                var organizationUpdate: [String: Any] = [
                    "adminIds": updatedAdminIds,
                    "moderatorIds": updatedModeratorIds,
                    "updatedAt": FieldValue.serverTimestamp()
                ]

                if !isRemoval {
                    switch role {
                    case .communityOwner:
                        organizationUpdate["ownerId"] = target.id
                    case .communityAdmin:
                        updatedAdminIds = Array(Set(updatedAdminIds + [target.id])).sorted()
                        organizationUpdate["adminIds"] = updatedAdminIds
                    case .communityModerator:
                        updatedModeratorIds = Array(Set(updatedModeratorIds + [target.id])).sorted()
                        organizationUpdate["moderatorIds"] = updatedModeratorIds
                    case .member:
                        break
                    }
                }

                transaction.updateData(organizationUpdate, forDocument: organizationReference)

                transaction.setData([
                    "actionType": isRemoval ? "organizationRoleRemoved" : "organizationRoleAssigned",
                    "targetUserId": target.id,
                    "performedBy": actor.id,
                    "createdAt": FieldValue.serverTimestamp(),
                    "reason": finalReason,
                    "note": NSNull(),
                    "previousValue": [
                        "organizationId": organization.id,
                        "role": previousRole?.rawValue ?? "none"
                    ],
                    "newValue": [
                        "organizationId": organization.id,
                        "role": isRemoval ? "none" : role.rawValue
                    ]
                ], forDocument: self.auditCollection.document())
            } catch {
                errorPointer?.pointee = error as NSError
            }

            return nil
        }
    }

    private func updateOrganizationOwner(
        organization: ManagedOrganization,
        newOwner: AppUser,
        actor: AppUser,
        reason: String
    ) async throws {
        let organizationReference = organizationsCollection.document(organization.id)
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalReason = trimmedReason.isEmpty ? "Organization owner changed" : trimmedReason

        _ = try await db.runTransaction { transaction, errorPointer in
            do {
                let organizationSnapshot = try transaction.getDocument(organizationReference)
                guard let organizationData = organizationSnapshot.data() else {
                    errorPointer?.pointee = AppError.notFound.asNSError
                    return nil
                }

                let currentOwnerId = organizationData["ownerId"] as? String
                let currentAdminIds = organizationData["adminIds"] as? [String] ?? []
                let currentModeratorIds = organizationData["moderatorIds"] as? [String] ?? []
                let oldOwnerId = currentOwnerId ?? ""

                guard actor.globalRole.authorizationRole == .owner,
                      !newOwner.id.isEmpty,
                      currentOwnerId != newOwner.id else {
                    errorPointer?.pointee = AppError.permissionDenied.asNSError
                    return nil
                }

                transaction.updateData([
                    "ownerId": newOwner.id,
                    "adminIds": currentAdminIds.filter { $0 != newOwner.id && $0 != oldOwnerId },
                    "moderatorIds": currentModeratorIds.filter { $0 != newOwner.id && $0 != oldOwnerId },
                    "updatedAt": FieldValue.serverTimestamp()
                ], forDocument: organizationReference)

                transaction.setData([
                    "actionType": "organizationOwnerChanged",
                    "targetUserId": newOwner.id,
                    "performedBy": actor.id,
                    "createdAt": FieldValue.serverTimestamp(),
                    "reason": finalReason,
                    "note": NSNull(),
                    "previousValue": [
                        "organizationId": organization.id,
                        "ownerId": currentOwnerId ?? "none"
                    ],
                    "newValue": [
                        "organizationId": organization.id,
                        "ownerId": newOwner.id
                    ]
                ], forDocument: self.auditCollection.document())
            } catch {
                errorPointer?.pointee = error as NSError
            }

            return nil
        }
    }

    private func writeAuditLog(
        actionType: String,
        targetUserId: String,
        performedBy: String,
        reason: String,
        previousValue: [String: String],
        newValue: [String: String]
    ) async throws {
        try await auditCollection.document().setData([
            "actionType": actionType,
            "targetUserId": targetUserId,
            "performedBy": performedBy,
            "createdAt": FieldValue.serverTimestamp(),
            "reason": reason,
            "note": NSNull(),
            "previousValue": previousValue,
            "newValue": newValue
        ])
    }

    private func makeUser(from document: QueryDocumentSnapshot) -> AppUser {
        let data = document.data()
        let legacyRole = UserRole(rawValue: data["role"] as? String ?? "") ?? .user
        let globalRole = (data["globalRole"] as? String).flatMap(GlobalRole.init(rawValue:)) ?? .user
        let isBlocked = data["isBlocked"] as? Bool ?? false
        let blockState = UserBlockState(rawValue: data["blockState"] as? String ?? "") ?? (isBlocked ? .suspendedUntil : .active)
        return AppUser(
            id: data["id"] as? String ?? document.documentID,
            fullName: data["fullName"] as? String ?? "",
            displayName: data["displayName"] as? String ?? data["fullName"] as? String ?? "",
            city: data["city"] as? String ?? "",
            email: data["email"] as? String ?? "",
            avatarURL: (data["avatarURL"] as? String).flatMap(URL.init(string:)),
            bio: data["bio"] as? String ?? "",
            telegramUsername: data["telegramUsername"] as? String,
            role: legacyRole,
            globalRole: globalRole,
            moderatorSections: (data["moderatorSections"] as? [String] ?? []).compactMap(AppSection.init(rawValue:)),
            canManageGuide: data["canManageGuide"] as? Bool ?? false,
            blockState: blockState,
            accountStatus: (data["accountStatus"] as? String).flatMap(AccountStatus.init(rawValue:)) ?? (blockState.isRestricted ? .suspendedUntil : .active),
            banExpiresAt: (data["banExpiresAt"] as? Timestamp)?.dateValue(),
            warningCount: data["warningCount"] as? Int ?? 0,
            communityMemberships: [],
            selectedFederalState: (data["selectedFederalState"] as? String).flatMap(AustrianFederalState.init(rawValue:)),
            acceptedTermsAt: (data["acceptedTermsAt"] as? Timestamp)?.dateValue(),
            acceptedPrivacyAt: (data["acceptedPrivacyAt"] as? Timestamp)?.dateValue(),
            termsVersion: data["termsVersion"] as? String,
            privacyVersion: data["privacyVersion"] as? String,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? .distantPast,
            updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? .distantPast
        )
    }

    private func makeManagedOrganization(from document: QueryDocumentSnapshot) -> ManagedOrganization {
        let data = document.data()
        return ManagedOrganization(
            id: document.documentID,
            name: data["name"] as? String ?? document.documentID,
            city: data["city"] as? String ?? "",
            logoURL: data["logoURL"] as? String ?? data["imageURL"] as? String,
            ownerId: data["ownerId"] as? String,
            adminIds: data["adminIds"] as? [String] ?? [],
            moderatorIds: data["moderatorIds"] as? [String] ?? []
        )
    }

    private func isOwner(_ user: AppUser?) -> Bool {
        user?.globalRole.authorizationRole == .owner
    }

    private static func role(
        for userID: String,
        ownerId: String?,
        adminIds: [String],
        moderatorIds: [String]
    ) -> CommunityRole? {
        if ownerId == userID { return .communityOwner }
        if adminIds.contains(userID) { return .communityAdmin }
        if moderatorIds.contains(userID) { return .communityModerator }
        return nil
    }
}

struct UserManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel = UserManagementViewModel()
    @State private var searchText = ""
    @State private var selectedFilter: UserManagementFilter = .all
    @FocusState private var isSearchFocused: Bool

    private var actor: AppUser? { authState.user }
    private var canAccessUserManagement: Bool {
        actor?.globalRole.authorizationRole == .owner
    }

    private var filteredUsers: [AppUser] {
        viewModel.users.filter { user in
            selectedFilter.matches(user, organizationRoles: viewModel.organizationRoles(for: user)) && matchesSearch(user)
        }
    }

    var body: some View {
        ZStack {
            AppBackgroundView()
                .allowsHitTesting(false)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    AppCenteredBrandHeader {
                        AppGlassIconButton(systemImage: "chevron.left", accessibilityLabel: AppStrings.Common.back) {
                            dismiss()
                        }
                    } trailingContent: {
                        EmptyView()
                    }

                    AppGroupedContentPlane {
                        userManagementContent
                    }
                }
                .padding(.horizontal, AppTheme.pageHorizontal)
                .padding(.top, AppTheme.sectionSpacing)
                .padding(.bottom, AppTheme.homeBottomContentPadding)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .tint(AppTheme.accentPrimary)
        .navigationTitle(AppStrings.UserManagement.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(AppStrings.Common.done) {
                    isSearchFocused = false
                }
            }
        }
        .task {
            await viewModel.loadIfNeeded(actor: actor)
        }
        .refreshable {
            await viewModel.refresh(actor: actor)
        }
        .alert(AppStrings.UserManagement.title, isPresented: Binding(
            get: { viewModel.statusMessage != nil },
            set: { if !$0 { viewModel.statusMessage = nil } }
        )) {
            Button(AppStrings.Common.ok, role: .cancel) {}
        } message: {
            Text(viewModel.statusMessage ?? "")
        }
    }

    @ViewBuilder
    private var userManagementContent: some View {
        VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
            AppEditorSectionCard {
                SectionHeaderBlock(
                    title: AppStrings.UserManagement.title,
                    subtitle: AppStrings.UserManagement.contentSubtitle
                )
            }

            if !canAccessUserManagement {
                UnifiedEmptyStateCard(
                    systemImage: "lock.shield",
                    title: AppStrings.UserManagement.title,
                    message: AppStrings.UserManagement.permission
                )
            } else {
                summaryCard
                searchField
                filterRow
                contentList
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            isSearchFocused = false
        }
    }

    private var summaryCard: some View {
        AppEditorSectionCard {
            HStack(spacing: AppTheme.eventsMetadataSpacing) {
                Label("\(viewModel.users.count)", systemImage: "person.3")
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

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AppTheme.inputHorizontalPadding)
        .frame(height: AppTheme.searchControlHeight)
        .background(AppTheme.surfaceControl.opacity(0.45), in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                .strokeBorder(AppTheme.borderSubtle)
        )
    }

    private var filterRow: some View {
        AppHorizontalFilterRow {
            ForEach(UserManagementFilter.allCases) { filter in
                Button {
                    selectedFilter = filter
                } label: {
                    AppFilterChip(
                        title: filter.title,
                        systemImage: filter.systemImage,
                        isSelected: selectedFilter == filter
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var contentList: some View {
        if viewModel.isLoading && viewModel.users.isEmpty {
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
        } else if filteredUsers.isEmpty {
            UnifiedEmptyStateCard(
                systemImage: "person.crop.circle.badge.questionmark",
                title: AppStrings.UserManagement.noResultsTitle,
                message: AppStrings.UserManagement.noResultsMessage
            )
        } else {
            VStack(spacing: AppTheme.feedRowSpacing) {
                ForEach(filteredUsers) { user in
                    NavigationLink {
                        UserDetailView(
                            userID: user.id,
                            fallbackUser: user,
                            viewModel: viewModel,
                            actor: actor
                        )
                    } label: {
                        ManagedUserRow(user: user, organizationRoles: viewModel.organizationRoles(for: user))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func matchesSearch(_ user: AppUser) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }

        return [
            user.displayName,
            user.fullName,
            user.email,
            user.telegramUsername ?? "",
            user.id,
            user.city,
            user.selectedFederalState?.rawValue ?? ""
        ]
        .contains { $0.lowercased().contains(query) }
    }
}

private struct ManagedUserRow: View {
    let user: AppUser
    let organizationRoles: [UserOrganizationRole]

    var body: some View {
        AppEditorSectionCard {
            HStack(alignment: .center, spacing: 12) {
                UserAvatarView(user: user, size: 46)

                VStack(alignment: .leading, spacing: 6) {
                    Text(user.preferredDisplayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .lineLimit(1)

                    Text(secondaryLine)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        UserStatusBadge(title: user.blockState.title, tint: statusTint)

                        if !user.city.isEmpty {
                            UserStatusBadge(title: user.city, tint: AppTheme.textSecondary)
                        }

                        if let primaryOrganizationRole {
                            UserStatusBadge(title: primaryOrganizationRole, tint: AppTheme.accentPrimary)
                        }

                        if organizationRoles.count > 1 {
                            UserStatusBadge(title: AppStrings.UserManagement.organizationRolesAdditionalCount(organizationRoles.count), tint: AppTheme.accentPrimary)
                        }
                    }
                }

                Spacer(minLength: 0)

                Text(LocalizationStore.dateString(from: user.createdAt, dateStyle: .short, timeStyle: .none))
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private var secondaryLine: String {
        if !user.email.isEmpty { return user.email }
        if let telegramUsername = user.telegramUsername, !telegramUsername.isEmpty { return telegramUsername }
        return user.id
    }

    private var statusTint: Color {
        switch user.blockState {
        case .active:
            AppTheme.accentPrimary
        case .warned:
            AppTheme.accentSupport
        case .suspendedUntil, .blocked, .bannedPermanent, .deactivated:
            AppTheme.accentDestructive
        }
    }

    private var primaryOrganizationRole: String? {
        if organizationRoles.contains(where: { $0.role == .communityOwner }) { return AppStrings.UserManagement.organizationOwnerRole }
        if organizationRoles.contains(where: { $0.role == .communityAdmin }) { return AppStrings.UserManagement.organizationAdminRole }
        if organizationRoles.contains(where: { $0.role == .communityModerator }) { return AppStrings.UserManagement.organizationModeratorRole }
        return nil
    }
}

private enum UserDetailFocusField {
    case organizationSearch
    case reason
}

private struct UserDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let userID: String
    let fallbackUser: AppUser
    @ObservedObject var viewModel: UserManagementViewModel
    let actor: AppUser?

    @State private var selectedOrganizationID: String?
    @State private var selectedRole: CommunityRole = .communityModerator
    @State private var organizationSearchText = ""
    @State private var reason = ""
    @State private var pendingAction: UserAdminAction?
    @State private var pendingRoleRemoval: ManagedOrganization?
    @FocusState private var focusedField: UserDetailFocusField?

    private var selectedOrganization: ManagedOrganization? {
        organizations.first { $0.id == selectedOrganizationID }
    }

    private var user: AppUser {
        viewModel.user(withID: userID) ?? fallbackUser
    }

    private var organizations: [ManagedOrganization] {
        viewModel.organizations
    }

    private var organizationRoles: [UserOrganizationRole] {
        viewModel.organizationRoles(for: user)
    }

    private var filteredOrganizations: [ManagedOrganization] {
        let query = organizationSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return organizations }

        return organizations.filter { organization in
            [organization.name, organization.city, organization.id]
                .contains { $0.lowercased().contains(query) }
        }
    }

    private var canAssignSelectedOrganizationRole: Bool {
        guard let selectedOrganization else { return false }
        let query = organizationSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty || filteredOrganizations.contains(where: { $0.id == selectedOrganization.id }) else {
            return false
        }
        if selectedRole == .communityOwner {
            return selectedOrganization.ownerId != user.id
        }
        return true
    }

    private var assignableRoles: [CommunityRole] {
        guard selectedOrganization?.ownerId != user.id else {
            return [.communityOwner]
        }
        return [.communityOwner, .communityAdmin, .communityModerator]
    }

    private var isUpdating: Bool {
        viewModel.updatingUserIDs.contains(userID)
    }

    private var canManage: Bool {
        actor.map { viewModel.canManage(target: user, actor: $0) } ?? false
    }

    var body: some View {
        ZStack {
            AppBackgroundView()
                .allowsHitTesting(false)

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                    AppCenteredBrandHeader {
                        AppGlassIconButton(systemImage: "chevron.left", accessibilityLabel: AppStrings.Common.back) {
                            dismiss()
                        }
                    } trailingContent: {
                        EmptyView()
                    }

                    AppGroupedContentPlane {
                        VStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                            profileCard
                            organizationRolesCard
                            roleAssignmentCard
                            accountActionsCard
                            UserAuditHistoryCard(userId: user.id)
                        }
                    }
                }
                .padding(.horizontal, AppTheme.pageHorizontal)
                .padding(.top, AppTheme.sectionSpacing)
                .padding(.bottom, AppTheme.homeBottomContentPadding)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable {
                await viewModel.refresh(actor: actor)
                ensureSelectedOrganization()
                ensureSelectedRole()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            focusedField = nil
        }
        .navigationTitle(user.preferredDisplayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(AppStrings.Common.done) {
                    focusedField = nil
                }
            }
        }
        .task {
            ensureSelectedOrganization()
            ensureSelectedRole()
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
        .confirmationDialog(
            pendingAction?.title ?? AppStrings.UserManagement.actionFallbackTitle,
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingAction {
                Button(pendingAction.title, role: pendingAction == .unblocked ? nil : .destructive) {
                    guard let actor else { return }
                    let currentUser = user
                    Task { await viewModel.perform(pendingAction, target: currentUser, actor: actor, reason: reason) }
                    reason = ""
                }
            }
            Button(AppStrings.Common.cancel, role: .cancel) {}
        } message: {
            Text(AppStrings.UserManagement.actionAuditNotice)
        }
        .confirmationDialog(
            AppStrings.UserManagement.removeOrganizationRoleTitle,
            isPresented: Binding(
                get: { pendingRoleRemoval != nil },
                set: { if !$0 { pendingRoleRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingRoleRemoval {
                Button(AppStrings.UserManagement.removeOrganizationRoleButton, role: .destructive) {
                    guard let actor else { return }
                    let currentUser = user
                    Task { await viewModel.removeRole(in: pendingRoleRemoval, from: currentUser, actor: actor, reason: reason) }
                    reason = ""
                }
            }
            Button(AppStrings.Common.cancel, role: .cancel) {}
        } message: {
            Text(AppStrings.UserManagement.removeOwnerRoleWarning)
        }
    }

    private var profileCard: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                HStack(spacing: 12) {
                    UserAvatarView(user: user, size: 64)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(user.preferredDisplayName)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(AppTheme.textPrimary)

                        Text(user.email.isEmpty ? user.id : user.email)
                            .font(.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            UserStatusBadge(title: user.blockState.title, tint: statusTint)
                            UserStatusBadge(title: user.globalRole.title, tint: user.globalRole.authorizationRole == .owner ? AppTheme.accentSupport : AppTheme.textSecondary)
                        }

                        if !organizationRoles.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(organizationRoles.prefix(3)) { item in
                                    UserStatusBadge(title: roleTitle(item.role), tint: AppTheme.accentPrimary)
                                }
                            }
                        }
                    }
                }

                Divider()

                UserManagementMetadataRow(systemImage: "number", title: "UID", value: user.id)
                UserManagementMetadataRow(systemImage: "at", title: "Telegram", value: user.telegramUsername ?? AppStrings.Common.notAvailable)
                UserManagementMetadataRow(systemImage: "mappin.and.ellipse", title: AppStrings.UserManagement.cityRegion, value: locationText)
                UserManagementMetadataRow(systemImage: "calendar", title: "Joined", value: LocalizationStore.dateString(from: user.createdAt, dateStyle: .medium, timeStyle: .none))
                UserManagementMetadataRow(systemImage: "building.2", title: AppStrings.UserManagement.organizationRolesTitle, value: String(organizationRoles.count))
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
                                .foregroundStyle(AppTheme.accentPrimary)
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
                                    .foregroundStyle(AppTheme.accentDestructive)
                            }
                            .disabled(!canManage || item.role == .communityOwner || isUpdating)
                        }
                    }
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
                        Button {
                            organizationSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(AppTheme.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, AppTheme.inputHorizontalPadding)
                .frame(height: AppTheme.searchControlHeight)
                .background(AppTheme.surfaceControl.opacity(0.45), in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous)
                        .strokeBorder(AppTheme.borderSubtle)
                )
                .disabled(organizations.isEmpty || !canManage)

                Picker(AppStrings.UserManagement.organizationPicker, selection: Binding(
                    get: { selectedOrganizationID ?? organizations.first?.id ?? "" },
                    set: { selectedOrganizationID = $0 }
                )) {
                    ForEach(filteredOrganizations) { organization in
                        Text(organization.name).tag(organization.id)
                    }
                }
                .pickerStyle(.menu)
                .disabled(filteredOrganizations.isEmpty || !canManage)

                if organizations.isEmpty {
                    Text(AppStrings.UserManagement.organizationsNotLoaded)
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
                .disabled(!canManage)

                if selectedOrganization?.ownerId == user.id {
                    Text(AppStrings.UserManagement.ownerTransferOnly)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }

                TextField(AppStrings.UserManagement.reasonPlaceholder, text: $reason, axis: .vertical)
                    .lineLimit(2...4)
                    .font(.subheadline)
                    .padding(AppTheme.inputHorizontalPadding)
                    .background(AppTheme.surfaceControl.opacity(0.36), in: RoundedRectangle(cornerRadius: AppTheme.chipRadius, style: .continuous))
                    .focused($focusedField, equals: .reason)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }

                PrimaryActionButton(
                    title: selectedRole == .communityOwner ? AppStrings.UserManagement.changeOwnerButton : AppStrings.UserManagement.assignRoleButton,
                    isEnabled: canManage && canAssignSelectedOrganizationRole,
                    isLoading: isUpdating,
                    systemImage: selectedRole == .communityOwner ? "person.crop.circle.badge.checkmark" : "person.badge.key"
                ) {
                    guard let selectedOrganization else { return }
                    guard let actor else { return }
                    let currentUser = user
                    if selectedRole == .communityOwner {
                        Task { await viewModel.changeOwner(in: selectedOrganization, to: currentUser, actor: actor, reason: reason) }
                    } else {
                        Task { await viewModel.assignRole(selectedRole, in: selectedOrganization, to: currentUser, actor: actor, reason: reason) }
                    }
                    reason = ""
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

                Button { pendingAction = .warningIssued } label: {
                    actionLabel(.warningIssued, tint: AppTheme.accentSupport)
                }
                .disabled(!canManage || isUpdating)

                Button { pendingAction = .suspended } label: {
                    actionLabel(.suspended, tint: AppTheme.accentDestructive)
                }
                .disabled(!canManage || isUpdating)

                Button { pendingAction = .banned } label: {
                    actionLabel(.banned, tint: AppTheme.accentDestructive)
                }
                .disabled(!canManage || isUpdating)

                Button { pendingAction = .unblocked } label: {
                    actionLabel(.unblocked, tint: AppTheme.accentPrimary)
                }
                .disabled(!canManage || isUpdating)

                Button { pendingAction = .deactivated } label: {
                    actionLabel(.deactivated, tint: AppTheme.accentDestructive)
                }
                .disabled(!canManage || isUpdating)
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
            AppTheme.accentPrimary
        case .warned:
            AppTheme.accentSupport
        case .suspendedUntil, .blocked, .bannedPermanent, .deactivated:
            AppTheme.accentDestructive
        }
    }

    private func actionLabel(_ action: UserAdminAction, tint: Color) -> some View {
        Label(action.title, systemImage: action.systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: AppTheme.iconButtonSize)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: AppTheme.iconButtonRadius, style: .continuous))
    }

    private func ensureSelectedOrganization(allowFilteredMatch: Bool = false) {
        let candidates = allowFilteredMatch ? filteredOrganizations : organizations
        if let selectedOrganizationID, candidates.contains(where: { $0.id == selectedOrganizationID }) {
            return
        }
        selectedOrganizationID = candidates.first?.id ?? organizations.first?.id
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

private struct UserAuditHistoryCard: View {
    let userId: String
    @State private var items: [UserAuditHistoryItem] = []
    @State private var isLoading = false

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                SectionHeaderBlock(
                    title: AppStrings.UserManagement.auditHistoryTitle,
                    subtitle: AppStrings.UserManagement.auditHistorySubtitle
                )

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if items.isEmpty {
                    Text(AppStrings.UserManagement.auditHistoryEmpty)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.textSecondary)
                } else {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.actionType)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.textPrimary)

                                Spacer(minLength: 8)

                                Text(LocalizationStore.dateString(from: item.createdAt, dateStyle: .short, timeStyle: .short))
                                    .font(.caption2)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }

                            Text(item.reason)
                                .font(.caption)
                                .foregroundStyle(AppTheme.textSecondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .task(id: userId) {
            await load()
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let snapshot = try await Firestore.firestore()
                .collection("auditLogs")
                .whereField("targetUserId", isEqualTo: userId)
                .order(by: "createdAt", descending: true)
                .limit(to: 20)
                .getDocuments()

            items = snapshot.documents.map { document in
                let data = document.data()
                return UserAuditHistoryItem(
                    id: document.documentID,
                    actionType: data["actionType"] as? String ?? "unknown",
                    reason: data["reason"] as? String ?? "",
                    createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? .distantPast
                )
            }
        } catch {
            items = []
        }
    }
}

private struct UserAuditHistoryItem: Identifiable {
    let id: String
    let actionType: String
    let reason: String
    let createdAt: Date
}

private struct UserAvatarView: View {
    let user: AppUser
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(AppTheme.accentPrimary.opacity(0.12))

            if let avatarURL = user.avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure, .empty:
                        initials
                    @unknown default:
                        initials
                    }
                }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initials: some View {
        Text(user.initials)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppTheme.accentPrimary)
    }
}

private struct UserStatusBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(tint.opacity(0.10), in: Capsule())
            .lineLimit(1)
    }
}

private struct UserManagementMetadataRow: View {
    let systemImage: String
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.accentPrimary)
                .frame(width: 18)

            Text(title)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)

            Spacer(minLength: 8)

            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(AppTheme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }
}
