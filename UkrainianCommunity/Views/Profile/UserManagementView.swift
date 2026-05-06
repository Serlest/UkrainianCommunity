import Combine
import FirebaseFirestore
import SwiftUI

private enum RolesAuditIssue: String, Identifiable {
    case moderatorSectionsMissing
    case adminGlobalRoleMismatch
    case ownerGlobalRoleMismatch
    case userGlobalRoleMissing
    case blockedStatusMismatch

    var id: String { rawValue }

    var title: String {
        switch self {
        case .moderatorSectionsMissing:
            AppStrings.UserManagement.issueModeratorSectionsMissing
        case .adminGlobalRoleMismatch:
            AppStrings.UserManagement.issueAdminGlobalRoleMismatch
        case .ownerGlobalRoleMismatch:
            AppStrings.UserManagement.issueOwnerGlobalRoleMismatch
        case .userGlobalRoleMissing:
            AppStrings.UserManagement.issueUserGlobalRoleMissing
        case .blockedStatusMismatch:
            AppStrings.UserManagement.issueBlockedStatusMismatch
        }
    }
}

private struct RolesAuditEntry: Identifiable {
    let uid: String
    let legacyRole: String
    let globalRole: String?
    let moderatorSectionsCount: Int
    let accountStatus: String
    let issues: [RolesAuditIssue]

    var id: String { uid }
}

@MainActor
private final class RolesAuditViewModel: ObservableObject {
    @Published private(set) var entries: [RolesAuditEntry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: AppError?

    private let usersCollection = Firestore.firestore().collection("users")
    private var loadTask: Task<Void, Never>?
    private var hasLoaded = false

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await startLoad(force: false)
    }

    func refresh() async {
        await startLoad(force: true)
    }

    func reload() {
        Task {
            await refresh()
        }
    }

    private func startLoad(force: Bool) async {
        guard force || !hasLoaded else { return }

        loadTask?.cancel()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performLoad()
        }
        loadTask = task
        await task.value
    }

    private func performLoad() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let snapshot = try await usersCollection.getDocuments()
            guard !Task.isCancelled else { return }

            entries = snapshot.documents.compactMap(makeEntry(from:)).sorted { $0.uid < $1.uid }
            error = nil
            hasLoaded = true
        } catch {
            guard !Task.isCancelled else { return }
            self.error = .network
        }
    }

    private func makeEntry(from document: QueryDocumentSnapshot) -> RolesAuditEntry? {
        let data = document.data()

        let legacyRole = data["role"] as? String ?? UserRole.user.rawValue
        let globalRole = data["globalRole"] as? String
        let moderatorSections = data["moderatorSections"] as? [String]
        let moderatorSectionsCount = moderatorSections?.count ?? 0
        let isBlocked = data["isBlocked"] as? Bool ?? false
        let accountStatus = data["accountStatus"] as? String ?? AccountStatus.active.rawValue

        var issues: [RolesAuditIssue] = []

        if legacyRole == UserRole.moderator.rawValue, moderatorSectionsCount == 0 {
            issues.append(.moderatorSectionsMissing)
        }
        if legacyRole == UserRole.admin.rawValue, globalRole != GlobalRole.topAdmin.rawValue {
            issues.append(.adminGlobalRoleMismatch)
        }
        if legacyRole == UserRole.owner.rawValue, globalRole != GlobalRole.owner.rawValue {
            issues.append(.ownerGlobalRoleMismatch)
        }
        if legacyRole == UserRole.user.rawValue, globalRole == nil {
            issues.append(.userGlobalRoleMissing)
        }
        if isBlocked, accountStatus == AccountStatus.active.rawValue {
            issues.append(.blockedStatusMismatch)
        }

        guard !issues.isEmpty else { return nil }

        return RolesAuditEntry(
            uid: data["id"] as? String ?? document.documentID,
            legacyRole: legacyRole,
            globalRole: globalRole,
            moderatorSectionsCount: moderatorSectionsCount,
            accountStatus: accountStatus,
            issues: issues
        )
    }
}

struct UserManagementView: View {
    @EnvironmentObject private var authState: AuthState
    @StateObject private var viewModel = RolesAuditViewModel()

