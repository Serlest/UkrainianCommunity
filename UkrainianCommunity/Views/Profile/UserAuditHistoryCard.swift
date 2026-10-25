import SwiftUI

struct UserAuditHistoryCard: View {
    let userID: String
    let actor: AppUser?
    let refreshToken: String
    @StateObject private var model: ManagedUserAuditStore

    init(userID: String, actor: AppUser?, refreshToken: String, load: @escaping ManagedUserAuditStore.Read) {
        self.userID = userID; self.actor = actor; self.refreshToken = refreshToken
        _model = StateObject(wrappedValue: ManagedUserAuditStore(read: load))
    }

    var body: some View {
        AppEditorSectionCard {
            VStack(alignment: .leading, spacing: AppTheme.dashboardSpacing) {
                SectionHeaderBlock(title: AppStrings.UserManagement.auditHistoryTitle, subtitle: AppStrings.UserManagement.auditHistorySubtitle)
                if model.isLoading && model.items.isEmpty || !model.hasLoaded && !model.failed {
                    ProgressView().frame(maxWidth: .infinity).accessibilityIdentifier("user.audit.loading")
                } else if model.hasLoaded && model.items.isEmpty && !model.failed {
                    Text(AppStrings.UserManagement.auditHistoryEmpty).foregroundStyle(AppTheme.textSecondary)
                        .accessibilityIdentifier("user.audit.empty")
                }
                if model.failed {
                    InlineMessageCard(style: .error, message: AppStrings.UserManagement.auditHistoryLoadError)
                    Button(AppStrings.UserManagement.retry) { Task { await model.retry(userID: userID) } }
                        .accessibilityIdentifier("user.audit.retry")
                }
                ForEach(model.items) { item in
                    UserManagementAuditRow(title: item.title,
                        date: item.createdAt == .distantPast ? AppStrings.Common.notAvailable : LocalizationStore.dateString(from: item.createdAt, dateStyle: .short, timeStyle: .short),
                        reason: item.reason, performedBy: item.performedBy, changeSummary: item.changeSummary)
                        .accessibilityIdentifier("user.audit.item.\(item.id)")
                }
                if model.hasMore {
                    Button(AppStrings.UserManagement.loadMore) { Task { await model.more(userID: userID) } }
                        .disabled(model.isLoading).accessibilityIdentifier("user.audit.more")
                }
            }
        }
        .task(id: "\(userID)|\(actor?.id ?? "")|\(PermissionService.canManageUsers(user: actor))|\(refreshToken)") {
            await model.ensure(userID: userID, actor: actor, refreshToken: refreshToken)
        }
        .accessibilityIdentifier("user.audit.section")
    }
}