    private var canAccessRolesAudit: Bool {
        guard let user = authState.user else { return false }
        return user.globalRole == .owner || user.globalRole == .topAdmin
    }

    var body: some View {
        Group {
            if !canAccessRolesAudit {
                stateView(
                    systemImage: "lock.shield",
                    title: AppStrings.UserManagement.title,
                    subtitle: AppStrings.UserManagement.permission
                )
            } else if viewModel.isLoading && viewModel.entries.isEmpty {
                ProgressView(AppStrings.UserManagement.title)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.entries.isEmpty, viewModel.error != nil {
                stateView(
                    systemImage: "exclamationmark.triangle",
                    title: AppStrings.UserManagement.title,
                    subtitle: AppStrings.UserManagement.loadError
                ) {
                    Button(AppStrings.UserManagement.retry) {
                        viewModel.reload()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if viewModel.entries.isEmpty {
                stateView(
                    systemImage: "checkmark.shield",
                    title: AppStrings.UserManagement.title,
                    subtitle: AppStrings.UserManagement.empty
                )
            } else {
                List {
                    Section {
                        Text(AppStrings.UserManagement.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .listRowBackground(AppTheme.surfacePrimary)

                    ForEach(viewModel.entries) { entry in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(entry.uid)
                                .font(.headline.monospaced())

                            MetadataRow(
                                label: AppStrings.UserManagement.legacyRole,
                                value: legacyRoleTitle(entry.legacyRole),
                                systemImage: "person.badge.key"
                            )
                            MetadataRow(
                                label: AppStrings.UserManagement.globalRole,
                                value: globalRoleTitle(entry.globalRole),
                                systemImage: "person.crop.circle.badge.checkmark"
                            )
                            MetadataRow(
                                label: AppStrings.UserManagement.moderatorSections,
                                value: String(entry.moderatorSectionsCount),
                                systemImage: "square.grid.2x2"
                            )
                            MetadataRow(
                                label: AppStrings.UserManagement.accountStatus,
                                value: accountStatusTitle(entry.accountStatus),
                                systemImage: "checkmark.shield"
                            )

                            VStack(alignment: .leading, spacing: 6) {
                                Text(AppStrings.UserManagement.issue)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(AppTheme.textSecondary)

                                ForEach(entry.issues) { issue in
                                    Label(issue.title, systemImage: "exclamationmark.circle")
                                        .font(.subheadline)
                                        .foregroundStyle(AppTheme.textPrimary)
                                }
                            }
                        }
                        .padding(.vertical, 6)
                        .listRowBackground(AppTheme.surfacePrimary)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(AppTheme.pageBackground)
            }
        }
        .background(AppTheme.pageBackground)
        .tint(AppTheme.accentPrimary)
        .navigationTitle(AppStrings.UserManagement.title)
        .task {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    private func stateView<ActionContent: View>(
        systemImage: String,
        title: String,
        subtitle: String,
        @ViewBuilder actionContent: () -> ActionContent = { EmptyView() }
    ) -> some View {
        VStack {
            Spacer(minLength: 0)
            VStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.system(size: 44))
                    .foregroundStyle(AppTheme.textSecondary)

                Text(title)
                    .font(.title3.weight(.semibold))

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)

                actionContent()
            }
            .frame(maxWidth: 320)
            .padding(.horizontal, 24)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.pageBackground)
    }

    private func legacyRoleTitle(_ rawValue: String) -> String {
        switch UserRole(rawValue: rawValue) {
        case .owner:
            AppStrings.Roles.owner
        case .admin:
            AppStrings.Roles.admin
        case .moderator:
            AppStrings.Roles.moderator
        case .user, nil:
            AppStrings.Roles.user
        }
    }

    private func globalRoleTitle(_ rawValue: String?) -> String {
        guard let rawValue, let role = GlobalRole(rawValue: rawValue) else {
            return AppStrings.Common.notAvailable
        }
        return role.title
    }

    private func accountStatusTitle(_ rawValue: String) -> String {
        guard let status = AccountStatus(rawValue: rawValue) else {
            return rawValue
        }
        return status.title
    }
}

#Preview {
    NavigationStack {
        UserManagementView()
    }
    .environmentObject(AuthState())
}
